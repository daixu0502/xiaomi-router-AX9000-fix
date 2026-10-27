#!/bin/sh
# Managed counterpart of the independently uploaded docker-mihomo-proxy.sh.
set -eu
. /data/router-docker-1.0.168/runtime/common.sh
check_rom
[ "$(id -u)" = 0 ] || die '请通过 root SSH 执行。'
[ -f "$BASE/installed" ] || die '尚未安装 Docker 自启修复。'
case "$(cat "$BASE/installed")" in 1.1.0|1.1.1|1.1.2|1.1.3) ;; *) die '请先将 Docker 自启修复升级到 1.1.3。' ;; esac
(cd "$BASE/runtime" && sha256sum -c SHA256SUMS >/dev/null) || die 'Docker 运行文件已改变。'
(cd / && sha256sum -c "$BASE/owned.sha256" >/dev/null) || die 'Docker 服务或页面已改变。'
ACTION=${1:-status}
[ "$#" -eq 0 ] || shift
RESTART=1
PROXY=http://10.31.0.66:7890
for option in "$@"; do
    case "$option" in --no-restart) RESTART=0 ;; http://*) PROXY=$option ;; *) die '参数错误。' ;; esac
done
case "$ACTION" in
    status|on|off) ;;
    -h|--help) echo "用法：sh $0 on|off|status [--no-restart] [http://IPv4:端口]"; exit 0 ;;
    *) die '用法：on|off|status [--no-restart] [http://IPv4:端口]' ;;
esac
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
show_status() {
    unset HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY http_proxy https_proxy no_proxy all_proxy
    load_proxy
    echo '【下次 Docker 启动时的配置】'
    if [ -f "$BASE/proxy.env" ]; then cat "$BASE/proxy.env"; else echo '代理：关闭'; fi
    echo '【当前运行状态】'
    if find_disk && check_engine && api_ready; then
        timeout -t 5 "$ENGINE/docker" --host unix:///var/run/docker.sock info --format 'HTTP={{.HTTPProxy}} HTTPS={{.HTTPSProxy}} NO_PROXY={{.NoProxy}}'
        docker_cli ps --format '{{.Names}}  {{.Status}}'
    else echo 'Docker 当前不可连接；保存配置不代表已经生效。'; fi
}
if [ "$ACTION" = status ]; then show_status; exit 0; fi
valid_proxy "$PROXY" || die '代理必须是 http://IPv4:1–65535，不支持认证信息。'
[ ! -L "$BASE/proxy.env" ] || die '代理配置不能为符号链接。'
[ ! -e "$BASE/proxy.env" ] || [ -f "$BASE/proxy.env" ] || die '代理配置不是普通文件。'
exec 8>/var/run/router-docker168-operation.lock
flock -n 8 || die '已有 Docker 部署、启停或代理切换任务。'
umask 077
if [ "$ACTION" = on ]; then
    echo '检查 Mihomo 到 Docker Hub 的连接……'
    code=$(curl -sS --connect-timeout 5 --max-time 20 --noproxy '' -x "$PROXY" -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/) || die '代理不可达或 TLS 验证失败，未修改配置。'
    case "$code" in 200|401) ;; *) die "Docker Hub 返回 HTTP $code，未修改配置。" ;; esac
else PROXY=; fi
RUNNING=
OLD=
TMP=
OLD_EXISTS=0
CHANGED=0
daemon_pid=
daemon_start=
if [ "$RESTART" = 1 ]; then
    [ "$(get docker_enable)" = 1 ] && [ "$(get docker_install)" = 1 ] || die 'Docker 开关未开启；请使用 --no-restart 仅保存配置。'
    find_disk && check_engine && api_ready || die '当前 Docker 不健康；未修改配置，可使用 --no-restart 仅保存。'
    pids=$(pidof dockerd || true)
    set -- $pids
    [ "$#" = 1 ] || die '需要唯一的托管 dockerd，未修改配置。'
    daemon_pid=$1
    case "$daemon_pid" in *[!0-9]*|'') die 'dockerd PID 无效。' ;; esac
    pidfile=/var/run/router-docker168/dockerd.pid
    [ -f "$pidfile" ] && [ ! -L "$pidfile" ] && [ "$(cat "$pidfile")" = "$daemon_pid" ] || die '不是本工具托管的 dockerd。'
    daemon_start=$(process_start "$daemon_pid")
    same_process "$daemon_pid" "$daemon_start" "$ENGINE/dockerd" || die 'dockerd 进程身份不匹配。'
    ready_limit=$(api_timeout)
