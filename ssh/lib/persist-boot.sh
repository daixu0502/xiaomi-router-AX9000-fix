#!/bin/sh
# Firewall include; also invoked by the persistence installer. No flash writes.
set -eu
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
init=/etc/init.d/dropbear
modern=/data/router-ssh-modern
version=/usr/share/xiaoqiang/xiaoqiang_version
[ "$(id -u)" = 0 ] || fail 'Root is required.'
[ "$(uci -q get "$version.version.HARDWARE")" = RA70 ] || fail 'Expected RA70.'
case "$(uci -q get "$version.version.ROM")" in 1.0.140|1.0.168) ;; *) fail 'Unsupported firmware.';; esac
[ -f "$init" ] && [ ! -L "$init" ] || fail 'Missing or symlinked init.'
[ ! -e "$modern/pending" ] || fail 'Modern SSH confirmation is pending; persistence deferred.'
hash=$(md5sum "$init" | awk '{print $1}')
case "$hash" in
    c91b64a8932e0d35ea95597c24485338|2d6bbcc437d74b63ba022055c4e0f109)
        [ "$(md5sum /usr/sbin/dropbear | awk '{print $1}')" = 1586d632c1b4e960ea0a406ed0758c02 ] || fail 'Unknown stock Dropbear binary.';;
    *)
        [ -f "$modern/dropbear.init.managed" ] && [ ! -L "$modern/dropbear.init.managed" ] &&
            cmp -s "$init" "$modern/dropbear.init.managed" || fail 'Unknown init; refusing to overwrite.';;
esac
[ "${1:-boot}" != check ] || { echo 'BOOT_CHECK_OK=1'; exit 0; }
lock=/tmp/router-ssh-persist-boot.lock
mkdir "$lock" 2>/dev/null || exit 0
tmp=
cleanup() { [ -z "$tmp" ] || rm -f "$tmp"; rmdir "$lock" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
if [ "$hash" = c91b64a8932e0d35ea95597c24485338 ]; then
    tmp=$(mktemp /etc/init.d/.dropbear.persist.XXXXXX)
    cp -p "$init" "$tmp"
    sed 's/^[[:space:]]*channel=.*/\tchannel="debug"/' "$init" > "$tmp"
    sh -n "$tmp"
    [ "$(md5sum "$tmp" | awk '{print $1}')" = 2d6bbcc437d74b63ba022055c4e0f109 ] || fail 'Unexpected patch result.'
    mv -f "$tmp" "$init"; tmp=
fi
if [ "$(nvram get ssh_en)" != 1 ]; then nvram set ssh_en=1; nvram commit; fi
"$init" enable
# procd sets the same service definition; do not restart an existing SSH session.
"$init" start
echo 'SSH_BOOT_REPAIR_OK=1'
