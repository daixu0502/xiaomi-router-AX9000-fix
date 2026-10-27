#!/bin/sh
# WSL/Linux SSH transport. Router scripts remain plain /bin/sh.
set -eu
DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
family=${1:?}; host=${2:?}; action=${3:-status}
[ "$#" -lt 3 ] && shift 2 || shift 3
port=22
backup_parent=$DIR/../local/ssh-backups
fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
case "$host" in ''|-*|*[!a-zA-Z0-9.-]*) fail '请输入单个 IP 地址或主机名。';; esac
case "$family:$action" in
    persist:status|persist:install|persist:harden|persist:remove|modern:prepare|modern:candidate-ok|modern:activate|modern:confirm|modern:status|modern:restore) ;;
    *) fail '不支持的远程操作。';;
esac
while [ "$#" -gt 0 ]; do
    case "$1" in
        --ssh-port) [ "$#" -ge 2 ] || fail '缺少端口。'; port=$2; shift 2;;
        --backup-dir) [ "$#" -ge 2 ] || fail '缺少本机备份目录。'; backup_parent=$2; shift 2;;
        *) fail '未知参数。';;
    esac
done
case "$port" in ''|*[!0-9]*) fail '端口必须为整数。';; esac
[ "$port" -ge 1 ] && [ "$port" -le 65535 ] || fail '端口范围 1–65535。'
for tool in ssh tar sha256sum mktemp awk; do command -v "$tool" >/dev/null || fail "缺少 $tool"; done
if [ "$action" = harden ]; then command -v python3 >/dev/null || fail 'Bdata CRC/字段验证需要 Python 3。'; fi
[ -f "$DIR/SHA256SUMS" ] || fail '缺少完整工具清单，请使用完整包，或在源码目录执行 python3 build-package.py。'
(cd "$DIR"; sha256sum -c SHA256SUMS >/dev/null) || fail '工具文件校验失败。'
umask 077
work=$(mktemp -d /tmp/router-ssh-client.XXXXXX)
remote=
sshrun() {
    ssh -p "$port" -o ConnectTimeout=10 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 \
        -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedAlgorithms=+ssh-rsa \
        -o ControlMaster=auto -o ControlPersist=30 -o "ControlPath=$work/control" "root@$host" "$@"
}
cleanup() {
    if [ -n "$remote" ] && printf '%s\n' "$remote" | grep -Eq '^/tmp/router-ssh-tool\.[A-Za-z0-9]{6}$' &&
        ssh -p "$port" -o "ControlPath=$work/control" -O check "root@$host" </dev/null >/dev/null 2>&1; then
        # A service switch can close the master. Cleanup must never ask for a new
        # password or consume the confirmation window trying to reconnect.
        ssh -p "$port" -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=3 -o ServerAliveCountMax=1 \
            -o ControlMaster=no -o "ControlPath=$work/control" "root@$host" \
            "test ! -L '$remote' && rm -rf -- '$remote'" </dev/null >/dev/null 2>&1 || true
    fi
    ssh -p "$port" -o "ControlPath=$work/control" -O exit "root@$host" </dev/null >/dev/null 2>&1 || true
    case "$work" in /tmp/router-ssh-client.??????) rm -rf -- "$work";; esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
reply=$(sshrun 'umask 077; d=$(mktemp -d /tmp/router-ssh-tool.XXXXXX) || exit 1; printf "TOOL_DIR=%s\n" "$d"')
remote=$(printf '%s\n' "$reply" | sed -n 's/^TOOL_DIR=//p')
printf '%s\n' "$remote" | grep -Eq '^/tmp/router-ssh-tool\.[A-Za-z0-9]{6}$' || fail '远端临时目录响应不正确。'
awk '{print $2}' "$DIR/SHA256SUMS" > "$work/files"
printf 'SHA256SUMS\n' >> "$work/files"
tar -C "$DIR" -czf "$work/tool.tar.gz" -T "$work/files"
sshrun "tar -xzf - -C '$remote' && cd '$remote' && sha256sum -c SHA256SUMS >/dev/null" < "$work/tool.tar.gz"
if [ "$family:$action" != persist:harden ]; then
    sshrun "sh '$remote/ssh.sh' '$family' '$action'"
    exit 0
fi
reply=$(sshrun "sh '$remote/ssh.sh' persist backup")
backup=$(printf '%s\n' "$reply" | sed -n 's/^BACKUP_DIR=//p')
printf '%s\n' "$backup" | grep -Eq '^/data/router-ssh/persist/backups/bdata\.[A-Za-z0-9]{6}$' || fail '远端备份路径不正确。'
mkdir -p "$backup_parent"
local_backup=$(mktemp -d "$backup_parent/ax9000-$host.XXXXXX")
chmod 0700 "$local_backup"
# Fixed file names only; never pull an entire router directory or private SSH keys.
for file in bdata.bin SHA256SUMS flags.before metadata; do
    sshrun "test -f '$backup/$file' && test ! -L '$backup/$file' && cat '$backup/$file'" > "$local_backup/$file" ||
        fail '备份下载失败；未开始 Bdata 写入。'
done
grep -Eq '^[a-f0-9]{64}  bdata.bin$' "$local_backup/SHA256SUMS" &&
    [ "$(wc -l < "$local_backup/SHA256SUMS")" -eq 1 ] || fail '备份校验清单异常。'
(cd "$local_backup"; sha256sum -c SHA256SUMS)
python3 "$DIR/lib/verify_bdata.py" "$local_backup/bdata.bin"
expected=$(sha256sum "$local_backup/bdata.bin" | awk '{print $1}')
printf '离机备份已保存：%s\n' "$local_backup"
result=0
sshrun "sh '$remote/ssh.sh' persist harden --backup '$backup' --backup-sha '$expected'" || result=$?
if sshrun "test -f '$backup/bdata.after.bin' && test ! -L '$backup/bdata.after.bin'"; then
    for file in bdata.after.bin SHA256SUMS.after flags.after; do
        sshrun "test -f '$backup/$file' && test ! -L '$backup/$file' && cat '$backup/$file'" > "$local_backup/$file" ||
            fail '写后数据下载失败；可能已写入，请先核对状态，离机备份已保留。'
    done
    grep -Eq '^[a-f0-9]{64}  bdata.after.bin$' "$local_backup/SHA256SUMS.after" &&
        [ "$(wc -l < "$local_backup/SHA256SUMS.after")" -eq 1 ] || fail '写后校验清单异常。'
    (cd "$local_backup"; sha256sum -c SHA256SUMS.after)
    python3 "$DIR/lib/verify_bdata.py" "$local_backup/bdata.bin" "$local_backup/bdata.after.bin" ||
        fail 'Bdata 写入已执行，写后验证失败；保留备份，请勿自动刷回整个分区。'
else
    fail '未取得写后 Flash 数据；可能已写入，请先核对状态，离机备份已保留。'
fi
[ "$result" = 0 ] || fail 'Bdata 写后数据已核对，但路由器操作未全部成功；请检查上方输出。'
echo '完成：软件固化已安装，Bdata SSH/Telnet 开关及 CRC、其余字段验证通过。'
echo '这不保证 OTA/重置后 SSH 自动可用；升级后先检查，必要时使用 recover。'
