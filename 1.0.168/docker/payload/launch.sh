#!/bin/sh
set -eu
. /data/router-docker-1.0.168/runtime/common.sh
check_rom
exec 9>/var/run/router-docker168-daemon.lock
flock -n 9 || die '已有托管 Docker 启动进程。'
elapsed=0
until find_disk; do
    [ "$elapsed" -lt 300 ] || die '指定 UUID 的 ext4 磁盘 300 秒内未就绪。'
    sleep 5; elapsed=$((elapsed+5))
done
[ "$(get docker_enable)" = 1 ] && [ "$(get docker_install)" = 1 ] || exit 0
check_tree
check_engine || die 'Docker 程序摘要不匹配。'
pidof dockerd >/dev/null 2>&1 && die '发现现有 dockerd，拒绝运行第二个实例。'
sh "$BASE/runtime/cgroups.sh"
for module in veth xt_addrtype ipt_MASQUERADE; do
    [ -d "/sys/module/$module" ] || modprobe "$module"
done
mkdir -p "$DATA" /var/run/router-docker168
export PATH=$ENGINE:/usr/sbin:/usr/bin:/sbin:/bin
unset DOCKER_HOST DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY http_proxy https_proxy all_proxy no_proxy
# Fixed local socket. No TCP Docker API and no changes to /etc/profile.
# Empty owned config avoids inheriting an unrelated daemon.json on upgraded disks.
exec "$ENGINE/dockerd" --config-file "$BASE/runtime/daemon.json" \
    --host unix:///var/run/docker.sock --data-root "$DATA" \
    --exec-root /var/run/router-docker168 --pidfile /var/run/router-docker168/dockerd.pid \
    --storage-driver overlay2 --exec-opt native.cgroupdriver=cgroupfs
