#!/bin/sh
# AX9000: staged Dropbear upgrade, same port and authentication settings.
set -eu
BASE=/data/router-ssh-modern
INIT=/etc/init.d/dropbear
BIN=$BASE/bin/dropbear
SELF=$BASE/fix-router-ssh-modern.sh
RSA=/etc/dropbear/dropbear_rsa_host_key
ED=$BASE/keys/dropbear_ed25519_host_key
EC=$BASE/keys/dropbear_ecdsa_host_key
LOCK=/tmp/router-ssh-modern.lock
STOCK_INIT_MD5=2d6bbcc437d74b63ba022055c4e0f109
STOCK_CONFIG_MD5=776f976aa34d90133a724e4a3c6b3c63
BINARY_MD5=7f47b9c263de7fb3c5707fa3c4675292
TMP=
LOCKED=0
say() { printf '%s\n' "$*"; }
die() { say "错误：$*" >&2; exit 1; }
hash() { md5sum "$1" | awk '{print $1}'; }
cleanup() {
    [ -z "$TMP" ] || rm -f "$TMP"
    if [ "$LOCKED" = 1 ]; then rmdir "$LOCK" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
usage() {
    say "用法：sh $0 prepare [二进制路径] | candidate-ok | activate | confirm | status | restore"
    say 'prepare：备份并启动仅监听 127.0.0.1:13964 的候选服务。'
    say '候选 SSH 登录成功后在该连接中执行 candidate-ok，再通过原连接执行 activate。'
    say 'activate：在原端口 3964 切换；120 秒内必须通过新 SSH 连接执行 confirm，否则回退。'
    say '不改密码、授权公钥、SSH 端口、防火墙或原 RSA 主机密钥。'
}
ACTION=${1:-status}
case "$ACTION" in -h|--help) usage; exit 0 ;; esac
case "$ACTION" in prepare|candidate-ok|activate|confirm|status|restore|watchdog) ;; *) usage; exit 2 ;; esac
if [ "$ACTION" = prepare ]; then [ "$#" -le 2 ] || die '参数过多。'; else [ "$#" -le 1 ] || die '参数过多。'; fi
[ "$(id -u)" = 0 ] || die '请以 root 执行。'
for tool in md5sum awk cmp mktemp readlink; do command -v "$tool" >/dev/null || die "缺少命令：$tool"; done
[ "$(uname -m)" = aarch64 ] || die '只支持 aarch64 路由器。'
[ -f "$INIT" ] && [ ! -L "$INIT" ] || die 'SSH 启动脚本不存在或为符号链接。'
[ -s "$RSA" ] && [ ! -L "$RSA" ] || die '原 RSA 主机密钥不存在或为符号链接。'
[ ! -L "$BASE" ] || die '持久目录不能为符号链接。'

valid_backup() {
    [ -f "$BASE/dropbear.init.original" ] && [ ! -L "$BASE/dropbear.init.original" ] || die '缺少原启动脚本备份。'
    [ "$(hash "$BASE/dropbear.init.original")" = "$STOCK_INIT_MD5" ] || die '原启动脚本备份校验失败。'
}
modern_ancestor() {
    pid=$$
    for step in 1 2 3 4 5 6 7 8 9 10; do
        [ "$pid" -gt 1 ] || return 1
        [ "$(readlink "/proc/$pid/exe" 2>/dev/null || true)" != "$BIN" ] || return 0
        pid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null) || return 1
    done
    return 1
}
stop_candidate() {
    [ -f "$BASE/candidate.pid" ] || return 0
    pid=$(cat "$BASE/candidate.pid")
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$(readlink "/proc/$pid/exe" 2>/dev/null || true)" = "$BIN" ] &&
        tr '\000' '\n' < "/proc/$pid/cmdline" | grep -q -F '127.0.0.1:13964'; then
        kill -TERM "$pid"
    fi
}

if [ "$ACTION" = watchdog ]; then
    trap '' HUP
    # A reboot needs no confirmation: only an active switch has a pending marker.
    for step in $(seq 1 40); do
        [ ! -f "$BASE/pending" ] || [ ! -f "$BASE/confirmed" ] || exit 0
        [ -f "$BASE/pending" ] || exit 0
        sleep 3
    done
    [ ! -f "$BASE/pending" ] || sh "$SELF" restore
    exit 0
