#!/bin/sh
# AX9000 stock LuCI: adapt the DHCP controller to its nine-argument utility.
# The installer does not change DHCP/network settings or restart any service.
set -eu
TARGET=/usr/lib/lua/luci/controller/api/xqnetwork.lua
UTIL=/usr/lib/lua/xiaoqiang/util/XQLanWanUtil.lua
BASE=/data/router-dhcp-web-fix
LOCK=/tmp/router-dhcp-web-fix.lock
STOCK_HASH=979355ee209f64621438497cb7d52f60
UTIL_HASH=14fa2c202541622b68bb4d3109e88677
MARKER='-- router-dhcp-web-fix v1'
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
for tool in md5sum awk cmp mktemp cp mv lua luac; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令：$tool"
done
[ -f "$TARGET" ] && [ ! -L "$TARGET" ] || die '控制器文件不存在或为符号链接。'
[ -f "$UTIL" ] && [ ! -L "$UTIL" ] || die 'DHCP 工具模块不存在或为符号链接。'
[ "$(hash "$UTIL")" = "$UTIL_HASH" ] || die 'DHCP 工具模块版本不匹配，拒绝修改。'
[ ! -L "$BASE" ] || die '备份目录不能为符号链接。'

check_backup() {
    for file in xqnetwork.original.lua xqnetwork.fixed.lua; do
        [ -f "$BASE/$file" ] && [ ! -L "$BASE/$file" ] || die '备份不完整或为符号链接。'
    done
    [ "$(hash "$BASE/xqnetwork.original.lua")" = "$STOCK_HASH" ] || die '原始备份校验失败。'
}

if [ "$ACTION" = status ]; then
    if [ "$(hash "$TARGET")" = "$STOCK_HASH" ]; then
        say '尚未安装：原厂控制器仍使用七参数调用，工具模块要求九参数。'
    elif grep -q -F -- "$MARKER" "$TARGET"; then
        check_backup
        cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '已安装控制器发生变化，请人工核对。'
        say '已安装 DHCP Web 参数修复，原厂其他接口通过备份模块保留。'
    else
        die '控制器版本不匹配，未修改文件。'
    fi
    exit 0
fi

mkdir "$LOCK" 2>/dev/null || die "已有操作或残留锁：$LOCK；请确认没有其他实例运行。"
LOCKED=1
umask 077
if [ "$ACTION" = restore ]; then
    check_backup
    if [ "$(hash "$TARGET")" = "$STOCK_HASH" ]; then say '已经是原始控制器，无需恢复。'; exit 0; fi
    cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '当前控制器在安装后已改变，拒绝覆盖。'
    TMP=$(mktemp "${TARGET}.dhcp-fix.XXXXXX")
    cp -p "$BASE/xqnetwork.original.lua" "$TMP"
    luac -p "$TMP"
    cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '当前控制器在操作期间发生变化，未恢复。'
    mv -f "$TMP" "$TARGET"
    TMP=
    say '已恢复原始控制器；备份保留，未修改 DHCP 配置，未重启服务。'
    exit 0
fi

if grep -q -F -- "$MARKER" "$TARGET"; then
    check_backup
    cmp -s "$TARGET" "$BASE/xqnetwork.fixed.lua" || die '当前控制器在安装后已改变，拒绝覆盖。'
    say '已经安装本版本，无需重复修改。'
    exit 0
fi
[ "$(hash "$TARGET")" = "$STOCK_HASH" ] || die '不是已核对的原厂控制器，拒绝覆盖。'
mkdir -p "$BASE"
chmod 0700 "$BASE"
[ ! -L "$BASE/xqnetwork.original.lua" ] && [ ! -L "$BASE/xqnetwork.fixed.lua" ] || die '备份文件不能为符号链接。'
if [ -f "$BASE/xqnetwork.original.lua" ]; then
    [ "$(hash "$BASE/xqnetwork.original.lua")" = "$STOCK_HASH" ] || die '已有原始备份校验失败。'
else
    cp -p "$TARGET" "$BASE/xqnetwork.original.lua"
fi
TMP=$(mktemp "${TARGET}.dhcp-fix.XXXXXX")
cp -p "$TARGET" "$TMP"
cat > "$TMP" <<'DHCP_CONTROLLER_LUA'
-- router-dhcp-web-fix v1
-- Keep stock registration/authentication and every other API implementation.
assert(loadfile('/data/router-dhcp-web-fix/xqnetwork.original.lua'))()
local controller = assert(package.loaded['luci.controller.api.xqnetwork'])
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
local function integer(value)
    if type(value) ~= 'string' or not value:match('^%d+$') then return nil end
    return tonumber(value)
end

