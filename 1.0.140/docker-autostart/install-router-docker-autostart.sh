#!/bin/sh
# AX9000 stock firmware mi_docker repair, v1.0.0. No downloads or disk formatting.
set -eu
BASE=/data/router-docker-autostart
INIT=/etc/init.d/mi_docker
BIN=/mnt/docker_disk/mi_docker/docker-binaries
VERSION=1.0.0
START_NOW=1
ALLOW_RESTART=0
PREPARE=0
case "${1:-}" in
    --no-start) START_NOW=0 ;;
    --prepare) START_NOW=0; PREPARE=1 ;;
    --restart) ALLOW_RESTART=1 ;;
    '') ;;
    *) echo "用法：sh $0 [--no-start|--restart|--prepare]"; exit 2 ;;
esac
die() { echo "错误：$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die '请在路由器上以 root 运行。'
[ -f "$INIT" ] && [ -f /lib/functions/procd.sh ] || die '仅支持带 mi_docker 的小米官方固件。'
grep -q '^DOCKER_PATH=/mnt/docker_disk$' "$INIT" || die 'Docker 安装路径与本脚本不符，未修改。'
for tool in awk md5sum mktemp flock timeout uci ubus; do
    command -v "$tool" >/dev/null || die "缺少命令：$tool"
done
if [ "$PREPARE" = 0 ]; then
    awk '$2=="/mnt/docker_disk" && $3=="ext4" && $4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts || die '原 Docker USB 磁盘尚未挂载。出厂恢复后应先拔下原盘，运行 --prepare，再接回原盘。'
    for tool in dockerd docker containerd containerd-shim runc docker-proxy docker-init; do
        [ -x "$BIN/$tool" ] || die "缺少 $BIN/$tool；请先用官方功能安装 Docker，本脚本不是 Docker 安装器。"
    done
    [ -d /mnt/docker_disk/mi_docker/lib/docker ] || die '未找到原 Docker 数据目录。'
fi
[ -d /data ] && [ ! -L "$BASE" ] || die '持久化目录异常。'
exec 8>/var/run/mi-docker-deploy.lock
flock -n 8 || die '已有部署操作。'
STAGE=$(mktemp -d /tmp/mi-docker-fix.XXXXXX)
cleanup() {
    # Only explicitly named files created in this mktemp directory are removed.
    for file in launch.sh service.sh proxy.sh proxy.env init running.ids legacy-proxy; do rm -f "$STAGE/$file"; done
    rmdir "$STAGE" 2>/dev/null || true
}
trap cleanup EXIT

cat > "$STAGE/launch.sh" <<'LAUNCH'
#!/bin/sh
set -u
BASE=/data/router-docker-autostart
DISK=/mnt/docker_disk
BIN=$DISK/mi_docker/docker-binaries
DATA=$DISK/mi_docker/lib/docker
RUN=/var/run/mi-docker-managed
LOG=/tmp/mi-docker-startup.log
DAEMON_LOG=/tmp/mi-docker-daemon.log
umask 077
rotate() {
    [ ! -f "$1" ] || [ "$(wc -c < "$1")" -lt "$2" ] || mv -f "$1" "$1.previous"
}
rotate "$LOG" 131072
rotate "$DAEMON_LOG" 2097152
note() { printf '%s [pid=%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$$" "$*" >> "$LOG"; }
trap 'note "启动等待被停止"; exit 0' TERM INT
# The lock FD survives exec; kernel releases it even after a crash.
exec 9>/var/run/mi-docker-managed.lock
flock -n 9 || { note '拒绝重复启动：已有托管进程'; exit 1; }
disk_ready() {
    local device
    device=$(awk '$2=="/mnt/docker_disk" && $3=="ext4" && $4 ~ /(^|,)rw(,|$)/ {print $1; exit}' /proc/mounts)
    [ -n "$device" ] && [ -b "$device" ] || return 1
    [ -d "$DATA" ] && [ ! -L "$DATA" ] || return 1
    for binary in docker dockerd containerd containerd-shim runc docker-proxy docker-init; do
        [ -x "$BIN/$binary" ] || return 1
    done
}
note '开始一次启动尝试；等待真实 ext4 磁盘和原数据目录，最长 300 秒'
elapsed=0
until disk_ready; do
    [ "$elapsed" -lt 300 ] || { note '失败：磁盘或 Docker 文件 300 秒内未就绪；交由 procd 有限重试'; exit 1; }
    [ $((elapsed % 30)) -ne 0 ] || note "仍在等待磁盘，已等待 ${elapsed} 秒"
    sleep 5
    elapsed=$((elapsed+5))
done
[ "$(uci -q get mi_docker.settings.docker_enable)" = 1 ] || { note 'Docker 开关已关闭，不启动'; exit 1; }
if pidof dockerd >/dev/null 2>&1; then note '失败：发现非本次启动的 dockerd，拒绝运行第二个实例'; exit 1; fi
mkdir -p "$RUN"
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$BIN
export PATH
unset HTTP_PROXY HTTPS_PROXY NO_PROXY ALL_PROXY http_proxy https_proxy no_proxy all_proxy
if [ -f "$BASE/proxy.env" ]; then
    while IFS='=' read -r key value; do
        case "$key" in HTTP_PROXY|HTTPS_PROXY|NO_PROXY) export "$key=$value" ;; esac
    done < "$BASE/proxy.env"
fi
note "磁盘已就绪；exec dockerd，数据=$DATA，临时运行状态=$RUN"
# Finite readiness observer. It cannot outlive this daemon or signal another PID.
daemon_pid=$$
daemon_start=$(awk '{print $22}' /proc/$$/stat)
(
    exec 9>&-
    same_daemon() {
        [ "$(readlink /proc/$daemon_pid/exe 2>/dev/null)" = "$BIN/dockerd" ] &&
        [ "$(awk '{print $22}' /proc/$daemon_pid/stat 2>/dev/null)" = "$daemon_start" ]
    }
    n=0
    while [ "$n" -lt 30 ]; do
        sleep 2
        same_daemon || exit 0
        if timeout -t 2 "$BIN/docker" info >/dev/null 2>&1; then
            note "Docker API 已就绪；PID=$daemon_pid，由 procd 托管"
            exit 0
        fi
        n=$((n+1))
    done
    note '失败：Docker API 未在就绪检查期限内响应；TERM 请求退出，由 procd 有限重试'
    same_daemon && kill -TERM "$daemon_pid"
) </dev/null >/dev/null 2>&1 &
exec "$BIN/dockerd" --data-root "$DATA" --exec-root "$RUN" >> "$DAEMON_LOG" 2>&1
LAUNCH

cat > "$STAGE/service.sh" <<'SERVICE'
# Sourced at the end of stock mi_docker. Keep stock install/uninstall commands.
# No procd respawn beyond three consecutive failures within an hour.
start_service() {
    [ "$(uci -q get mi_docker.settings.docker_enable)" = 1 ] || return 0
    procd_open_instance managed
    procd_set_param command /data/router-docker-autostart/launch.sh
    procd_set_param respawn 3600 10 2
    procd_set_param term_timeout 60
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param file /data/router-docker-autostart/launch.sh /data/router-docker-autostart/proxy.env
    procd_close_instance
}
stop_service() { :; }
# Hotplug add/remove and old UI commands now use exactly the same supervisor.
start_from_disk() { /etc/init.d/mi_docker start; }
start_docker() { /etc/init.d/mi_docker start; }
stop_docker() { /etc/init.d/mi_docker stop; }
restart() {
    local n=0
    stop
    while pidof dockerd >/dev/null 2>&1; do
        [ "$n" -lt 60 ] || { echo 'Docker 未正常停止，拒绝启动第二个实例。' >&2; return 1; }
        sleep 1
        n=$((n+1))
    done
    start
}
SERVICE

cat > "$STAGE/proxy.sh" <<'PROXY'
#!/bin/sh
# Compatibility entrypoint for the existing docker-mihomo-proxy.sh helper.
set -eu
BASE=/data/router-docker-autostart
BIN=/mnt/docker_disk/mi_docker/docker-binaries
action=${1:-status}
[ "$#" -eq 0 ] || shift
restart=1
proxy=http://10.31.0.66:7890
for arg in "$@"; do
    case "$arg" in --no-restart) restart=0 ;; http://*) proxy=$arg ;; *) echo '参数错误' >&2; exit 2 ;; esac
