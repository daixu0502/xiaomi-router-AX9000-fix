#!/bin/sh
# AX9000 software persistence and explicit, backed-up Bdata flag changes.
set -eu
DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
BASE=/data/router-ssh/persist
BOOT=$BASE/boot.sh
SECTION=router_ssh_persist
LOCK=/tmp/router-ssh-persist.lock
SYS_MODULE=/sys/module/xmir_patcher
PARAM=$SYS_MODULE/parameters/cmd
MODULE_SHA=ac6f89aa6839b46b746320eaff54c0b11581f467e9cfdac9e4cb4fd195788de1
MODULE=$DIR/modules/xmir_patcher-4.4.60-arm64-preempt.ko
locked=0
tmp=
cleanup() { [ -z "$tmp" ] || rm -f "$tmp"; [ "$locked" = 0 ] || rmdir "$LOCK" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
hash() { sha256sum "$1" | awk '{print $1}'; }
usage() {
    echo 'persist status | install | remove | backup | harden --backup 目录 --backup-sha SHA256'
    echo 'install：开机软件修复；harden：写 Bdata 的 ssh_en/telnet_en，优先从电脑统一入口执行以保存离机备份。'
}
ACTION=${1:-status}
[ "$#" = 0 ] || shift
case "$ACTION" in -h|--help) usage; exit 0;; status|install|remove|backup|harden) ;; *) usage; exit 2;; esac
backup=
expected=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --backup) [ "$#" -ge 2 ] || fail 'Missing backup directory.'; backup=$2; shift 2;;
        --backup-sha) [ "$#" -ge 2 ] || fail 'Missing backup hash.'; expected=$2; shift 2;;
        *) fail 'Unknown argument.';;
    esac
