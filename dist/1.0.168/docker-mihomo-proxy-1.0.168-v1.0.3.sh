#!/bin/sh
# RA70 1.0.168: preserve the 1.0.140 managed/unmanaged routing contract.
set -u
CORE=/data/router-docker-1.0.168
fail_early() { printf '错误：%s\n' "$*" >&2; exit 1; }
VERSION_FILE=/usr/share/xiaoqiang/xiaoqiang_version
[ ! -L "$CORE/installed" ] || fail_early '托管安装标记不能为符号链接。'
[ "$(awk '$1=="option" && $2=="ROM" {gsub(/[\047\042]/,"",$3);print $3}' "$VERSION_FILE")" = 1.0.168 ] &&
[ "$(awk '$1=="option" && $2=="HARDWARE" {gsub(/[\047\042]/,"",$3);print $3}' "$VERSION_FILE")" = RA70 ] || fail_early '仅适用于 RA70 原厂 1.0.168。'
# Stock curl does not reliably discover the otherwise valid system CA bundle.
# Preserve any explicit trust-store choice from the caller; never skip TLS checks.
if [ -z "${CURL_CA_BUNDLE:-}" ] && [ -z "${SSL_CERT_FILE:-}" ] &&
   [ -z "${SSL_CERT_DIR:-}" ] && [ -r /etc/ssl/certs/ca-certificates.crt ]; then
    export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
fi
if [ -e "$CORE/installed" ]; then
    [ ! -L "$CORE" ] && [ ! -L "$CORE/runtime" ] || fail_early '托管目录不能为符号链接。'
    case "$(cat "$CORE/installed")" in 1.1.0|1.1.1|1.1.2|1.1.3|1.1.4|1.1.5) ;; *) fail_early '请先将 Docker 自启修复升级到 1.1.5。' ;; esac
    [ -f "$CORE/runtime/proxy.sh" ] || fail_early '托管代理入口缺失，请核对 Docker 核心。'
    (cd "$CORE/runtime" && sha256sum -c SHA256SUMS >/dev/null) || fail_early '托管运行文件已改变。'
    (cd / && sha256sum -c "$CORE/owned.sha256" >/dev/null) || fail_early '托管服务或页面已改变。'
    exec /bin/sh "$CORE/runtime/proxy.sh" "$@"
fi
INIT=/etc/init.d/mi_docker
BIN_DIR=/mnt/docker_disk/mi_docker/docker-binaries
DATA_ROOT=/mnt/docker_disk/mi_docker/lib/docker
EXEC_ROOT=/mnt/docker_disk/mi_docker/run/dock
STATE_DIR=/data/docker-mihomo-proxy-toggle-1.0.168
LOCK=/tmp/docker-mihomo-proxy-toggle-1.0.168.lock
LOG=/tmp/docker-mihomo-proxy-toggle-1.0.168.log
PROXY=http://10.31.0.66:7890
BYPASS='localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local,.lan'
DOCKER=$BIN_DIR/docker
DAEMON=$BIN_DIR/dockerd
DOCKER_PATH=/usr/sbin:/usr/bin:/sbin:/bin:$BIN_DIR
TMP_INIT=
LOCKED=false
NEW_PID=

say() { printf '%s\n' "$*"; }
fail() { say "错误：$*" >&2; exit 1; }
usage() {
    say "用法：sh $0 on|off|status [--no-restart] [http://NAS_IP:端口]"
    say '  on             开启 Docker 拉取镜像代理，并重启 Docker'
    say '  off            关闭 Docker 拉取镜像代理，并重启 Docker'
    say '  status         查看启动配置和当前运行状态'
    say '  --no-restart   仅保存启动配置，当前 Docker 暂不受影响'
    say '默认代理：http://10.31.0.66:7890；仅适用这台小米路由器的 mi_docker 启动方式。'
    say '脚本不修改 NAS；开启前需确保 Mihomo 已允许局域网访问。'
    say '重启会短暂中断 Lucky、Portainer 等容器，不重启路由器，不修改全局代理和路由。'
}
cleanup() {
    [ -z "$TMP_INIT" ] || rm -f "$TMP_INIT"
    if [ "$LOCKED" = true ]; then
        rm -f "$LOCK/pid"
        rmdir "$LOCK" 2>/dev/null || true
    fi
}
trap cleanup EXIT
# Allow an already-authorized toggle to finish if its SSH session disconnects.
trap '' HUP

