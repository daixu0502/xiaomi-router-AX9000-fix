#!/bin/sh
# Unified entry: WSL Web/Telnet, SSH deployment, and local router maintenance.
set -eu
DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
usage() {
    cat <<'USAGE'
AX9000 SSH 工具 v2.0.0
电脑 WSL/Linux：
  sh ssh.sh open [地址] [--check] [--set-password]
  sh ssh.sh recover [地址] [--set-password]
  sh ssh.sh persist 地址 status|install|harden|remove [--ssh-port 22] [--backup-dir 本机目录]
  sh ssh.sh modern 地址 prepare|candidate-ok|activate|confirm|status|restore [--ssh-port 22]
路由器 root SSH 内：
  sh ssh.sh persist status|install|backup|harden|remove [参数]
  sh ssh.sh modern prepare|candidate-ok|activate|confirm|status|restore
harden：电脑先保存并验证完整 Bdata 备份，再写 ssh_en/telnet_en，最后核对 Flash 数据。
modern：保留候选登录和 120 秒确认回退；不是一键跳过验证。
USAGE
}
ACTION=${1:-help}
[ "$#" = 0 ] || shift
case "$ACTION" in
    -h|--help|help) usage;;
    --version) echo 2.0.0;;
    open|recover)
        command -v python3 >/dev/null || { echo '请先安装 python3 openssh-client。' >&2; exit 1; }
        if [ "$ACTION" = open ]; then exec python3 "$DIR/lib/open_ssh.py" "$@";
        else exec python3 "$DIR/lib/reopen_ssh.py" "$@"; fi;;
    persist|modern)
        [ "$#" -gt 0 ] || { usage; exit 2; }
        case "${1:-status}" in
            -h|--help) exec sh "$DIR/$ACTION.sh" --help;;
            status|install|backup|harden|remove|boot|check|prepare|candidate-ok|activate|confirm|restore)
                exec sh "$DIR/$ACTION.sh" "$@";;
            *) exec sh "$DIR/lib/remote.sh" "$ACTION" "$@";;
        esac;;
    *) usage >&2; exit 2;;
esac