done
[ "$(id -u)" = 0 ] || fail 'Root is required.'
version=/usr/share/xiaoqiang/xiaoqiang_version
[ "$(uci -q get "$version.version.HARDWARE")" = RA70 ] || fail 'Expected AX9000 / RA70.'
rom=$(uci -q get "$version.version.ROM")
case "$rom" in 1.0.140|1.0.168) ;; *) fail 'Unsupported firmware.';; esac
for tool in sha256sum awk mktemp dd wc bdata nvram uci cmp; do command -v "$tool" >/dev/null || fail "Missing $tool"; done
for path in /data/router-ssh "$BASE" "$BASE/backups"; do [ ! -L "$path" ] || fail 'Symlinked persistent directory.'; done
flags() {
    for key in ssh_en telnet_en uart_en; do
        value=$(bdata get "$key" || true)
        case "$value" in ''|0|1) ;; *) fail "Unexpected Bdata flag: $key";; esac
        printf '%s=%s\n' "$key" "$value"
    done
}
partition() {
    count=$(awk '$4=="\"bdata\"" || $4=="\"Bdata\"" {n++} END{print n+0}' /proc/mtd)
    [ "$count" = 1 ] || fail 'Expected exactly one Bdata partition.'
    record=$(awk '$4=="\"bdata\"" || $4=="\"Bdata\"" {print $1, $2, $4}' /proc/mtd)
    set -- $record
    number=${1#mtd}; number=${number%:}
    case "$number" in ''|*[!0-9]*) fail 'Invalid MTD index.';; esac
    hex=$2
    case "$hex" in ''|*[!a-fA-F0-9]*) fail 'Invalid MTD size.';; esac
    size=$((0x$hex))
    [ "$size" -gt 1024 ] && [ "$size" -le 16777216 ] || fail 'Unexpected Bdata size.'
    name=$(printf '%s' "$3" | tr -d '"')
    device=/dev/mtd$number
    [ -c "$device" ] || fail 'Bdata character device missing.'
}
dump() {
    [ ! -L "$1" ] || fail 'Refusing a symlinked dump target.'
    [ ! -e "$1" ] || [ -f "$1" ] || fail 'Dump target is not a regular file.'
    dd if="$device" of="$1" bs=65536 2>/dev/null || fail 'Bdata read failed.'
    [ "$(wc -c < "$1")" = "$size" ] || fail 'Incomplete Bdata backup.'
    chmod 0600 "$1"
}
owned_hook() {
    [ "$(uci -q get firewall.$SECTION || true)" = include ] &&
    [ "$(uci -q get firewall.$SECTION.path || true)" = "$BOOT" ] &&
    [ "$(uci -q get firewall.$SECTION.type || true)" = script ]
}
install_soft() {
    [ -f "$DIR/lib/persist-boot.sh" ] || fail 'Use the complete toolkit.'
    sh "$DIR/lib/persist-boot.sh" check
    if uci -q get firewall.$SECTION >/dev/null; then owned_hook || fail 'Firewall section is owned by another configuration.'; fi
    [ ! -L "$BOOT" ] || fail 'Symlinked boot script.'
    if [ -e "$BOOT" ]; then cmp -s "$BOOT" "$DIR/lib/persist-boot.sh" || fail 'Existing boot script was modified; preserve and inspect it first.'; fi
    [ -z "$(uci -q changes firewall)" ] || fail 'Uncommitted firewall changes; save them first.'
    mkdir -p "$BASE/backups"
    chmod 0700 /data/router-ssh "$BASE" "$BASE/backups"
    saved=$(mktemp -d "$BASE/backups/software.XXXXXX")
    cp -p /etc/init.d/dropbear "$saved/dropbear.init"
    cp -p /etc/config/firewall "$saved/firewall.config"
    nvram get ssh_en > "$saved/ssh_en"
    # Preserve the previous owned section without touching unrelated firewall rules.
    before=$(uci -q show firewall.$SECTION || true)
    tmp=$(mktemp "$BASE/.boot.XXXXXX")
    cp "$DIR/lib/persist-boot.sh" "$tmp"; chmod 0700 "$tmp"; sh -n "$tmp"
    [ ! -f "$BOOT" ] || cp -p "$BOOT" "$saved/boot.previous"
    mv -f "$tmp" "$BOOT"; tmp=
    if ! {
        uci set firewall.$SECTION=include && uci set firewall.$SECTION.type=script &&
        uci set "firewall.$SECTION.path=$BOOT" && uci set firewall.$SECTION.enabled=1 &&
        uci set firewall.$SECTION.reload=1 && uci commit firewall && sh "$BOOT";
    }; then
        uci -q revert firewall.$SECTION || true
        uci -q delete firewall.$SECTION || true
        if [ -n "$before" ]; then
            # Values were checked as our own fixed section; UCI import is not shell eval.
            printf '%s\n' "$before" | sed 's/^/set /' | uci -q batch || fail "Hook rollback failed; inspect $saved"
        fi
        uci commit firewall || fail "Hook rollback failed; inspect $saved"
        if [ -f "$saved/boot.previous" ]; then cp -p "$saved/boot.previous" "$BOOT"; else rm -f "$BOOT"; fi
        fail "Software persistence failed; inspect backup $saved and current SSH state."
    fi
    say "SOFTWARE_BACKUP=$saved"
    say 'SOFTWARE_PERSIST_OK=1'
}
if [ "$ACTION" = status ]; then
    if owned_hook && [ -f "$BOOT" ] && [ "$(uci -q get firewall.$SECTION.enabled || true)" = 1 ]; then
        say '软件固化：开机修复钩子已启用。'
    else say '软件固化：未完整安装。'; fi
    flags
    say "NVRAM_ssh_en=$(nvram get ssh_en)"
    [ ! -d "$SYS_MODULE" ] || say '内核模块仍已加载；分区可写标志可能保留至重启，不自动重启。'
    exit 0
fi
mkdir "$LOCK" 2>/dev/null || fail 'Another persistence operation or stale lock exists.'
locked=1
umask 077
case "$ACTION" in
    install) install_soft; exit 0;;
    remove)
        [ -z "$(uci -q changes firewall)" ] || fail 'Uncommitted firewall changes.'
        if uci -q get firewall.$SECTION >/dev/null; then
            owned_hook || fail 'Refusing to remove another configuration.'
            uci delete firewall.$SECTION; uci commit firewall
        fi
        say '已移除开机修复钩子；SSH、密码、Bdata 开关及备份保留。'; exit 0;;
esac
partition
if [ "$ACTION" = backup ]; then
    mkdir -p "$BASE/backups"; chmod 0700 /data/router-ssh "$BASE" "$BASE/backups"
    backup=$(mktemp -d "$BASE/backups/bdata.XXXXXX")
    dump "$backup/bdata.bin"
    flags > "$backup/flags.before"
    printf 'MODEL=RA70\nROM=%s\nMTD=%s\nSIZE=%s\nNAME=%s\n' "$rom" "$number" "$size" "$name" > "$backup/metadata"
    (cd "$backup"; sha256sum bdata.bin > SHA256SUMS)
    say "BACKUP_DIR=$backup"
    say "BACKUP_SHA256=$(hash "$backup/bdata.bin")"
    exit 0
