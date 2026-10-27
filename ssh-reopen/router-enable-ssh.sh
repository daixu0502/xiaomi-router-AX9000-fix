#!/bin/sh
# Executed through Telnet by reopen_ssh.py; no password is embedded here.
set -eu
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'Telnet session is not root.'
version=/usr/share/xiaoqiang/xiaoqiang_version
model=$(uci -q get "$version.version.HARDWARE" || true)
[ "$model" = RA70 ] || fail "Expected AX9000 / RA70, got: $model"
printf 'MODEL=%s\nROM=%s\n' "$model" "$(uci -q get "$version.version.ROM" || true)"
[ "$(nvram get ssh_en)" = 1 ] || fail 'ssh_en is not 1; check existing hard persistence first.'
init=/etc/init.d/dropbear
[ -f "$init" ] && [ ! -L "$init" ] || fail 'Dropbear init is missing or is a symlink.'
if grep -q '/data/router-ssh-modern' "$init"; then
    fail 'Managed modern Dropbear detected; use ssh-modern/status to inspect it first.'
fi
grep -q 'start_service()' "$init" || fail 'Unrecognized Dropbear init structure.'
count=$(grep -c '^[[:space:]]*channel=' "$init" || true)
[ "$count" = 1 ] || fail 'Expected exactly one channel assignment; no changes made.'
lock=/tmp/router-ssh-reopen.lock
mkdir "$lock" 2>/dev/null || fail 'Another recovery is active, or a stale lock exists.'
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
if ! grep -q '^[[:space:]]*channel="debug"[[:space:]]*$' "$init"; then
    backup=$(mktemp /etc/init.d/dropbear.ssh-reopen.bak.XXXXXX)
    cp -p "$init" "$backup" || fail 'Cannot back up init.'
    printf 'BACKUP=%s\n' "$backup"
    tmp=$(mktemp /etc/init.d/.dropbear.ssh-reopen.XXXXXX)
    cp -p "$init" "$tmp"
    sed 's/^[[:space:]]*channel=.*/\tchannel="debug"/' "$init" > "$tmp"
    sh -n "$tmp" || fail 'Modified init failed syntax check; original preserved.'
    mv -f "$tmp" "$init"
    tmp=
    if ! "$init" start; then
        tmp=$(mktemp /etc/init.d/.dropbear.ssh-reopen.XXXXXX)
        cp -p "$backup" "$tmp"
        mv -f "$tmp" "$init"
        tmp=
        fail 'Dropbear start failed; original init restored. Check service via Telnet.'
    fi
else
    printf 'UNCHANGED=channel already debug\n'
    "$init" start || fail 'Dropbear start failed.'
fi
# Report every configured port, retaining the router configuration.
ports=$(uci -q show dropbear | sed -n "s/.*\.Port='\([0-9][0-9]*\)'$/\1/p")
if [ -n "$ports" ]; then
    for port in $ports; do printf 'PORT=%s\n' "$port"; done
else
    printf 'PORT=22\n'
fi
printf 'ENABLE_DONE=1\n'