fi
restore_config() {
    if [ "$OLD_EXISTS" = 1 ]; then
        copy=$(mktemp "$BASE/.proxy-rollback.XXXXXX")
        cp -p "$OLD" "$copy"
        mv -f "$copy" "$BASE/proxy.env"
    else rm -f "$BASE/proxy.env"; fi
}
cleanup() {
    rc=$?
    [ -z "$TMP" ] || rm -f "$TMP"
    [ -z "$RUNNING" ] || rm -f "$RUNNING"
    if [ "$CHANGED" = 1 ]; then restore_config || true; echo '保存的代理配置已回退，请检查 Docker 状态。' >&2; fi
    exit "$rc"
}
trap cleanup EXIT
trap '' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if [ "$RESTART" = 1 ]; then
    RUNNING=$(mktemp "$BASE/.proxy-running.XXXXXX")
    timeout -t 5 "$ENGINE/docker" --host unix:///var/run/docker.sock ps -q > "$RUNNING" || die '无法记录运行中容器，未修改配置。'
fi
if [ -f "$BASE/proxy.env" ]; then
    OLD=$(mktemp "$BASE/proxy.before.XXXXXX")
    cp -p "$BASE/proxy.env" "$OLD"
    OLD_EXISTS=1
fi
TMP=$(mktemp "$BASE/.proxy.XXXXXX")
printf 'HTTP_PROXY=%s\nHTTPS_PROXY=%s\nNO_PROXY=%s\n' "$PROXY" "$PROXY" 'localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local,.lan' > "$TMP"
CHANGED=1
mv -f "$TMP" "$BASE/proxy.env"
TMP=
load_proxy
if [ "$RESTART" = 0 ]; then
    CHANGED=0
    echo '仅保存配置，下次 Docker 启动后生效；当前 Docker 未重启。'
    exit 0
fi
stop_wait() {
    /etc/init.d/mi_docker stop || return 1
    local count=0
    while pidof dockerd >/dev/null 2>&1; do
        [ "$count" -lt 65 ] || return 1
        sleep 1; count=$((count+1))
    done
}
restore_running() {
    local container running failed=0
    while IFS= read -r container; do
        case "$container" in ''|*[!a-f0-9]*) continue ;; esac
        running=$(timeout -t 5 "$ENGINE/docker" --host unix:///var/run/docker.sock inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)
        if [ "$running" != true ]; then
            timeout -t 30 "$ENGINE/docker" --host unix:///var/run/docker.sock start "$container" >/dev/null || { echo "警告：容器 $container 未恢复。" >&2; failed=1; }
        fi
    done < "$RUNNING"
    return "$failed"
}
same_process "$daemon_pid" "$daemon_start" "$ENGINE/dockerd" || die 'Docker 进程在切换前改变，未停止其他进程。'
echo '正在通过 procd 重启 Docker，记录的运行中容器会短暂中断。'
stop_wait || die 'Docker 未正常停止，未启动第二个实例。'
if ! /etc/init.d/mi_docker start || ! wait_api "$((ready_limit+15))"; then
    echo '新配置启动未就绪，尝试恢复旧配置和 Docker……' >&2
    # procd owns the instance; no process is directly killed by this script.
    stop_wait || die '新实例未正常退出，保存配置将回退，未强杀进程。'
    restore_config
    CHANGED=0
    /etc/init.d/mi_docker start && wait_api "$((ready_limit+15))" || die '旧配置也未恢复就绪，请检查 logread -e router-docker168。'
    restore_running || true
    die '本次切换失败，已恢复旧配置和 Docker。'
fi
CHANGED=0
restore_running || die '代理已切换，部分容器未恢复，请人工检查。'
echo '代理切换完成。'
show_status
