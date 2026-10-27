#!/bin/sh
set -eu
# Keep the stable firmware's existing cpu, memory and net_cls hierarchies intact.
ROOT=/sys/fs/cgroup
[ ! -L "$ROOT" ] || { echo 'cgroup 根目录不能为符号链接。' >&2; exit 1; }
mkdir -p "$ROOT"
if awk -v p="$ROOT" '$2==p {yes=1} END {exit !yes}' /proc/mounts; then
    awk -v p="$ROOT" '$2==p && $3=="tmpfs" {yes=1} END {exit !yes}' /proc/mounts || { echo 'cgroup 根目录已由其他文件系统占用。' >&2; exit 1; }
else
    mount -t tmpfs -o mode=0755,size=1m cgroup "$ROOT"
fi
for controller in cpu cpuacct cpuset memory blkio devices freezer pids; do
    awk -v c="$controller" '$1==c && $4==1 {yes=1} END {exit !yes}' /proc/cgroups || { echo "cgroup 不可用：$controller" >&2; exit 1; }
    existing=$(awk -v c="$controller" '$3=="cgroup" {n=split($4,a,","); for(i=1;i<=n;i++) if(a[i]==c) {print $2; exit}}' /proc/mounts)
    [ ! -L "$ROOT/$controller" ] || { echo "cgroup 路径不能为符号链接：$controller" >&2; exit 1; }
    mkdir -p "$ROOT/$controller"
    if awk -v p="$ROOT/$controller" -v c="$controller" '$2==p && $3=="cgroup" {n=split($4,a,","); for(i=1;i<=n;i++) if(a[i]==c) yes=1} END {exit !yes}' /proc/mounts; then continue; fi
    if awk -v p="$ROOT/$controller" '$2==p {yes=1} END {exit !yes}' /proc/mounts; then echo "cgroup 路径已被占用：$controller" >&2; exit 1; fi
    if [ -n "$existing" ]; then
        [ "$existing" = "$ROOT/$controller" ] || mount -o bind "$existing" "$ROOT/$controller"
    else
        mount -t cgroup -o "$controller" cgroup "$ROOT/$controller"
    fi
done
# runc rc10 finds the first cgroup mount's parent, then searches only below it.
# Stock 1.0.168 mounts memory/cpu/net_cls under /dev/cgroup before this script.
# Expose the same hierarchies there too; never replace the stock root or limits.
first_mount=$(awk '$3=="cgroup" {print $2; exit}' /proc/mounts)
first_root=${first_mount%/*}
case "$first_root" in
    "$ROOT") ;;
    /dev/cgroup)
        [ -d "$first_root" ] && [ ! -L "$first_root" ] || exit 1
        for controller in cpu cpuacct cpuset memory blkio devices freezer pids; do
            target=$first_root/$controller
            [ ! -L "$target" ] || { echo "cgroup 路径不能为符号链接：$target" >&2; exit 1; }
            if awk -v p="$target" -v c="$controller" '$2==p && $3=="cgroup" {n=split($4,a,","); for(i=1;i<=n;i++) if(a[i]==c) yes=1} END {exit !yes}' /proc/mounts; then continue; fi
            if awk -v p="$target" '$2==p {yes=1} END {exit !yes}' /proc/mounts; then echo "cgroup 路径已被占用：$target" >&2; exit 1; fi
            mkdir -p "$target"
            mount -o bind "$ROOT/$controller" "$target"
        done ;;
    *) echo "未知的原厂 cgroup 根目录：$first_root" >&2; exit 1 ;;
esac
# Existing firmware group limits are untouched; Docker chooses its own subgroups.
