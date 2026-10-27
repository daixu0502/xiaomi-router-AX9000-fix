#!/bin/sh
# RA70 1.0.168: correct only the Web DHCP /16 save path.
# Installing/restoring this wrapper never changes network settings or services.
set -eu
TARGET=/usr/lib/lua/luci/controller/api/xqnetwork.lua
UTIL=/usr/lib/lua/xiaoqiang/util/XQLanWanUtil.lua
VERSION_FILE=/usr/share/xiaoqiang/xiaoqiang_version
BASE=/data/router-dhcp16-web-fix-1.0.168
LOCK=/tmp/router-dhcp16-web-fix-1.0.168.lock
STOCK_HASH=2d636e2ac2170f519d353f506d90aad7
UTIL_HASH=ee5889a76bc7a43cd61ec5c68fbfa915
MARKER='-- router-dhcp16-web-fix 1.0.168 v1'
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
ACTION=${1:-apply}
[ "$#" -le 1 ] || die "用法：sh $0 [apply|status|restore]"
case "$ACTION" in
    -h|--help) say "用法：sh $0 [apply|status|restore]"; exit 0 ;;
    apply|status|restore) ;;
    *) die "用法：sh $0 [apply|status|restore]" ;;
esac
[ "$(id -u)" = 0 ] || die '请在路由器上以 root 运行。'
for tool in md5sum awk cmp mktemp cp mv lua luac grep; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令：$tool"
done
[ -f "$VERSION_FILE" ] || die '无法读取固件版本。'
ROM=$(awk '$1=="option" && $2=="ROM" {gsub(/[\047\042]/,"",$3); print $3}' "$VERSION_FILE")
MODEL=$(awk '$1=="option" && $2=="HARDWARE" {gsub(/[\047\042]/,"",$3); print $3}' "$VERSION_FILE")
[ "$ROM" = 1.0.168 ] && [ "$MODEL" = RA70 ] || die '仅支持 RA70 原厂稳定版 1.0.168。'
[ -f "$TARGET" ] && [ ! -L "$TARGET" ] || die '控制器文件不存在或为符号链接。'
[ -f "$UTIL" ] && [ ! -L "$UTIL" ] || die 'DHCP 工具模块不存在或为符号链接。'
[ "$(hash "$UTIL")" = "$UTIL_HASH" ] || die 'DHCP 工具模块摘要不匹配，拒绝修改。'
[ ! -L "$BASE" ] || die '备份目录不能为符号链接。'
check_backup() {
    for file in xqnetwork.original.lua xqnetwork.fixed.lua; do
        [ -f "$BASE/$file" ] && [ ! -L "$BASE/$file" ] || die '备份不完整或为符号链接。'
    done
    [ "$(hash "$BASE/xqnetwork.original.lua")" = "$STOCK_HASH" ] || die '原始备份摘要不匹配。'
}
if [ "$ACTION" = status ]; then
    if [ "$(hash "$TARGET")" = "$STOCK_HASH" ]; then
        say '尚未安装：1.0.168 已修复 /24 参数错位，但 /16 地址池计数与起始偏移仍需修复。'
    elif grep -q -F -- "$MARKER" "$TARGET"; then
        check_backup
        cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '已安装控制器发生变化，请人工核对。'
        say '已安装 1.0.168 /16 DHCP Web 修复；/24 与关闭 DHCP 委托原厂处理。'
    else
        die '控制器摘要或修复版本不匹配，未修改文件。'
    fi
    exit 0
fi
mkdir "$LOCK" 2>/dev/null || die "已有操作或残留锁：$LOCK；请先核对。"
LOCKED=1
umask 077
if [ "$ACTION" = restore ]; then
    check_backup
    if [ "$(hash "$TARGET")" = "$STOCK_HASH" ]; then say '已经是原始控制器，无需恢复。'; exit 0; fi
    cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '控制器在安装后已改变，拒绝覆盖。'
    TMP=$(mktemp "${TARGET}.dhcp16-fix.XXXXXX")
    cp -p "$BASE/xqnetwork.original.lua" "$TMP"
    luac -p "$TMP"
    cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '控制器在操作期间发生变化，未恢复。'
    mv -f "$TMP" "$TARGET"
    TMP=
    say '已恢复原始控制器；未修改 DHCP 配置，未重启服务。备份保留。'
    exit 0
fi
if grep -q -F -- "$MARKER" "$TARGET"; then
    check_backup
    cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '当前控制器在安装后已改变，拒绝覆盖。'
    say '已经安装本版本，无需重复修改。'
    exit 0
fi
[ "$(hash "$TARGET")" = "$STOCK_HASH" ] || die '不是已核对的 1.0.168 原厂控制器，拒绝覆盖。'
mkdir -p "$BASE"
chmod 0700 "$BASE"
for file in xqnetwork.original.lua xqnetwork.fixed.lua; do
    [ ! -L "$BASE/$file" ] || die '备份文件不能为符号链接。'
