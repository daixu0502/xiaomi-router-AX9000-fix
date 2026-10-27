#!/bin/sh
# Shared by the installer and the supervised runtime. Never source UCI as shell.
BASE=/data/router-docker-1.0.168
CONFIG=mi_docker
ARCHIVE_SHA256=030359d3cc1aac326409c6c37cc2ef5c1b9e5f1ddf97d722f5b8ab2cfa711d13
ARCHIVE_URL=https://cdn.cnbj1.fds.api.mi-img.com/opensource/AX9000-stable-firmware/docker/docker-19.03.15-ce.tgz
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
get() { uci -q get "$CONFIG.settings.$1" 2>/dev/null || true; }
set_option() { uci set "$CONFIG.settings.$1=$2"; uci commit "$CONFIG"; }
sha() { sha256sum "$1" | awk '{print $1}'; }
check_rom() {
    local file=/usr/share/xiaoqiang/xiaoqiang_version
    [ "$(awk '$1=="option" && $2=="ROM" {gsub(/[\047\042]/,"",$3); print $3}' "$file")" = 1.0.168 ] &&
    [ "$(awk '$1=="option" && $2=="HARDWARE" {gsub(/[\047\042]/,"",$3); print $3}' "$file")" = RA70 ] || die '仅支持 RA70 原厂 1.0.168。'
}
safe_path() {
    # Restrict to stock external-storage mount locations, with no escapes/spaces.
    case "$1" in /extdisks/*|/mnt/docker_disk) ;; *) return 1 ;; esac
    case "$1" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*|*//*|*/..|*/.) return 1 ;; esac
    [ "$(readlink -f "$1")" = "$1" ]
}
disk_at() {
    local mountpoint=$1 device uuid
    safe_path "$mountpoint" || return 1
    device=$(awk -v p="$mountpoint" '$2==p && $3=="ext4" && $4 ~ /(^|,)rw(,|$)/ && $4 !~ /(^|,)noexec(,|$)/ {print $1; exit}' /proc/mounts)
    case "$device" in /dev/sd*) ;; *) return 1 ;; esac
    [ -b "$device" ] || return 1
    uuid=$(blkid -s UUID -o value "$device" 2>/dev/null) || return 1
    case "$uuid" in ''|*[!a-fA-F0-9-]*) return 1 ;; esac
    DISK=$mountpoint; DEVICE=$device; UUID=$uuid
}
find_disk() {
    local wanted candidate
    wanted=$(get disk_uuid)
    [ -n "$wanted" ] || return 1
    # A changed /dev/sdX or stock mount name must not select a different disk.
    for candidate in $(awk '$3=="ext4" {print $2}' /proc/mounts); do
        if disk_at "$candidate" && [ "$UUID" = "$wanted" ]; then
            ENGINE=$DISK/mi_docker/docker-binaries
            DATA=$DISK/mi_docker/lib/docker
            return 0
        fi
    done
    return 1
}
check_tree() {
    local item path
    for item in mi_docker mi_docker/lib mi_docker/lib/docker mi_docker/docker-binaries; do
        path=$DISK/$item
        [ ! -L "$path" ] || die "磁盘路径为符号链接：$path"
        [ ! -e "$path" ] || [ -d "$path" ] || die "磁盘路径不是目录：$path"
    done
}
check_engine() {
    local name expected
    while read -r expected name; do
        [ -f "$ENGINE/$name" ] && [ ! -L "$ENGINE/$name" ] && [ -x "$ENGINE/$name" ] || return 1
        [ "$(md5sum "$ENGINE/$name" | awk '{print $1}')" = "$expected" ] || return 1
    done <<'ENGINE_HASHES'
235fa0fb58ba77823a94fed6c1326956 containerd
8af168bd148c238415bb5ace6f71d47e containerd-shim
e78943af421a291839c080370bf41ad6 ctr
a8523af0f057113d60743a459cedf8b6 docker
6a32bd7aa96f8bf145444d98871e2ce0 docker-init
454a3aca9c22c178679dd349ab7084ea docker-proxy
00ce99e358584f046c6d9aada7f65146 dockerd
c08c14d59908856a54416d369052e1ba runc
ENGINE_HASHES
}
install_engine() {
    local archive=${1:-} stage extracted
    check_tree
    if [ -e "$ENGINE" ]; then
        check_engine || die '已有 Docker 程序与已核对的小米原厂版本不同，保留原文件并拒绝覆盖。'
        return 0
    fi
    [ "$(df -Pk "$DISK" | awk 'END {print $4}')" -ge 262144 ] || die '安装至少需要 256 MiB 可用空间。'
    mkdir -p "$DISK/mi_docker"
    # Download/extract on the external disk, never consume internal overlay space.
    stage=$(mktemp -d "$DISK/mi_docker/.install168.XXXXXX")
    if [ -z "$archive" ]; then
        archive=$stage/docker.tgz
        curl --fail --location --connect-timeout 15 --max-time 240 --retry 2 --output "$archive" "$ARCHIVE_URL" || die "下载失败；暂存保留在 $stage"
    fi
    [ -f "$archive" ] && [ "$(sha "$archive")" = "$ARCHIVE_SHA256" ] || die "Docker 压缩包 SHA-256 不符；暂存保留在 $stage"
    tar -xzf "$archive" -C "$stage"
    extracted=$stage/docker
    ENGINE=$extracted
    check_engine || die '解包后的八个 Docker 程序摘要不匹配。'
    ENGINE=$DISK/mi_docker/docker-binaries
    [ ! -e "$ENGINE" ] && [ ! -L "$ENGINE" ] || die '操作期间出现 Docker 程序目录。'
    mv "$extracted" "$ENGINE"
    [ "$archive" != "$stage/docker.tgz" ] || rm -f "$archive"
    rmdir "$stage"
}
docker_cli() {
    # Always use the local Unix socket, ignoring inherited client contexts/hosts.
    "$ENGINE/docker" --host unix:///var/run/docker.sock "$@"
}