controller.setLanDhcp = function()
    local ignore = http.formvalue('ignore')
    if ignore ~= nil and ignore ~= '0' and ignore ~= '1' then
        return fail('DHCP 开关参数无效')
    end
    if ignore == '1' then
        -- start/end/startip/endip/leasetime/ignore/router/dns1/dns2
        util.setLanDHCPService(nil,nil,nil,nil,nil,'1',nil,nil,nil)
        http.write_json({code=0})
        return
    end
    local lease = http.formvalue('leasetime')
    local number, unit
    if type(lease) == 'string' then number,unit = lease:match('^(%d+)([hm])$') end
    number = tonumber(number)
    local minutes = number and number * (unit == 'h' and 60 or 1)
    if not minutes or minutes<2 or minutes>2880 then
        return fail('租期必须为 2–2880 分钟（支持 m 或 h 单位）')
    end
    local router,dns1,dns2 = http.formvalue('router'),http.formvalue('dns1'),http.formvalue('dns2')
    for _,value in pairs({router=router,dns1=dns1,dns2=dns2}) do
        if value ~= '' and not ipv4(value) then return fail('网关和 DNS 必须为 IPv4 地址或留空') end
    end
    local lan = util.getLanDHCPService().lanIp
    local address = lan and lan[1]
    local ip = address and ipv4(address.ip)
    local mask = address and address.mask
    if not ip then return fail('无法读取当前 LAN 地址，未修改配置') end
    local first,last,startip,endip,startoffset,endoffset
    if mask == '255.255.255.0' then
        first,last = integer(http.formvalue('start')),integer(http.formvalue('end'))
        if not first or not last or first<1 or last>254 or first>last then
            return fail('开始和结束地址必须在 1–254 内，且结束地址不小于开始地址')
        end
    elseif mask == '255.255.0.0' then
        startip,endip = http.formvalue('startip'),http.formvalue('endip')
        local a,b = ipv4(startip),ipv4(endip)
        if not a or not b or a[1]~=ip[1] or a[2]~=ip[2] or b[1]~=ip[1] or b[2]~=ip[2] then
            return fail('地址池必须位于当前 LAN /16 网段内')
        end
        startoffset,endoffset = a[3]*256+a[4],b[3]*256+b[4]
        if startoffset<1 or endoffset>65534 or endoffset<startoffset or endoffset-startoffset+1>1000 then
            return fail('地址池顺序或范围无效，最多允许 1000 个地址')
        end
    else
        return fail('当前子网掩码不在此版本支持的 /24 或 /16 范围内')
    end
    if startip then
        -- The same stock utility also reverses /16 pool subtraction, producing
        -- a negative limit. Write the validated offsets/count in one commit.
        local cursor = require('luci.model.uci').cursor()
        cursor:set('dhcp','lan','start',tostring(startoffset))
        cursor:set('dhcp','lan','startip',startip)
        cursor:set('dhcp','lan','endip',endip)
        cursor:set('dhcp','lan','limit',tostring(endoffset-startoffset+1))
        cursor:set('dhcp','lan','leasetime',lease)
        cursor:delete('dhcp','lan','ignore')
        for key,value in pairs({router=router,dns1=dns1,dns2=dns2}) do
            cursor:set('dhcp','lan',key,value)
        end
        if not cursor:save('dhcp') or not cursor:commit('dhcp') then
            return fail('DHCP 配置保存失败，请检查存储状态')
        end
        require('luci.util').exec('/etc/init.d/dnsmasq restart > /dev/null')
    else
        -- Fix the stock seven-argument caller: leave explicit /24 placeholders.
        util.setLanDHCPService(first,last,nil,nil,lease,'0',router,dns1,dns2)
    end
    common.forkReboot()
    http.write_json({code=0})
end
return controller
DHCP_CONTROLLER_LUA
luac -p "$TMP"
lua - "$TMP" <<'CHECK_LUA'
local controller = assert(loadfile(arg[1]))()
assert(type(controller.index)=='function', 'stock registration missing')
assert(type(controller.getLanDhcp)=='function', 'stock reader missing')
assert(type(controller.setLanDhcp)=='function', 'corrected writer missing')
CHECK_LUA
cmp -s "$TARGET" "$BASE/xqnetwork.original.lua" || die '控制器在操作期间发生变化，未覆盖。'
cp -p "$TMP" "$BASE/xqnetwork.fixed.lua"
mv -f "$TMP" "$TARGET"
TMP=
say 'DHCP Web 修复已安装：已修正参数映射及 /16 地址池计数，兼容 /24 和 /16。'
say "原厂控制器备份：$BASE/xqnetwork.original.lua"
say "恢复命令：sh $0 restore"
say '安装过程未修改 DHCP/网络配置，未重启服务。请刷新页面。'