done
if [ -f "$BASE/xqnetwork.original.lua" ]; then
    [ "$(hash "$BASE/xqnetwork.original.lua")" = "$STOCK_HASH" ] || die '已有原始备份摘要不匹配。'
else
    cp -p "$TARGET" "$BASE/xqnetwork.original.lua"
fi
TMP=$(mktemp "${TARGET}.dhcp16-fix.XXXXXX")
cp -p "$TARGET" "$TMP"
cat > "$TMP" <<'DHCP_CONTROLLER_LUA'
-- router-dhcp16-web-fix 1.0.168 v1
-- Preserve the exact 1.0.168 registration, authentication and unrelated APIs.
assert(loadfile('/data/router-dhcp16-web-fix-1.0.168/xqnetwork.original.lua'))()
local controller = assert(package.loaded['luci.controller.api.xqnetwork'])
local stockSave = assert(controller.setLanDhcp)
local http = require 'luci.http'
local util = require 'xiaoqiang.util.XQLanWanUtil'
local common = require 'xiaoqiang.common.XQFunction'

local function fail(message)
    http.write_json({code=1537, msg=message})
end
local function ipv4(value)
    if type(value) ~= 'string' then return nil end
    local a,b,c,d = value:match('^(%d+)%.(%d+)%.(%d+)%.(%d+)$')
    if not a then return nil end
    a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
    if a>255 or b>255 or c>255 or d>255 then return nil end
    return {a,b,c,d}
end

controller.setLanDhcp = function()
    local startip,endip = http.formvalue('startip'),http.formvalue('endip')
    local ignore = http.formvalue('ignore')
    -- Do not replace the already corrected /24 or disable implementations.
    if ignore == '1' or (startip == nil and endip == nil) then
        return stockSave()
    end
    local lan = util.getLanWanIp('lan')
    local address = lan and lan[1]
    if not address or address.mask ~= '255.255.0.0' then return stockSave() end
    if ignore ~= '0' then return fail('DHCP 开关参数无效') end
    local ip,a,b = ipv4(address.ip),ipv4(startip),ipv4(endip)
    if not ip or not a or not b or a[1]~=ip[1] or a[2]~=ip[2] or b[1]~=ip[1] or b[2]~=ip[2] then
        return fail('地址池必须位于当前 LAN /16 网段内')
    end
    local first,last = a[3]*256+a[4],b[3]*256+b[4]
    local count = last-first+1
    if first<1 or last>65534 or count<1 or count>1000 then
        return fail('地址池顺序或范围无效，最多允许 1000 个地址')
    end
    local lease = http.formvalue('leasetime')
    local number,unit
    if type(lease)=='string' then number,unit=lease:match('^(%d+)([hm])$') end
    number=tonumber(number)
    local minutes=number and number*(unit=='h' and 60 or 1)
    if not minutes or minutes<2 or minutes>2880 then
        return fail('租期必须为 2–2880 分钟（支持 m 或 h 单位）')
    end
    local options={router=http.formvalue('router'),dns1=http.formvalue('dns1'),dns2=http.formvalue('dns2')}
    for _,value in pairs(options) do
        if value~='' and not ipv4(value) then return fail('网关和 DNS 必须为 IPv4 地址或留空') end
    end
    local cursor=require('luci.model.uci').cursor()
    local values={start=tostring(first),limit=tostring(count),startip=startip,endip=endip,leasetime=lease}
    for key,value in pairs(options) do values[key]=value end
    for key,value in pairs(values) do
        if not cursor:set('dhcp','lan',key,value) then return fail('DHCP 配置暂存失败') end
    end
    -- An absent ignore option is the enabled state, matching the stock writer.
    cursor:delete('dhcp','lan','ignore')
    if not cursor:save('dhcp') or not cursor:commit('dhcp') then
        return fail('DHCP 配置保存失败，请检查存储状态')
    end
    require('luci.util').exec('/etc/init.d/dnsmasq restart > /dev/null')
    common.forkReboot()
    http.write_json({code=0})
end
return controller
DHCP_CONTROLLER_LUA
luac -p "$TMP"
lua - "$TMP" <<'CHECK_LUA'
local controller = assert(loadfile(arg[1]))()
assert(type(controller.index)=='function', 'stock registration missing')
assert(type(controller.getLanDhcp)=='function', 'stock DHCP reader missing')
assert(type(controller.setLanDhcp)=='function', 'corrected writer missing')
CHECK_LUA
cmp -s "$TARGET" "$BASE/xqnetwork.original.lua" || die '控制器在操作期间变化，未覆盖。'
cp -p "$TMP" "$BASE/xqnetwork.fixed.lua"
mv -f "$TMP" "$TARGET"
TMP=
say '1.0.168 /16 DHCP Web 修复已安装：正确保存起始偏移与正数地址数量，保留原厂 /24 和其他 API。'
say "原厂备份：$BASE/xqnetwork.original.lua"
say "恢复命令：sh $0 restore"
say '安装未修改 DHCP/网络配置，未重启服务。请刷新页面。'
