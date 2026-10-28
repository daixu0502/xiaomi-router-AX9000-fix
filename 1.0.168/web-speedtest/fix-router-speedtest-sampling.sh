#!/bin/sh
# Guarded sampling repair for stock AX9000 / RA70 1.0.168.
set -eu
BASE=/data/router-speedtest-sampling-1.0.168
LOCK=/tmp/router-speedtest-sampling-1.0.168.lock
UP=/usr/bin/upload_speedtest
DOWN=/usr/bin/download_speedtest
UP_STOCK=41e01eb536e9f3516e566d57336d0853
DOWN_STOCK=2582995a6b11d5425721879d141bdfd1
UP_FIXED=46112aeba05824b0a30ea8e2dad1bb04
DOWN_FIXED=8a87dbf251173da1cbe833acbe73b833
UP_PREVIOUS=6a4ddc50f5e0ca818984455ee31a05fb
DOWN_PREVIOUS=756ae97cc70bb06930c4908537864a49
ACTION=${1:-apply}
hash() { md5sum "$1" | awk '{print $1}'; }
fail() { echo "错误：$*" >&2; exit 1; }
regular() { [ -f "$1" ] && [ ! -L "$1" ]; }
case "$ACTION" in apply|status|restore) [ "$#" -le 1 ] || fail '参数过多';; *) fail '用法：sh fix-router-speedtest-sampling.sh [apply|status|restore]';; esac
[ "$(id -u)" = 0 ] || fail '需要 root'
for tool in lua luac awk md5sum mktemp cp mv cmp; do command -v "$tool" >/dev/null || fail "缺少 $tool"; done
VERSION=/usr/share/xiaoqiang/xiaoqiang_version
[ "$(awk '$1=="option" && $2=="ROM" {gsub(/[\047\042]/,"",$3);print $3}' "$VERSION")" = 1.0.168 ] || fail '仅适用 1.0.168'
[ "$(awk '$1=="option" && $2=="HARDWARE" {gsub(/[\047\042]/,"",$3);print $3}' "$VERSION")" = RA70 ] || fail '仅适用 RA70'
regular "$UP" && regular "$DOWN" || fail '目标缺失或为符号链接'
U=$(hash "$UP"); D=$(hash "$DOWN")
case "$U" in "$UP_STOCK"|"$UP_FIXED"|"$UP_PREVIOUS") ;; *) fail '上传测速程序含未知修改';; esac
case "$D" in "$DOWN_STOCK"|"$DOWN_FIXED"|"$DOWN_PREVIOUS") ;; *) fail '下载测速程序含未知修改';; esac
if [ "$ACTION" = status ]; then echo "upload=$U download=$D"; exit 0; fi
for name in upload_speedtest download_speedtest; do
    pidof "$name" >/dev/null 2>&1 && fail '请等待当前测速结束后安装或恢复'
done
mkdir "$LOCK" 2>/dev/null || fail '安装锁已存在'
NEW_UP=; NEW_DOWN=; WORK=; COMMITTING=0
cleanup() {
    rc=$?; trap - EXIT HUP INT TERM
    if [ "$COMMITTING" = 1 ]; then
        for name in up down; do
            case "$name" in up) target=$UP; stage=$NEW_UP; stock=$UP_STOCK; fixed=$UP_FIXED; previous=$UP_PREVIOUS;; down) target=$DOWN; stage=$NEW_DOWN; stock=$DOWN_STOCK; fixed=$DOWN_FIXED; previous=$DOWN_PREVIOUS;; esac
            current=$(hash "$target")
            if regular "$target" && { [ "$current" = "$stock" ] || [ "$current" = "$fixed" ] || [ "$current" = "$previous" ]; }; then
                cp -p "$WORK/$name.before" "$stage" && mv -f "$stage" "$target" || rc=1
            fi
        done
    fi
    [ -z "$NEW_UP" ] || rm -f "$NEW_UP"
    [ -z "$NEW_DOWN" ] || rm -f "$NEW_DOWN"
    rmdir "$LOCK"; exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
