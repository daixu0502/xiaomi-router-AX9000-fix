#!/bin/sh
# Sent through the authenticated Web interface. No Bdata or flash operations.
set -eu
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'Command execution is not root.'
version=/usr/share/xiaoqiang/xiaoqiang_version
model=$(uci -q get "$version.version.HARDWARE" || true)
rom=$(uci -q get "$version.version.ROM" || true)
[ "$model" = RA70 ] || fail 'Expected AX9000 / RA70.'
case "$rom" in 1.0.140|1.0.168) ;; *) fail 'Unsupported firmware.';; esac
init=/etc/init.d/dropbear
[ -f "$init" ] && [ ! -L "$init" ] || fail 'Missing or symlinked Dropbear init.'
case "$(md5sum "$init" | cut -d ' ' -f 1)" in
    c91b64a8932e0d35ea95597c24485338|2d6bbcc437d74b63ba022055c4e0f109) ;;
    *) fail 'Unknown/managed Dropbear init; inspect existing SSH tools first.';;
esac
[ "$(md5sum /usr/sbin/dropbear | cut -d ' ' -f 1)" = 1586d632c1b4e960ea0a406ed0758c02 ] || fail 'Not the verified stock Dropbear binary.'
printf 'MODEL=%s\nROM=%s\n' "$model" "$rom"
ports=$(uci -q show dropbear | sed -n "s/.*\.Port='\([0-9][0-9]*\)'$/\1/p")
if [ -n "$ports" ]; then
    for port in $ports; do printf 'PORT=%s\n' "$port"; done
else
    printf 'PORT=22\n'
fi
[ "$OPEN_ACTION" = apply ] || { printf 'INSPECT_OK=1\n'; exit 0; }
lock=/tmp/router-ssh-open.lock
mkdir "$lock" 2>/dev/null || fail 'Another opener is active, or a stale lock exists.'
tmp=
cleanup() {
    [ -z "$tmp" ] || rm -f "$tmp"
    rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
umask 077
backup=$(mktemp -d /etc/ssh-open-backup.XXXXXX)
cp -p "$init" "$backup/dropbear.init"
cp -p /etc/config/dropbear "$backup/dropbear.config"
nvram get ssh_en > "$backup/ssh_en"
printf 'BACKUP=%s\n' "$backup"
was_enabled=0
"$init" enabled && was_enabled=1
rollback() {
    tmp=$(mktemp /etc/init.d/.dropbear.ssh-open.XXXXXX) || return 1
    cp -p "$backup/dropbear.init" "$tmp" && mv -f "$tmp" "$init" || return 1
    tmp=
    old=$(cat "$backup/ssh_en")
    if [ -n "$old" ]; then nvram set "ssh_en=$old" || return 1; else nvram unset ssh_en || return 1; fi
    nvram commit || return 1
    if [ "$was_enabled" != 1 ]; then "$init" disable || return 1; fi
}
if ! grep -q '^[[:space:]]*channel="debug"[[:space:]]*$' "$init"; then
    tmp=$(mktemp /etc/init.d/.dropbear.ssh-open.XXXXXX)
    cp -p "$init" "$tmp"
    sed 's/^[[:space:]]*channel=.*/\tchannel="debug"/' "$init" > "$tmp"
    sh -n "$tmp" || fail 'Modified init failed syntax check; original preserved.'
    [ "$(md5sum "$tmp" | cut -d ' ' -f 1)" = 2d6bbcc437d74b63ba022055c4e0f109 ] || fail 'Unexpected patch result.'
    mv -f "$tmp" "$init"
    tmp=
fi
if ! { nvram set ssh_en=1 && nvram commit && "$init" enable && "$init" start; }; then
    rollback || fail 'Start failed; automatic rollback incomplete. Inspect printed backup.'
    fail 'Start failed; init, ssh_en and enable state restored. Inspect service manually.'
fi
printf 'SERVICE_STARTED=1\n'
# OPEN_PASSWORD_COMMAND is supplied only for an explicitly requested password change.
__OPEN_PASSWORD_COMMAND__
printf 'SSH_OPEN_OK=1\n'