fi
if [ "$ACTION" = status ]; then
    if [ "$(hash "$INIT")" = "$STOCK_INIT_MD5" ]; then say '当前为原厂 SSH 启动方式。';
    elif [ -f "$BASE/dropbear.init.managed" ] && cmp -s "$INIT" "$BASE/dropbear.init.managed"; then
        say '当前已配置现代 Dropbear。'
        "$BIN" -V 2>&1
        "$BIN" -Q sig
    else die 'SSH 启动脚本与受支持版本不匹配。'; fi
    [ ! -f "$BASE/pending" ] || say '等待新连接确认；超时将恢复原厂启动方式。'
    exit 0
fi

mkdir "$LOCK" 2>/dev/null || die "已有操作或残留锁：$LOCK"
LOCKED=1
umask 077
if [ "$ACTION" = prepare ]; then
    [ "$(hash /etc/config/dropbear)" = "$STOCK_CONFIG_MD5" ] || die 'SSH 配置与已核对版本不同，拒绝套用启动参数。'
    [ "$(hash "$INIT")" = "$STOCK_INIT_MD5" ] || die '当前不是已核对的原厂启动脚本。'
    INPUT=${2:-$(dirname "$0")/bin/dropbear}
    [ -f "$INPUT" ] && [ ! -L "$INPUT" ] || die '请使用安装包附带的 bin/dropbear。'
    [ "$(hash "$INPUT")" = "$BINARY_MD5" ] || die '二进制校验失败。'
    mkdir -p "$BASE/bin" "$BASE/keys"
    chmod 0700 "$BASE" "$BASE/bin" "$BASE/keys"
    if [ -e "$BASE/dropbear.init.original" ]; then valid_backup; else cp -p "$INIT" "$BASE/dropbear.init.original"; fi
    [ -e "$BASE/dropbear.config.original" ] || cp -p /etc/config/dropbear "$BASE/dropbear.config.original"
    [ ! -e "$BASE/rsa.original.md5" ] || [ "$(hash "$RSA")" = "$(cat "$BASE/rsa.original.md5")" ] || die '原 RSA 密钥已变化。'
    hash "$RSA" > "$BASE/rsa.original.md5"
    if [ -e "$BIN" ]; then
        [ "$(hash "$BIN")" = "$BINARY_MD5" ] || die '已有不同版本，拒绝覆盖。'
    else
        TMP=$(mktemp "$BASE/bin/.dropbear.XXXXXX")
        cp "$INPUT" "$TMP"; chmod 0700 "$TMP"; mv "$TMP" "$BIN"; TMP=
    fi
    "$BIN" -V 2>&1 | grep -q -F '2026.94' || die '版本检查失败。'
    if [ -L "$BASE/bin/dropbearkey" ]; then
        [ "$(readlink "$BASE/bin/dropbearkey")" = dropbear ] || die '已有不同的密钥工具链接。'
    elif [ -e "$BASE/bin/dropbearkey" ]; then die '已有不同的密钥工具。'
    else ln -s dropbear "$BASE/bin/dropbearkey"; fi
    for type in ed25519 ecdsa; do
        key=$BASE/keys/dropbear_${type}_host_key
        [ ! -L "$key" ] || die '密钥不能为符号链接。'
        if [ ! -s "$key" ]; then
            TMP=$(mktemp "$BASE/keys/.key.XXXXXX")
            rm -f "$TMP"
            if [ "$type" = ecdsa ]; then "$BASE/bin/dropbearkey" -t "$type" -s 256 -f "$TMP" >/dev/null;
            else "$BASE/bin/dropbearkey" -t "$type" -f "$TMP" >/dev/null; fi
            chmod 0600 "$TMP"; mv "$TMP" "$key"; TMP=
        fi
    done
    TMP=$(mktemp "$BASE/.installer.XXXXXX")
    cp "$0" "$TMP"; chmod 0700 "$TMP"; mv "$TMP" "$SELF"; TMP=
    if [ -f "$BASE/candidate.pid" ]; then stop_candidate; fi
    rm -f "$BASE/candidate-verified"
    (trap '' HUP; exec "$BIN" -F -E -P "$BASE/candidate.pid" -p 127.0.0.1:13964 \
        -r "$RSA" -r "$ED" -r "$EC" -D /etc/dropbear -K 300 -T 3) </dev/null >/tmp/router-ssh-modern-candidate.log 2>&1 &
    candidate=$!
    sleep 1
    kill -0 "$candidate" 2>/dev/null || die '候选服务启动失败，请检查 /tmp/router-ssh-modern-candidate.log。'
    say '候选服务已启动，仅监听 127.0.0.1:13964；原端口服务未改变。'
    say "在候选 SSH 连接内执行：sh $SELF candidate-ok"
    exit 0