one_pid() {
    pid_list=$(pidof dockerd 2>/dev/null || true)
    set -- $pid_list
    [ "$#" = 1 ] || return 1
    case "$1" in *[!0-9]*|'') return 1 ;; esac
    [ "$(readlink "/proc/$1/exe" 2>/dev/null)" = "$DAEMON" ] || return 1
    printf '%s\n' "$1"
}
ready() {
    # BusyBox 1.25 timeout uses -t, unlike GNU timeout.
    timeout -t 5 "$DOCKER" info >/dev/null 2>&1
}
wait_ready() {
    wait_count=0
    while [ "$wait_count" -lt 15 ]; do
        ready && return 0
        wait_count=$((wait_count + 1))
        sleep 1
    done
    return 1
}
show_status() {
    say '【下次 Docker 启动时的配置】'
    if grep -q '^[[:space:]]*env .*HTTP_PROXY="http://' "$INIT"; then
        sed -n 's/^[[:space:]]*env .* HTTP_PROXY="\([^"]*\)".*/代理：\1/p' "$INIT" | head -n 1
    else
        say '代理：关闭（或尚未使用此脚本配置）'
    fi
    say '【当前运行状态】'
    if ready; then
        "$DOCKER" info --format 'HTTP={{.HTTPProxy}}  HTTPS={{.HTTPSProxy}}  NO_PROXY={{.NoProxy}}'
        "$DOCKER" ps --format '{{.Names}}  {{.Status}}'
    else
        say 'Docker 当前不可连接；启动配置不代表已生效。'
    fi
}

ACTION=${1:-}
if [ "$ACTION" = -h ] || [ "$ACTION" = --help ]; then usage; exit 0; fi
if [ -z "$ACTION" ]; then
    [ -t 0 ] || { usage; exit 2; }
    say '1) 开启代理并重启 Docker'
    say '2) 关闭代理并重启 Docker'
    say '3) 查看状态'
    say '0) 退出'
    printf '请选择：'
    read -r choice || exit 2
    case "$choice" in 1) ACTION=on ;; 2) ACTION=off ;; 3) ACTION=status ;; 0) exit 0 ;; *) exit 2 ;; esac
else
    shift
fi
RESTART=true
for option in "$@"; do
    case "$option" in
        --no-restart) RESTART=false ;;
        http://*) PROXY=$option ;;
        *) usage; exit 2 ;;
    esac
done
case "$ACTION" in on|off|status) ;; *) usage; exit 2 ;; esac
[ "$(id -u)" = 0 ] || fail '请使用 root 执行。'
[ -f "$INIT" ] && [ -x "$DOCKER" ] && [ -x "$DAEMON" ] || fail '未找到 Docker。原版 1.0.168 请先部署 Docker 核心与自启修复。'

[ ! -L "$INIT" ] && [ ! -L "$STATE_DIR" ] || fail '启动文件或备份路径不能为符号链接。'
if [ "$(sha256sum "$INIT" | awk '{print $1}')" != '4cd782fb90feca23ffd91653a22f82b99274482694db70784544c5660adac01a' ]; then
    [ -f "$STATE_DIR/current.sha256" ] && [ ! -L "$STATE_DIR/current.sha256" ] && sha256sum -c "$STATE_DIR/current.sha256" >/dev/null 2>&1 || fail '未托管的启动脚本不是已核对原厂版本或本脚本结果，拒绝覆盖。'
fi
if [ "$ACTION" = status ]; then show_status; exit 0; fi

# No credentials, shell syntax, DNS names or ambiguous addresses in generated shell.
printf '%s\n' "$PROXY" | awk '
    /^http:\/\/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ {
        value=$0; sub(/^http:\/\//,"",value); split(value,p,":")
        split(p[1],a,"."); for(i=1;i<=4;i++) if(a[i]>255) exit 1
        if(p[2]<1 || p[2]>65535) exit 1
        valid=1
    }
    END {if(!valid) exit 1}
' || fail '代理必须是 http://IPv4:端口。'
for required in awk cmp mktemp timeout pidof readlink curl; do
    command -v "$required" >/dev/null 2>&1 || fail "缺少命令：$required"
done
mkdir "$LOCK" 2>/dev/null || fail "已有操作或残留锁：$LOCK；请先确认没有其他脚本在执行。"
LOCKED=true
printf '%s\n' "$$" > "$LOCK/pid"

if [ "$ACTION" = on ]; then
    say '检查 Mihomo 到 Docker Hub 的连接……'
    http_code=$(curl -sS --connect-timeout 5 --max-time 20 --noproxy '' -x "$PROXY" \
        -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/) || fail '代理不可达或 TLS 验证失败；未改配置。'
    case "$http_code" in 200|401) ;; *) fail "镜像仓库返回 HTTP $http_code；未改配置。" ;; esac