done
case "$action" in
    status)
        echo '【下次启动配置】'
        cat "$BASE/proxy.env"
        echo '【当前运行配置】'
        timeout -t 5 "$BIN/docker" info --format 'HTTP={{.HTTPProxy}} HTTPS={{.HTTPSProxy}} NO_PROXY={{.NoProxy}}'
        exit ;;
    on|off) ;;
    *) echo '用法：proxy.sh on|off|status [--no-restart] [http://IPv4:端口]'; exit 2 ;;
esac
[ "$(id -u)" = 0 ] || exit 1
exec 8>/var/run/mi-docker-deploy.lock
flock -n 8 || { echo '已有部署或代理切换操作'; exit 1; }
if [ "$action" = on ]; then
    printf '%s\n' "$proxy" | awk '
      /^http:\/\/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/ {
        sub(/^http:\/\//, ""); split($0,p,":"); split(p[1],a,".");
        for(i=1;i<=4;i++) if(a[i]>255) exit 1;
        if(p[2]<1 || p[2]>65535) exit 1; valid=1
      } END {if(!valid) exit 1}' || { echo '代理必须为 http://IPv4:端口'; exit 2; }
else proxy=; fi
tmp=$(mktemp "$BASE/.proxy.XXXXXX")
running=
trap 'rm -f "$tmp"; [ -z "$running" ] || rm -f "$running"' EXIT
if [ "$restart" = 1 ] && pidof dockerd >/dev/null 2>&1; then
    running=$(mktemp /tmp/mi-docker-running.XXXXXX)
    timeout -t 5 "$BIN/docker" ps -q > "$running" || { echo '无法读取容器状态，未更改代理'; exit 1; }
fi
printf 'HTTP_PROXY=%s\nHTTPS_PROXY=%s\nNO_PROXY=%s\n' "$proxy" "$proxy" 'localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local,.lan' > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$BASE/proxy.env"
if [ "$restart" = 1 ]; then
    echo '正在通过 procd 重启 Docker，容器会短暂中断。'
    /etc/init.d/mi_docker restart
    n=0
    until timeout -t 2 "$BIN/docker" info >/dev/null 2>&1; do
        [ "$n" -lt 25 ] || { echo '尚未就绪，请检查 /tmp/mi-docker-startup.log'; exit 1; }
        sleep 2; n=$((n+1))
    done
    if [ -n "$running" ]; then
        while IFS= read -r id; do
            [ -z "$id" ] || timeout -t 30 "$BIN/docker" start "$id" >/dev/null || echo "警告：容器 $id 未恢复"
        done < "$running"
    fi
    "$BIN/docker" info --format '当前 HTTP={{.HTTPProxy}} HTTPS={{.HTTPSProxy}}'
else echo '仅保存配置，下次 Docker 启动后生效。'; fi
PROXY

# Preserve the current proxy, without sourcing shell text from config files.
if [ -f "$BASE/proxy.env" ]; then
    cp "$BASE/proxy.env" "$STAGE/proxy.env"
else
    for name in HTTP_PROXY HTTPS_PROXY NO_PROXY; do
        value=$(sed -n "s/.* $name=\"\([^\"]*\)\".*/\1/p" "$INIT" | head -n 1)
        printf '%s=%s\n' "$name" "$value" >> "$STAGE/proxy.env"
    done
fi
# Idempotent marker replacement; no changes to firmware install/uninstall logic.
awk '/^# BEGIN MI_DOCKER_MANAGED_FIX$/ {skip=1; next} /^# END MI_DOCKER_MANAGED_FIX$/ {skip=0; next} !skip {print}' "$INIT" > "$STAGE/init"
cat >> "$STAGE/init" <<'HOOK'
# BEGIN MI_DOCKER_MANAGED_FIX
. /data/router-docker-autostart/service.sh
# END MI_DOCKER_MANAGED_FIX
HOOK
for file in launch.sh service.sh proxy.sh init; do sh -n "$STAGE/$file" || die "语法检查失败：$file"; done

# Redirect the previously supplied helper; never replace an unknown user script.
LEGACY=/root/docker-mihomo-proxy.sh
if [ -f "$LEGACY" ] && [ ! -L "$LEGACY" ] &&
   ! grep -q '^# MI_DOCKER_MANAGED_PROXY$' "$LEGACY"; then
    if grep -q '^INIT=/etc/init.d/mi_docker$' "$LEGACY" &&
       grep -q '^STATE_DIR=/data/docker-mihomo-proxy-toggle$' "$LEGACY"; then
        awk 'NR==1 {
          print;
          print "# MI_DOCKER_MANAGED_PROXY";
          print "if [ -x /data/router-docker-autostart/proxy.sh ]; then";
          print "    exec /data/router-docker-autostart/proxy.sh \"$@\"";
          print "fi"; next
        } {print}' "$LEGACY" > "$STAGE/legacy-proxy"
        sh -n "$STAGE/legacy-proxy" || die '旧代理脚本适配语法检查失败。'
    else
        echo "警告：$LEGACY 不是已知版本，未覆盖；请以后使用 $BASE/proxy.sh 切换代理。"
    fi
