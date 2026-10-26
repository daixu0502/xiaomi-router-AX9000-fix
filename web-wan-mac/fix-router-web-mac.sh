#!/bin/sh
# Xiaomi AX9000: guard a missing client MAC in the stock WAN LuCI template.
# Only edits the known expression; does not restart any service.
set -eu

TARGET=/usr/lib/lua/luci/view/web/setting/wan.htm
BASE=/data/router-web-mac-fix
LOCK=/tmp/router-web-mac-fix.lock
OLD='string.upper(luci.sys.net.ip4mac(remote_addr))'
NEW='string.upper(luci.sys.net.ip4mac(remote_addr) or "")'
TMP=
LOCKED=0

say() { printf '%s\n' "$*"; }
die() { say "错误：$*" >&2; exit 1; }
usage() {
    say "用法：sh $0 [apply|status|restore 备份编号]"
    say '  apply     修复 WAN 页面获取不到访问者 MAC 时的 HTTP 500（默认）'
    say '  status    检查模板是否包含本脚本支持的原表达式或修复表达式'
    say '  restore   使用 apply 输出的 backup-XXXXXX 编号恢复原模板'
    say '只修改 WAN 页面模板，不修改 MAC、WAN、端口转发或 Docker 配置，不重启服务。'
}
cleanup() {
    [ -z "$TMP" ] || rm -f "$TMP"
    if [ "$LOCKED" = 1 ]; then rmdir "$LOCK" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Count literal occurrences, not regex matches. Unknown/ambiguous versions fail closed.
classify() {
    awk -v old="$OLD" -v new="$NEW" '
        function occurrences(line, needle, n, p) {
            n=0
            while ((p=index(line, needle))>0) { n++; line=substr(line,p+length(needle)) }
            return n
        }
        { before+=occurrences($0,old); after+=occurrences($0,new) }
        END {
            if(before==1 && after==0) print "original"
            else if(before==0 && after==1) print "fixed"
            else print "unknown"
        }
    ' "$1"
}

ACTION=${1:-apply}
case "$ACTION" in -h|--help) usage; exit 0 ;; esac
case "$ACTION" in
    apply|status) [ "$#" -le 1 ] || { usage; exit 2; } ;;
    restore) [ "$#" -eq 2 ] || { usage; exit 2; } ;;
    *) usage; exit 2 ;;
esac
[ "$(id -u)" = 0 ] || die '请在路由器上以 root 运行。'
[ -f "$TARGET" ] && [ ! -L "$TARGET" ] || die "未找到受支持的普通模板文件：$TARGET"
for tool in awk cmp cp mktemp mv; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令：$tool"
done

if [ "$ACTION" = status ]; then
    case "$(classify "$TARGET")" in
        original) say '尚未修复：模板直接将 MAC 查询结果传给 string.upper()。' ;;
        fixed) say '已包含空值保护：查不到 MAC 时使用空字符串。' ;;
        *) die '模板版本或修改方式不匹配，请人工核对；未修改文件。' ;;
    esac
    exit 0
fi

mkdir "$LOCK" 2>/dev/null || die "已有操作或残留锁：$LOCK；请确认没有其他实例在运行。"
LOCKED=1
umask 077

if [ "$ACTION" = restore ]; then
    BACKUP_ID=$2
    case "$BACKUP_ID" in backup-*) ;; *) die '备份编号应为 backup-XXXXXX。' ;; esac
    case "$BACKUP_ID" in *[!a-zA-Z0-9-]*) die '备份编号不能包含路径或特殊字符。' ;; esac
    BACKUP=$BASE/$BACKUP_ID
    [ -d "$BACKUP" ] && [ ! -L "$BACKUP" ] || die '备份目录不存在或为符号链接。'
    for name in wan.htm.original wan.htm.fixed; do
        [ -f "$BACKUP/$name" ] && [ ! -L "$BACKUP/$name" ] || die '备份文件不完整或为符号链接。'
    done
    [ "$(classify "$BACKUP/wan.htm.original")" = original ] || die '原始备份不符合预期。'
    [ "$(classify "$BACKUP/wan.htm.fixed")" = fixed ] || die '修复备份不符合预期。'
    if cmp -s "$TARGET" "$BACKUP/wan.htm.original"; then
        say '模板已经是此备份的原始内容，无需恢复。'
        exit 0
    fi
    cmp -s "$TARGET" "$BACKUP/wan.htm.fixed" || die '当前模板在修复后发生了变化，拒绝覆盖；请人工核对备份。'
    TMP=$(mktemp "${TARGET}.mac-fix.XXXXXX") || die '无法在模板目录创建恢复暂存文件。'
    cp -p "$BACKUP/wan.htm.original" "$TMP"
    cmp -s "$TARGET" "$BACKUP/wan.htm.fixed" || die '当前模板在操作期间发生了变化，未恢复。'
    mv -f "$TMP" "$TARGET"
    TMP=
    say '已恢复原模板。未重启任何服务。'
    exit 0
fi

case "$(classify "$TARGET")" in
    fixed) say '模板已包含空值保护，无需重复修改。'; exit 0 ;;
    original) ;;
    *) die '模板版本或表达式数量不匹配，拒绝覆盖；未修改文件。' ;;
esac
[ ! -L "$BASE" ] || die '备份根目录不能是符号链接。'
mkdir -p "$BASE"
chmod 0700 "$BASE"
BACKUP=$(mktemp -d "$BASE/backup-XXXXXX") || die '无法创建备份目录。'
cp -p "$TARGET" "$BACKUP/wan.htm.original"
TMP=$(mktemp "${TARGET}.mac-fix.XXXXXX") || die '无法在模板目录创建暂存文件。'
cp -p "$BACKUP/wan.htm.original" "$TMP"
awk -v old="$OLD" -v new="$NEW" '
    {
        p=index($0,old)
        if(p>0) $0=substr($0,1,p-1) new substr($0,p+length(old))
        print
    }
' "$BACKUP/wan.htm.original" > "$TMP"
[ "$(classify "$TMP")" = fixed ] || die '修复结果校验失败，原模板未修改。'
cp -p "$TMP" "$BACKUP/wan.htm.fixed"
cmp -s "$TARGET" "$BACKUP/wan.htm.original" || die '当前模板在操作期间发生了变化，原模板未覆盖。'
mv -f "$TMP" "$TARGET"
TMP=
say '修复完成：访问者 MAC 查不到时使用空字符串，避免 string.upper(nil)。'
say "备份目录：$BACKUP"
say "恢复命令：sh $0 restore ${BACKUP##*/}"
say '请刷新 WAN 设置页面验证。未修改网络配置，未重启任何服务。'