fi

TMP_INIT=$(mktemp /etc/init.d/.mi_docker.proxy.XXXXXX) || fail '无法创建配置暂存文件。'
# Rewrite only the two known Xiaomi dockerd commands. Reject unrelated wrappers.
awk -v mode="$ACTION" -v proxy="$PROXY" -v bypass="$BYPASS" '
    /^[[:space:]]*#/ {print; next}
    /dockerd --data-root / {
        match($0,/dockerd --data-root /)
        prefix=substr($0,1,RSTART-1); tail=substr($0,RSTART)
        match(prefix,/^[[:space:]]*/); indent=substr(prefix,1,RLENGTH)
        sub(/^[[:space:]]*/,"",prefix); sub(/[[:space:]]*$/,"",prefix)
        if(prefix!="" && prefix!~/^env PATH="\$BIN_DOCKER_PATH"( (HTTP_PROXY|HTTPS_PROXY|NO_PROXY|ALL_PROXY|http_proxy|https_proxy|no_proxy|all_proxy)="[^"]*")*$/) {bad=1; exit}
        if(tail!~/^dockerd --data-root \$MI_DOCKER_PATH\/lib\/docker --exec-root \$MI_DOCKER_PATH\/run\/dock[[:space:]]*&[[:space:]]*$/) {bad=1; exit}
        target=(mode=="on" ? proxy : ""); excluded=(mode=="on" ? bypass : "")
        print indent "env PATH=\"$BIN_DOCKER_PATH\" HTTP_PROXY=\"" target "\" HTTPS_PROXY=\"" target "\" NO_PROXY=\"" excluded "\" ALL_PROXY=\"\" http_proxy=\"\" https_proxy=\"\" no_proxy=\"\" all_proxy=\"\" " tail
        count++; next
    }
    {print}
    END {if(bad || count!=2) exit 1}
' "$INIT" > "$TMP_INIT" || fail '启动脚本结构不符，拒绝覆盖；原文件未修改。'
/bin/sh -n "$TMP_INIT" || fail '新配置语法错误；原文件未修改。'
chmod 0755 "$TMP_INIT" || fail '设置配置权限失败。'

mkdir -p "$STATE_DIR" || fail '无法创建备份目录。'
chmod 0700 "$STATE_DIR"
if [ "$RESTART" = true ]; then
    OLD_PID=$(one_pid) || fail '需要唯一且路径正确的 dockerd 进程；可使用 --no-restart 仅保存配置。'
    ready || fail '当前 Docker 不健康；未修改配置。'
    # This script may only relaunch the exact arguments used by the known firmware.
    tr '\000' '\n' < "/proc/$OLD_PID/cmdline" | sed '1d' > "$STATE_DIR/arguments.actual"
    printf '%s\n' --data-root "$DATA_ROOT" --exec-root "$EXEC_ROOT" > "$STATE_DIR/arguments.expected"
    cmp -s "$STATE_DIR/arguments.actual" "$STATE_DIR/arguments.expected" || fail 'dockerd 有额外启动参数，拒绝自动重启。'
    "$DOCKER" ps -q > "$STATE_DIR/running.ids" || fail '读取运行中容器失败。'
    tr '\000' '\n' < "/proc/$OLD_PID/environ" | \
        grep -E '^(HTTP_PROXY|HTTPS_PROXY|NO_PROXY|ALL_PROXY|http_proxy|https_proxy|no_proxy|all_proxy)=' > "$STATE_DIR/runtime.env" || true
    chmod 0600 "$STATE_DIR/runtime.env" "$STATE_DIR/running.ids"
fi
cp -p "$INIT" "$STATE_DIR/mi_docker.previous" || fail '备份启动脚本失败。'
mv -f "$TMP_INIT" "$INIT" || fail '保存启动脚本失败。'
TMP_INIT=
sha256sum "$INIT" > "$STATE_DIR/current.sha256"
say "启动配置已设为 $ACTION。上一版备份：$STATE_DIR/mi_docker.previous"
if [ "$RESTART" = false ]; then
    say '本次未重启 Docker；当前代理不变，下次 Docker 启动后生效。'
    exit 0
fi

launch() {
    launch_mode=$1
    (
        trap '' HUP
        unset HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY http_proxy https_proxy no_proxy all_proxy
        PATH=$DOCKER_PATH; export PATH
        if [ "$launch_mode" = on ]; then
            HTTP_PROXY=$PROXY; HTTPS_PROXY=$PROXY; NO_PROXY=$BYPASS
            export HTTP_PROXY HTTPS_PROXY NO_PROXY
        elif [ "$launch_mode" = previous ]; then
            while IFS='=' read -r key value; do
                case "$key" in HTTP_PROXY|HTTPS_PROXY|NO_PROXY|ALL_PROXY|http_proxy|https_proxy|no_proxy|all_proxy) export "$key=$value" ;; esac
            done < "$STATE_DIR/runtime.env"
        fi
        exec "$DAEMON" --data-root "$DATA_ROOT" --exec-root "$EXEC_ROOT"
    ) </dev/null >> "$LOG" 2>&1 &
    NEW_PID=$!
}
restore_init() {
    rollback_tmp=$(mktemp /etc/init.d/.mi_docker.rollback.XXXXXX) || return 1
    if cp -p "$STATE_DIR/mi_docker.previous" "$rollback_tmp" && mv -f "$rollback_tmp" "$INIT"; then
        sha256sum "$INIT" > "$STATE_DIR/current.sha256"
        return 0
    fi
    rm -f "$rollback_tmp"
    return 1
}
restore_containers() {
    failed=0
    while IFS= read -r container_id; do
        case "$container_id" in ''|*[!a-f0-9]*) continue ;; esac
        running=$(timeout -t 5 "$DOCKER" inspect --format '{{.State.Running}}' "$container_id" 2>/dev/null || true)
        if [ "$running" != true ]; then
            timeout -t 30 "$DOCKER" start "$container_id" >/dev/null 2>&1 || {
                say "警告：容器 $container_id 未能恢复，请检查 Docker 日志。" >&2
                failed=1
            }
        fi
    done < "$STATE_DIR/running.ids"
    return "$failed"
}
say '正在重启 Docker，运行中的容器将短暂中断……'
if [ "$(one_pid)" != "$OLD_PID" ]; then
    restore_init || true
    fail 'Docker 进程已变化，已尝试恢复启动配置；未停止其他进程。'