fi

existing=$(pidof dockerd || true)
if [ -n "$existing" ] && [ "$START_NOW" = 1 ]; then
    [ "$ALLOW_RESTART" = 1 ] || die 'Docker 正在运行；如允许短暂中断，请加 --restart 重试。'
    set -- $existing
    [ "$#" = 1 ] && [ "$(readlink /proc/$1/exe)" = "$BIN/dockerd" ] || die '发现未知 Docker 进程，拒绝停止。'
    timeout -t 5 "$BIN/docker" ps -q > "$STAGE/running.ids" || die '无法记录当前运行容器。'
    if [ -f "$BASE/service.sh" ]; then /etc/init.d/mi_docker stop; else kill -TERM "$existing"; fi
    n=0
    while kill -0 "$existing" 2>/dev/null; do
        [ "$n" -lt 60 ] || die 'Docker 未正常退出；没有强制终止或替换文件。'
        sleep 1; n=$((n+1))
    done
fi
mkdir -p "$BASE"
chmod 700 "$BASE"
[ -f "$BASE/mi_docker.original" ] || cp -p "$INIT" "$BASE/mi_docker.original"
[ -f "$BASE/mi_docker.uci.original" ] || cp -p /etc/config/mi_docker "$BASE/mi_docker.uci.original"
for file in launch.sh service.sh proxy.sh proxy.env; do
    cp "$STAGE/$file" "$BASE/$file.new"
    chmod 700 "$BASE/$file.new"
    mv -f "$BASE/$file.new" "$BASE/$file"
