#!/bin/sh
# AX9000 RA70 stock 1.0.168 Docker + stock LuCI view, version 1.1.0.
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
[ -f "$HERE/payload/common.sh" ] || { echo '请保留完整安装目录（包含 payload）。' >&2; exit 1; }
. "$HERE/payload/common.sh"
ACTION=${1:-status}
[ "$#" -eq 0 ] || shift
REQUEST_DISK=; ARCHIVE=; START_NOW=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --disk) [ "$#" -ge 2 ] || die '--disk 缺少挂载路径。'; REQUEST_DISK=$2; shift 2 ;;
        --archive) [ "$#" -ge 2 ] || die '--archive 缺少文件路径。'; ARCHIVE=$2; shift 2 ;;
        --start) START_NOW=1; shift ;;
        *) die "未知参数：$1" ;;
    esac
done
case "$ACTION" in
    -h|--help|help) echo "用法：sh $0 status|apply --disk /extdisks/挂载点 [--archive Docker包] [--start]|upgrade|start|stop|restore"; exit 0 ;;
    apply|upgrade|status|start|stop|restore) ;;
    *) die '未知动作。' ;;
esac
[ "$(id -u)" = 0 ] || die '请通过 root SSH 执行。'
check_rom
for tool in awk sha256sum md5sum cmp mktemp flock uci blkid luac readlink curl tar df; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令：$tool"
done
[ -f /lib/functions/procd.sh ] || die '缺少 procd。'
[ ! -L "$BASE" ] || die '状态目录不能为符号链接。'
HEADER=/usr/lib/lua/luci/view/web/inc/header.htm
HEADER_MD5=9678b0beb974771986b1d6df3ef7dbc8
OLD_MANIFEST_SHA=0d3a43154695fcc1fab8b3bbc4b29a3b684f2ce0f486bf4a374d63cb8ef84fa0
targets() {
    cat <<'TARGETS'
mi_docker.init /etc/init.d/mi_docker 755
docker-cli.sh /usr/bin/docker 755
routerdocker168.lua /usr/lib/lua/luci/controller/api/routerdocker168.lua 644
docker.htm /usr/lib/lua/luci/view/web/setting/docker.htm 644
docker.css /www/xiaoqiang/web/css/docker.css 644
install-docker.png /www/xiaoqiang/web/img/install-docker.png 644
header.htm /usr/lib/lua/luci/view/web/inc/header.htm 644
TARGETS
}
check_owned() {
    [ -f "$BASE/installed" ] && [ -f "$BASE/owned.sha256" ] || die '没有完整的本工具安装记录。'
    (cd / && sha256sum -c "$BASE/owned.sha256" >/dev/null) || die '已安装的服务/页面已被修改，拒绝覆盖，请人工核对。'
    (cd "$BASE/runtime" && sha256sum -c SHA256SUMS >/dev/null) || die '持久运行文件已改变，拒绝操作。'
    [ -f "$BASE/backup.sha256" ] || die '缺少备份摘要。'
    (cd "$BASE/backup" && sha256sum -c "$BASE/backup.sha256" >/dev/null) || die '原厂备份已损坏。'
    targets | while read -r source target mode; do [ ! -L "$target" ] || die "目标不能为符号链接：$target"; done
}
validate_payload() {
    (cd "$HERE/payload" && sha256sum -c SHA256SUMS >/dev/null) || die '安装目录摘要校验失败。'
    luac -p "$HERE/payload/routerdocker168.lua"
    for file in "$HERE"/payload/*.sh "$HERE/payload/mi_docker.init"; do sh -n "$file"; done
}
if [ "$ACTION" = status ]; then
    if [ -f "$BASE/installed" ]; then
        check_owned
        sh "$BASE/runtime/control.sh" status
    else
        echo '尚未安装 1.0.168 Docker 恢复工具。'
        echo '请先确认外接 ext4 盘挂载位置，然后使用 apply --disk 路径。'
    fi
    exit 0
fi
if [ "$ACTION" = start ] || [ "$ACTION" = stop ]; then
    check_owned
    if [ "$ACTION" = start ]; then exec sh "$BASE/runtime/control.sh" on; fi
    exec sh "$BASE/runtime/control.sh" off
fi
exec 8>/var/run/router-docker168-operation.lock
flock -n 8 || die '已有部署、页面操作或回退任务。'
umask 077
PENDING=0
TMP=
UPGRADE_BACKUP=
UPGRADE_STAGE=
rollback_files() {
    # Only paths in the fixed target list; Docker disk contents are never removed.
    targets | while read -r source target mode; do
        if [ -f "$BASE/backup/$source" ]; then
            local tmp
            tmp=$(mktemp "${target}.rollback168.XXXXXX")
            cp -p "$BASE/backup/$source" "$tmp"
            mv -f "$tmp" "$target"
        elif [ -f "$BASE/backup/$source.absent" ]; then
            rm -f "$target"
        fi
    done
    if [ -f "$BASE/backup/mi_docker.config" ]; then
        cp -p "$BASE/backup/mi_docker.config" /etc/config/mi_docker
    elif [ -f "$BASE/backup/mi_docker.config.absent" ]; then
        rm -f /etc/config/mi_docker
    fi
    # S99mi_docker is already present as a dangling link in the original ROM.
    [ ! -f "$BASE/backup/K10mi_docker.absent" ] || rm -f /etc/rc.d/K10mi_docker
}
clear_cache() {
    # Only LuCI registration/template caches; no system services are restarted.
    rm -f /tmp/luci-indexcache
    if [ -d /tmp/luci-modulecache ] && [ ! -L /tmp/luci-modulecache ]; then
        find /tmp/luci-modulecache -type f -exec rm -f '{}' \;
    fi
}
rollback_upgrade() {
    targets | while read -r source target mode; do
        local copy
        copy=$(mktemp "${target}.upgrade-rollback.XXXXXX")
        cp -p "$UPGRADE_BACKUP/files/$source" "$copy"
        mv -f "$copy" "$target"
    done
    if [ -d "$UPGRADE_BACKUP/runtime" ]; then
        [ ! -d "$BASE/runtime" ] || mv "$BASE/runtime" "$UPGRADE_BACKUP/runtime.failed"
        mv "$UPGRADE_BACKUP/runtime" "$BASE/runtime"
    fi
    cp -p "$UPGRADE_BACKUP/owned.sha256" "$BASE/owned.sha256"
    cp -p "$UPGRADE_BACKUP/installed" "$BASE/installed"
}
cleanup() {
    rc=$?
    [ -z "$TMP" ] || rm -f "$TMP"
    if [ "$PENDING" = 1 ]; then
        rollback_files || true
        clear_cache
        echo '安装未完成，已尝试回退服务和页面；外接盘程序及数据保留。' >&2
    elif [ "$PENDING" = 2 ]; then
        rollback_upgrade || true
        clear_cache
        echo '升级未完成，已尝试恢复升级前的运行文件；原配置与外接盘数据保留。' >&2
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
if [ "$ACTION" = upgrade ]; then
    check_owned
    validate_payload
    api_timeout >/dev/null
    load_proxy
    if [ "$(cat "$BASE/installed")" = 1.1.0 ]; then
        cmp -s "$BASE/runtime/SHA256SUMS" "$HERE/payload/SHA256SUMS" || die '当前 1.1.0 与此包不一致，拒绝覆盖。'
        echo '已经是 1.1.0，无需升级。'
        exit 0
    fi
    [ "$(cat "$BASE/installed")" = 1.0.0 ] && [ "$(sha "$BASE/runtime/SHA256SUMS")" = "$OLD_MANIFEST_SHA" ] || die '仅支持已核对的 1.0.0 升级到 1.1.0。'
    [ "$(df -Pk / | awk 'END {print $4}')" -ge 2048 ] || die '系统可写层至少需要 2 MiB 可用空间。'
    UPGRADE_BACKUP=$(mktemp -d "$BASE/upgrade-1.0.0.XXXXXX")
    mkdir "$UPGRADE_BACKUP/files"
    targets | while read -r source target mode; do cp -p "$target" "$UPGRADE_BACKUP/files/$source"; done
    cp -p "$BASE/owned.sha256" "$BASE/installed" "$UPGRADE_BACKUP/"
    UPGRADE_STAGE=$(mktemp -d "$BASE/.runtime-upgrade.XXXXXX")
    cp "$HERE"/payload/* "$UPGRADE_STAGE/"
    (cd "$UPGRADE_STAGE" && sha256sum -c SHA256SUMS >/dev/null)
    PENDING=2
    mv "$BASE/runtime" "$UPGRADE_BACKUP/runtime"
    mv "$UPGRADE_STAGE" "$BASE/runtime"
    UPGRADE_STAGE=
    targets | while read -r source target mode; do
        copy=$(mktemp "${target}.upgrade168.XXXXXX")
        cp "$BASE/runtime/$source" "$copy"
        chmod "$mode" "$copy"
        mv -f "$copy" "$target"
    done
    TMP=$(mktemp "$BASE/.owned.XXXXXX")
    targets | while read -r source target mode; do sha256sum "$target"; done > "$TMP"
    mv -f "$TMP" "$BASE/owned.sha256"
    TMP=$(mktemp "$BASE/.installed.XXXXXX")
    echo 1.1.0 > "$TMP"
    mv -f "$TMP" "$BASE/installed"
    TMP=
    PENDING=0
    clear_cache
    echo "已升级到 1.1.0，配置、容器数据及原厂备份保留；升级前文件在 $UPGRADE_BACKUP。"
    echo '未主动重启 Docker；新检查在下次启动生效。需要立即生效时明确执行 stop，再执行 start。'
    exit 0
fi
if [ "$ACTION" = restore ]; then
    check_owned
    /etc/init.d/mi_docker stop
    n=0
    while pidof dockerd >/dev/null 2>&1; do
        [ "$n" -lt 65 ] || die 'Docker 尚未停止，未恢复文件或强杀进程。'
        sleep 1; n=$((n+1))
    done
    [ ! -f /etc/config/mi_docker ] || cp -p /etc/config/mi_docker "$BASE/last-mi_docker.config"
    rollback_files
    mv "$BASE/installed" "$BASE/restored"
    clear_cache
    echo "已恢复安装前的页面、入口与配置；备份在 $BASE，外接盘的容器和卷数据保留。"
    echo '新增 cgroup 挂载保留至下次重启，避免影响其他进程。'
    exit 0
fi
[ -n "$REQUEST_DISK" ] || die '必须用 --disk 明确指定已挂载的 ext4 外接盘。'
disk_at "$REQUEST_DISK" || die '指定路径不是受支持的真实 ext4 可读写 USB 挂载点，或具有 noexec/符号链接。'
ENGINE=$DISK/mi_docker/docker-binaries
DATA=$DISK/mi_docker/lib/docker
check_tree
if [ -f "$BASE/installed" ]; then
    check_owned
    [ "$(cat "$BASE/installed")" = 1.1.0 ] || die '已安装旧版本，请先执行 upgrade 保留配置升级。'
    cmp -s "$BASE/runtime/SHA256SUMS" "$HERE/payload/SHA256SUMS" || die '安装包与当前运行文件版本不一致。'
    [ "$(get disk_uuid)" = "$UUID" ] || die '已安装到其他 UUID，拒绝更换磁盘。'
    check_engine || die '已有 Docker 程序不匹配，未覆盖文件。'
    [ "$(get docker_install)" = 1 ] || set_option docker_install 1
    echo '服务和页面已经安装，原始备份保持不变。'
else
    # A known stable header is the only original firmware file being replaced.
    [ -f "$HEADER" ] && [ ! -L "$HEADER" ] && [ "$(md5sum "$HEADER" | awk '{print $1}')" = "$HEADER_MD5" ] || die '不是已核对的 1.0.168 页头，拒绝覆盖。'
    targets | while read -r source target mode; do
        [ ! -L "$target" ] && [ ! -L "$(dirname "$target")" ] || die "目标路径为符号链接：$target"
        [ "$target" = "$HEADER" ] || [ ! -e "$target" ] || die "已有未知文件，拒绝覆盖：$target"
    done
    [ ! -e /etc/config/mi_docker ] && [ ! -L /etc/config/mi_docker ] || die '已有 Docker 配置，请先人工核对。'
    [ -L /etc/rc.d/S99mi_docker ] && [ "$(readlink /etc/rc.d/S99mi_docker)" = ../init.d/mi_docker ] || die '原厂 S99mi_docker 残留链接不匹配。'
    [ ! -e /etc/rc.d/K10mi_docker ] && [ ! -L /etc/rc.d/K10mi_docker ] || die '已有未知停止链接。'
    pidof dockerd >/dev/null 2>&1 && die '已有 dockerd 运行，拒绝接管。'
    validate_payload
    [ "$(df -Pk / | awk 'END {print $4}')" -ge 2048 ] || die '系统可写层至少需要 2 MiB 可用空间。'
    if [ -d "$BASE/backup" ]; then
        [ -f "$BASE/backup.sha256" ] || die '已有不完整备份，请先核对。'
        (cd "$BASE/backup" && sha256sum -c "$BASE/backup.sha256" >/dev/null) || die '已有备份损坏。'
        cmp -s "$HEADER" "$BASE/backup/header.htm" || die '原始页头备份不匹配。'
    else
        mkdir -p "$BASE/backup"
        chmod 700 "$BASE" "$BASE/backup"
        targets | while read -r source target mode; do
            if [ -e "$target" ]; then cp -p "$target" "$BASE/backup/$source"; else : > "$BASE/backup/$source.absent"; fi
        done
        : > "$BASE/backup/mi_docker.config.absent"
        : > "$BASE/backup/K10mi_docker.absent"
        (cd "$BASE/backup" && sha256sum ./*) > "$BASE/backup.sha256"
    fi
    # An interrupted/failed attempt may have left a runtime directory; check it.
    if [ -d "$BASE/runtime" ]; then
        (cd "$BASE/runtime" && sha256sum -c SHA256SUMS >/dev/null) || die '已有运行目录已改变。'
        if ! cmp -s "$HERE/payload/SHA256SUMS" "$BASE/runtime/SHA256SUMS"; then
            [ "$(sha "$BASE/runtime/SHA256SUMS")" = "$OLD_MANIFEST_SHA" ] || die '已有运行文件版本不符。'
            retired=$(mktemp -d "$BASE/restored-runtime-1.0.0.XXXXXX")
            mv "$BASE/runtime" "$retired/runtime"
        fi
    fi
    if [ ! -d "$BASE/runtime" ]; then
        mkdir "$BASE/runtime"
        cp "$HERE"/payload/* "$BASE/runtime/"
        chmod 700 "$BASE/runtime"
    fi
    # Verify/install the engine before exposing any UI/service entry points.
    if [ -z "$ARCHIVE" ] && [ -f "$HERE/docker-19.03.15-ce.tgz" ]; then ARCHIVE=$HERE/docker-19.03.15-ce.tgz; fi
    install_engine "$ARCHIVE"
    mkdir -p "$DATA"
    PENDING=1
    targets | while read -r source target mode; do
        TMP=$(mktemp "${target}.docker168.XXXXXX")
        cp "$BASE/runtime/$source" "$TMP"
        chmod "$mode" "$TMP"
        mv -f "$TMP" "$target"
    done
    TMP=$(mktemp /etc/config/.mi_docker168.XXXXXX)
    printf "config mi_docker 'settings'\n\toption disk_uuid '%s'\n\toption docker_install '1'\n\toption docker_enable '0'\n\toption portainer_install '0'\n" "$UUID" > "$TMP"
    chmod 600 "$TMP"
    mv "$TMP" /etc/config/mi_docker
    TMP=
    /etc/init.d/mi_docker enable
    targets | while read -r source target mode; do sha256sum "$target"; done > "$BASE/owned.sha256"
    echo 1.1.0 > "$BASE/installed"
    PENDING=0
    clear_cache
    echo '已恢复高级设置 → DOCKER，默认尚未启动 Docker。'
fi
if [ "$START_NOW" = 1 ]; then
    flock -u 8
    sh "$BASE/runtime/control.sh" on
else
    echo "准备好后使用页面开关，或 sh $0 start。"
fi
echo '实机验收：docker info、测试容器、网络/卷和重启恢复；尚未完成 1.0.168 真机验收。'