fi
# Hardware persistence requires the receipt of a complete backup, normally saved on WSL.
sh "$DIR/lib/persist-boot.sh" check
if uci -q get firewall.$SECTION >/dev/null; then owned_hook || fail 'Foreign firewall section; no Bdata changes made.'; fi
[ -z "$(uci -q changes firewall)" ] || fail 'Uncommitted firewall changes; no Bdata changes made.'
case "$backup" in "$BASE"/backups/bdata.*) ;; *) fail 'Use a backup made by this toolkit.';; esac
suffix=${backup#"$BASE/backups/bdata."}
[ "${#suffix}" = 6 ] || fail 'Invalid backup directory suffix.'
case "$suffix" in *[!a-zA-Z0-9]*) fail 'Invalid backup directory suffix.';; esac
case "$backup" in *[!a-zA-Z0-9_./-]*|*/../*|*/./*) fail 'Invalid backup path.';; esac
[ ! -L "$backup" ] && [ -d "$backup" ] || fail 'Missing or symlinked backup.'
for file in bdata.bin SHA256SUMS flags.before metadata; do
    [ -f "$backup/$file" ] && [ ! -L "$backup/$file" ] || fail 'Incomplete backup.'
done
[ "${#expected}" = 64 ] || fail 'Missing verified backup SHA-256.'
case "$expected" in *[!a-f0-9]*) fail 'Invalid SHA-256.';; esac
[ "$(hash "$backup/bdata.bin")" = "$expected" ] || fail 'Backup checksum mismatch.'
grep -qx "MTD=$number" "$backup/metadata" && grep -qx "SIZE=$size" "$backup/metadata" &&
    grep -qx "ROM=$rom" "$backup/metadata" || fail 'Backup belongs to a different partition or firmware.'
tmp=$(mktemp /tmp/ssh-bdata-check.XXXXXX)
dump "$tmp"
[ "$(hash "$tmp")" = "$expected" ] || fail 'Bdata changed since backup; make a new backup.'
rm -f "$tmp"; tmp=
flags_now=$(flags)
[ "$flags_now" = "$(cat "$backup/flags.before")" ] || fail 'Bdata CLI flags changed since backup.'
if [ "$(bdata get ssh_en || true)" != 1 ] || [ "$(bdata get telnet_en || true)" != 1 ]; then
    [ "$(uname -m)" = aarch64 ] && [ "$(uname -r)" = 4.4.60 ] || fail 'Only verified 4.4.60 aarch64 kernel profile is accepted.'
    case "$(uname -v)" in *SMP*PREEMPT*) ;; *) fail 'Kernel is not SMP PREEMPT.';; esac
    [ -f "$MODULE" ] && [ ! -L "$MODULE" ] && [ "$(hash "$MODULE")" = "$MODULE_SHA" ] || fail 'Module checksum mismatch.'
    [ ! -d "$SYS_MODULE" ] || fail 'An existing xmir_patcher is loaded; reboot and inspect before retrying.'
    command -v insmod >/dev/null || fail 'insmod missing.'
    insmod "$MODULE" || fail 'Module load failed; no Bdata flags written. Never force-load.'
    [ -e "$PARAM" ] || fail 'Module command interface missing; no Bdata flags written.'
    printf 'get_mtd_info|%s\n' "$name" > "$PARAM"
    response=$(cat "$PARAM")
    case "$response" in "0|$number|$name|"*) ;; *) fail 'Module resolved a different MTD; no flags written.';; esac
    printf 'set_mtd_rw|%s\n' "$name" > "$PARAM"
    response=$(cat "$PARAM")
    case "$response" in "0|$number|"*) ;; *) fail 'MTD unlock failed; no flags written.';; esac
    bdata set ssh_en=1 || fail 'ssh_en staging failed; inspect Bdata state before retrying.'
    bdata set telnet_en=1 || fail 'telnet_en staging failed; inspect Bdata state before retrying.'
    bdata commit || fail 'Bdata commit failed; backup retained. Do not raw-flash automatically.'
fi
[ "$(bdata get ssh_en)" = 1 ] && [ "$(bdata get telnet_en)" = 1 ] || fail 'Bdata readback failed.'
dump "$backup/bdata.after.bin"
for key in ssh_en telnet_en; do
    dd if="$backup/bdata.after.bin" bs=1 skip=4 2>/dev/null | tr '\000' '\n' | grep -qx "$key=1" || fail 'Raw Flash flags do not match CLI readback.'
done
flags > "$backup/flags.after"
(cd "$backup"; sha256sum bdata.after.bin > SHA256SUMS.after)
say 'BDATA_FLAGS_READBACK_OK=1'
say '模块可能保持加载，MTD 可写状态保留至重启；本工具不自动重启。'
install_soft
say 'HARDEN_ROUTER_OK=1'
say '电脑端仍需核对备份与写后 Flash 的 CRC 和其他字段；未承诺跨 OTA 自动 SSH。'