done
chmod 600 "$BASE/proxy.env"
cp "$STAGE/init" /etc/init.d/.mi_docker.managed-new
chmod 755 /etc/init.d/.mi_docker.managed-new
mv -f /etc/init.d/.mi_docker.managed-new "$INIT"
if [ -f "$STAGE/legacy-proxy" ]; then
    [ -f "$BASE/docker-mihomo-proxy.original" ] || cp -p "$LEGACY" "$BASE/docker-mihomo-proxy.original"
    cp "$STAGE/legacy-proxy" /root/.docker-mihomo-proxy.managed-new
    chmod 700 /root/.docker-mihomo-proxy.managed-new
    mv -f /root/.docker-mihomo-proxy.managed-new "$LEGACY"
    echo '已让旧代理开关脚本使用 procd 托管入口。'
fi
uci set mi_docker.settings.docker_install=1
uci set mi_docker.settings.docker_enable=1
uci commit mi_docker
/etc/init.d/mi_docker enable
echo "Docker 自启修复 v$VERSION 已安装。磁盘等待每次最多 300 秒；连续失败最多尝试 3 次，间隔 10 秒。"
echo "数据仍在 /mnt/docker_disk/mi_docker/lib/docker；原配置备份在 $BASE。"
echo '日志：/tmp/mi-docker-startup.log 和 /tmp/mi-docker-daemon.log（重启清空）。'
if [ "$PREPARE" = 1 ]; then
    echo '准备完成：已设 docker_install=1，防止官方热插拔脚本按“未安装”状态删除原 mi_docker 目录。'
    echo '现在可接回保留原 Docker 程序及数据的 USB 盘；磁盘插入事件或下次开机会触发托管启动。'
    echo '不适用于空白 USB 盘；本脚本不下载 Docker、不格式化磁盘、不恢复已丢失的数据。'
fi
[ "$START_NOW" = 1 ] || { echo '本次不启动。'; exit 0; }
/etc/init.d/mi_docker start
n=0
while [ "$n" -lt 25 ]; do
    if timeout -t 2 "$BIN/docker" info >/dev/null 2>&1; then
        if [ -f "$STAGE/running.ids" ]; then
            while IFS= read -r id; do
                [ -z "$id" ] || timeout -t 30 "$BIN/docker" start "$id" >/dev/null || echo "警告：容器 $id 未恢复"
            done < "$STAGE/running.ids"
        fi
        echo 'Docker API 已就绪。'
        "$BIN/docker" ps --format '{{.Names}}  {{.Status}}'
        exit 0
    fi
    sleep 2; n=$((n+1))
done
echo '尚未就绪；procd 将按有限重试策略处理，请查看独立日志。' >&2
exit 1
