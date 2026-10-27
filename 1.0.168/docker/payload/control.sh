#!/bin/sh
set -eu
. /data/router-docker-1.0.168/runtime/common.sh
check_rom
[ "$(id -u)" = 0 ] || die '需要 root。'
ACTION=${1:-status}
case "$ACTION" in status|install|uninstall|on|off|portainer) ;; *) die '未知动作。' ;; esac
if [ "$ACTION" = status ]; then
    printf 'install=%s enable=%s uuid=%s\n' "$(get docker_install)" "$(get docker_enable)" "$(get disk_uuid)"
    find_disk || die '指定磁盘未挂载。'
    printf 'disk=%s data=%s\n' "$DISK" "$DATA"
    check_engine || die '程序缺失或摘要不符。'
    if [ "$(get docker_enable)" != 1 ]; then echo 'Docker 当前已关闭；程序和数据保留。'; exit 0; fi
    timeout -t 5 "$ENGINE/docker" --host unix:///var/run/docker.sock info
    exit
fi
exec 8>/var/run/router-docker168-operation.lock
flock -n 8 || die '已有安装、停用或回退操作。'
umask 077
echo "$ACTION" > /tmp/router-docker168.busy
finish() { rc=$?; rm -f /tmp/router-docker168.busy; echo "$rc" > /tmp/router-docker168.result; }
trap finish EXIT
trap 'exit 143' TERM HUP
trap 'exit 130' INT
stop_managed() {
    /etc/init.d/mi_docker stop
    local n=0
    while pidof dockerd >/dev/null 2>&1; do
        [ "$n" -lt 65 ] || die 'dockerd 尚未退出，保留服务和数据，未强杀。'
        sleep 1; n=$((n+1))
    done
}
case "$ACTION" in
    off|uninstall)
        set_option docker_enable 0
        stop_managed
        [ "$ACTION" != uninstall ] || set_option docker_install 0
        echo '已停用；程序、镜像、容器和卷数据全部保留。'
        exit 0 ;;
esac
find_disk || die '指定 UUID 的 ext4 外接盘未就绪。'
check_tree
case "$ACTION" in
    install)
        install_engine
        mkdir -p "$DATA"
        set_option docker_install 1
        echo 'Docker 已准备好，请使用页面开关启动。' ;;
    on)
        [ "$(get docker_install)" = 1 ] || die '请先安装 Docker。'
        check_engine || die 'Docker 程序不匹配。'
        ready_limit=$(api_timeout)
        set_option docker_enable 1
        /etc/init.d/mi_docker start
        wait_api "$((ready_limit+15))" || die 'Docker API 尚未就绪，请检查 logread -e router-docker168；开关状态保留供 procd 重试。' ;;
    portainer)
        check_engine || die 'Docker 程序不匹配。'
        image=$(get portainer_image)
        # Optional management image must be explicitly pinned; never pull latest.
        printf '%s\n' "$image" | grep -Eq '^portainer/portainer-ce@sha256:[a-f0-9]{64}$' || die '请先按 README 配置已核对的 Portainer ARM64 镜像摘要。'
        timeout -t 5 "$ENGINE/docker" --host unix:///var/run/docker.sock info >/dev/null || die 'Docker API 未就绪。'
        docker_cli inspect router-portainer168 >/dev/null 2>&1 && die '管理容器已经存在，请通过 SSH 核对，未重建或删除。'
        lan=$(uci -q get network.lan.ipaddr)
        printf '%s\n' "$lan" | awk -F. 'NF!=4 {exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i>255) exit 1}' || die 'LAN IPv4 无效。'
        timeout -t 240 "$ENGINE/docker" --host unix:///var/run/docker.sock pull "$image"
        docker_cli volume create router_portainer168_data
        docker_cli run -d --name router-portainer168 --restart unless-stopped \
            -p "$lan:9001:9000" -v /var/run/docker.sock:/var/run/docker.sock \
            -v router_portainer168_data:/data "$image"
        set_option portainer_install 1 ;;
esac