fi
kill -TERM "$OLD_PID" || { restore_init; fail '无法停止 Docker。'; }
count=0
while kill -0 "$OLD_PID" 2>/dev/null && [ "$count" -lt 40 ]; do sleep 1; count=$((count+1)); done
if kill -0 "$OLD_PID" 2>/dev/null; then
    restore_init || true
    fail 'Docker 未在 40 秒内退出，未强制终止；已尝试恢复启动配置，请检查服务。'
fi
launch "$ACTION"
if ! wait_ready; then
    say '新配置启动未就绪，尝试恢复旧配置……' >&2
    if kill -0 "$NEW_PID" 2>/dev/null; then
        kill -TERM "$NEW_PID" 2>/dev/null || true
        count=0
        while kill -0 "$NEW_PID" 2>/dev/null && [ "$count" -lt 30 ]; do sleep 1; count=$((count+1)); done
    fi
    restore_init || fail "恢复文件失败，请使用 $STATE_DIR/mi_docker.previous 手动恢复。"
    if pidof dockerd >/dev/null 2>&1; then fail "仍有 dockerd 进程，未重复启动；日志：$LOG"; fi
    launch previous
    wait_ready || fail "旧配置也未能启动，请检查 $LOG"
    restore_containers || true
    fail '本次切换失败，已恢复旧配置及 Docker；请检查日志。'
fi
restore_containers || fail '代理已切换，但部分容器未恢复；请手动检查。'
say '切换完成。'
show_status