fi

valid_backup
if [ "$ACTION" = candidate-ok ]; then
    set -- ${SSH_CONNECTION:-}
    [ "$#" = 4 ] && [ "$4" = 13964 ] && modern_ancestor || die '必须在候选服务的新 SSH 连接内确认。'
    : > "$BASE/candidate-verified"
    say '候选 SSH 登录已确认。现在可在原连接执行 activate。'
    exit 0
fi
if [ "$ACTION" = confirm ]; then
    set -- ${SSH_CONNECTION:-}
    [ "$#" = 4 ] && [ "$4" = 3964 ] && modern_ancestor || die '必须通过正式端口 3964 的新版 SSH 连接确认。'
    [ -f "$BASE/pending" ] || die '当前没有等待确认的切换。'
    cmp -s "$INIT" "$BASE/dropbear.init.managed" || die '启动脚本已变化。'
    : > "$BASE/confirmed"
    rm -f "$BASE/pending"
    stop_candidate
    say '已确认正式端口的新 SSH 登录，取消超时回退。'
    exit 0
fi
if [ "$ACTION" = restore ]; then
    if [ "$(hash "$INIT")" != "$STOCK_INIT_MD5" ]; then
        cmp -s "$INIT" "$BASE/dropbear.init.managed" || die '启动脚本有其他改动，拒绝覆盖。'
        TMP=$(mktemp /etc/init.d/.dropbear.restore.XXXXXX)
        cp -p "$BASE/dropbear.init.original" "$TMP"; mv "$TMP" "$INIT"; TMP=
    fi
    rm -f "$BASE/pending" "$BASE/confirmed" "$BASE/candidate-verified"
    /etc/init.d/dropbear restart
    stop_candidate
    say '已恢复原厂 SSH 启动方式；主机密钥、配置与现代程序备份均保留。'
    exit 0
fi

[ -f "$BASE/candidate-verified" ] || die '请先通过候选服务验证密码登录并执行 candidate-ok。'
[ ! -f "$BASE/pending" ] || die '已有等待确认的切换。'
[ "$(hash "$INIT")" = "$STOCK_INIT_MD5" ] || die '当前启动脚本不是已核对的原版。'
cmp -s /etc/config/dropbear "$BASE/dropbear.config.original" || die '准备后 SSH 配置已变化。'
[ "$(hash "$RSA")" = "$(cat "$BASE/rsa.original.md5")" ] || die '原 RSA 密钥已变化。'
TMP=$(mktemp /etc/init.d/.dropbear.modern.XXXXXX)
awk '
    /^PROG=\/usr\/sbin\/dropbear$/ {
        print $0
        print "if [ -x /data/router-ssh-modern/bin/dropbear ] && [ -s /data/router-ssh-modern/keys/dropbear_ed25519_host_key ] && [ -s /data/router-ssh-modern/keys/dropbear_ecdsa_host_key ]; then"
        print "    PROG=/data/router-ssh-modern/bin/dropbear"
        print "fi"
        n++; next
    }
    /procd_set_param command "\$PROG" -F -P "\$pid_file"/ {
        print "    if [ \"$PROG\" = /usr/sbin/dropbear ]; then"
        print $0
        print "    else"
        print $0 " -r /etc/dropbear/dropbear_rsa_host_key -r /data/router-ssh-modern/keys/dropbear_ed25519_host_key -r /data/router-ssh-modern/keys/dropbear_ecdsa_host_key -D /etc/dropbear"
        print "    fi"
        m++; next
    }
    { print }
    END { if(n!=1 || m!=1) exit 1 }
' "$INIT" > "$TMP" || die '启动脚本结构不匹配。'
/bin/sh -n "$TMP"
chmod 0755 "$TMP"
cp -p "$TMP" "$BASE/dropbear.init.managed"
rm -f "$BASE/confirmed"
: > "$BASE/pending"
(trap '' HUP; exec /bin/sh "$SELF" watchdog) </dev/null >/tmp/router-ssh-modern-watchdog.log 2>&1 &
mv "$TMP" "$INIT"; TMP=
say '正在切换原端口 3964；120 秒内请通过新版 SSH 登录并执行 confirm。'
/etc/init.d/dropbear restart
say "确认命令：sh $SELF confirm"
