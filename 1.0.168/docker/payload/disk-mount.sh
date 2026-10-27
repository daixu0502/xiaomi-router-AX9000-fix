#!/bin/sh
set -eu
. /data/router-docker-1.0.168/runtime/common.sh
check_rom
find_disk || die '指定 UUID 的 ext4 外接盘未就绪。'
legacy=/mnt/docker_disk
[ ! -L /mnt ] && [ ! -L "$legacy" ] || die '兼容挂载路径不能为符号链接。'
source_record=$(awk -v p="$DISK" '$5==p {print $3 " " $4; exit}' /proc/self/mountinfo)
[ -n "$source_record" ] && [ "$(printf '%s\n' "$source_record" | awk '{print $2}')" = / ] || die '来源必须是完整分区的根挂载。'
verify_mount() {
    local target_record
    target_record=$(awk -v p="$legacy" '$5==p {print $3 " " $4; exit}' /proc/self/mountinfo)
    [ "$target_record" = "$source_record" ] &&
    awk -v p="$legacy" '$2==p && $3=="ext4" && $4 ~ /(^|,)rw(,|$)/ && $4 !~ /(^|,)noexec(,|$)/ {ok=1} END {exit !ok}' /proc/mounts
}
if awk -v p="$legacy" '$2==p {ok=1} END {exit !ok}' /proc/mounts; then
    verify_mount || die '/mnt/docker_disk 已由其他磁盘、子目录或挂载参数占用，未覆盖。'
    exit 0
fi
if [ -e "$legacy" ]; then
    [ -d "$legacy" ] || die '/mnt/docker_disk 已存在且不是目录。'
    content=$(ls -A "$legacy") || die '无法检查兼容挂载目录。'
    [ -z "$content" ] || die '/mnt/docker_disk 已有文件，拒绝隐藏原有内容。'
else
    mkdir -m 0755 "$legacy"
fi
mount -o bind "$DISK" "$legacy" || die '建立 /mnt/docker_disk 兼容挂载失败。'
verify_mount || die '兼容挂载校验失败，请人工核对。'
printf '已按 UUID %s 将 %s 绑定挂载到 %s。\n' "$UUID" "$DISK" "$legacy"