umask 077
[ ! -L "$BASE" ] || fail '备份目录为符号链接'
mkdir -p "$BASE"; chmod 0700 "$BASE"
for name in up down; do
    case "$name" in up) target=$UP; expected=$UP_STOCK;; down) target=$DOWN; expected=$DOWN_STOCK;; esac
    if [ -e "$BASE/$name.original" ]; then
        regular "$BASE/$name.original" && [ "$(hash "$BASE/$name.original")" = "$expected" ] || fail '原始备份摘要不符'
    else
        [ "$ACTION" = apply ] && [ "$(hash "$target")" = "$expected" ] || fail '缺少原厂备份'
        cp -p "$target" "$BASE/$name.original"
    fi
done
WORK=$(mktemp -d "$BASE/operation-XXXXXX")
cp -p "$UP" "$WORK/up.before"; cp -p "$DOWN" "$WORK/down.before"
NEW_UP=$(mktemp "${UP}.sampling.XXXXXX"); NEW_DOWN=$(mktemp "${DOWN}.sampling.XXXXXX")
cp -p "$BASE/up.original" "$NEW_UP"; cp -p "$BASE/down.original" "$NEW_DOWN"
if [ "$ACTION" = apply ]; then
lua - "$NEW_UP" "$NEW_DOWN" <<'LUA'
for index=1,2 do
    local path=arg[index]
    local f=assert(io.open(path,'rb')); local s=f:read('*a'); f:close()
    local function replace(old,new)
        local a,b=assert(s:find(old,1,true))
        assert(not s:find(old,b+1,true),'Duplicate anchor')
        s=s:sub(1,a-1)..new..s:sub(b+1)
    end
    -- ab's repeated socket errors otherwise fill nginx's FastCGI header buffer.
    -- Keep result stdout intact; shell redirection also applies to forked workers.
    replace("['ab'] = \"/usr/bin/ab\"", "['ab'] = \"/usr/bin/ab 2>/dev/null\"")
    replace('\tposix.sleep(1)', '\trepeat posix.sleep(1) until get_uptime() - rt.uptime >= 1')
    replace('local delta_time = rt.uptime - rt_last.uptime',
        'local delta_time = rt.uptime - rt_last.uptime\n\tif delta_time <= 0 then return end')
    local direction=index==1 and 'tx' or 'rx'
    local counter=index==1 and 't_bytes' or 'r_bytes'
    local a=assert(s:find('function '..direction..'_avg_interval_speed(dotdata)',1,true))
    local b=assert(s:find('function if_net_burst(dotdata)',a,true))
    local body=[=[function DIRECTION_avg_interval_speed(dotdata)
    local rates, dropped = {}, 0
    for i=1,#dotdata-cfg.interval do
        local first,last=dotdata[i],dotdata[i+cfg.interval]
        local dt=last.uptime-first.uptime
        local delta=last.COUNTER-first.COUNTER
        if dt > 0 and delta >= 0 then
            local rate=delta/dt/1024
            if rate==rate and rate<math.huge then
                rates[#rates+1]=rate
            else dropped=dropped+1 end
        else dropped=dropped+1 end
    end
    logger(3, 'speedtest_sampling DIRECTION valid='..#rates..' dropped='..dropped)
    if #rates < 3 then return 0 end
    table.sort(rates)
    if #rates >= 5 then table.remove(rates); table.remove(rates,1) end
    local total=0
    for _,rate in ipairs(rates) do total=total+rate end
    return total/#rates
end

]=]
    body=body:gsub('DIRECTION',direction):gsub('COUNTER',counter)
    s=s:sub(1,a-1)..body..s:sub(b)
    f=assert(io.open(path,'wb')); assert(f:write(s)); assert(f:close())
end
LUA
    [ "$(hash "$NEW_UP")" = "$UP_FIXED" ] && [ "$(hash "$NEW_DOWN")" = "$DOWN_FIXED" ] || fail '补丁摘要不符'
fi
luac -p "$NEW_UP"; luac -p "$NEW_DOWN"
cmp -s "$UP" "$WORK/up.before" && cmp -s "$DOWN" "$WORK/down.before" || fail '程序在安装期间变化'
COMMITTING=1
mv -f "$NEW_UP" "$UP"; mv -f "$NEW_DOWN" "$DOWN"
COMMITTING=0
echo "完成 $ACTION；原厂备份：$BASE；未启动测速、未修改 QoS 或重启服务。"
