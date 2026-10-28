#!/bin/sh
# AX9000 / RA70 1.0.168: expose the existing manual speed-test UI.
set -eu

INDEX=/usr/lib/lua/luci/view/web/index.htm
QOS=/usr/lib/lua/luci/view/web/setting/qos.htm
SHARED=/usr/lib/lua/luci/view/web/inc/speedtest.js.htm
VERSION_FILE=/usr/share/xiaoqiang/xiaoqiang_version
BASE=/data/router-speedtest-web-1.0.168
LOCK=/tmp/router-speedtest-web-1.0.168.lock
INDEX_STOCK=f4c3a793015aa376bedbb6f14ec10144
INDEX_FIXED=a022d3fff445191712aa0e0520d0f0c0
QOS_STOCK=17a1ea8f785d2b0ed08843afc2b02602
QOS_FIXED=b6ae09f98bd8d134148db8a95cbd5011
QOS_PREVIOUS=35125f038b9dacdf2b3ea970c572f9cc
SHARED_STOCK=a90c46c1d0643fbb76c47d02a2454e7b
SHARED_FIXED=74b18f689af22889be97e362e7c5f216
SHARED_PREVIOUS=0436a2a32cd12ebafe93ebedefe142d5
SHARED_LEGACY=d51298f4c028c2a8e4f76932b25f391f
UPGRADE=0
WORK=
NEW_INDEX=
NEW_QOS=
NEW_SHARED=
LOCKED=0
COMMITTING=0

say() { printf '%s\n' "$*"; }
die() { say "错误：$*" >&2; exit 1; }
hash() { md5sum "$1" | awk '{print $1}'; }
regular() { [ -f "$1" ] && [ ! -L "$1" ]; }
state() {
    case "$(hash "$1")" in
        "$2") say original ;;
        "$3") say enabled ;;
        "${4:-no_previous}") say previous ;;
        "${5:-no_legacy}") say previous ;;
        *) say unknown ;;
    esac
}
cleanup() {
    code=$?
    trap - EXIT HUP INT TERM
    if [ "$COMMITTING" = 1 ]; then
        # Keep the pre-operation copies on error, and restore only our known bytes.
        for entry in index qos shared; do
            case "$entry" in
                index) target=$INDEX; staged=$NEW_INDEX; stock=$INDEX_STOCK; fixed=$INDEX_FIXED; previous=no_previous ;;
                qos) target=$QOS; staged=$NEW_QOS; stock=$QOS_STOCK; fixed=$QOS_FIXED; previous=$QOS_PREVIOUS ;;
                shared) target=$SHARED; staged=$NEW_SHARED; stock=$SHARED_STOCK; fixed=$SHARED_FIXED; previous=$SHARED_PREVIOUS ;;
            esac
            if regular "$target" && [ "$(state "$target" "$stock" "$fixed" "$previous" "$SHARED_LEGACY")" != unknown ]; then
                if cp -p "$WORK/$entry.before" "$staged" && mv -f "$staged" "$target"; then
                    say "已回退：$target" >&2
                else
                    say "自动回退失败，请保留并核对：$WORK" >&2
                    code=1
                fi
            else
                say "文件出现其他修改，未覆盖，请核对：$target；备份：$WORK" >&2
                code=1
            fi
        done
    fi
    [ -z "$NEW_INDEX" ] || rm -f "$NEW_INDEX"
    [ -z "$NEW_QOS" ] || rm -f "$NEW_QOS"
    [ -z "$NEW_SHARED" ] || rm -f "$NEW_SHARED"
    if [ "$LOCKED" = 1 ]; then rmdir "$LOCK" 2>/dev/null || true; fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

ACTION=${1:-apply}
case "$ACTION" in
    -h|--help)
        say "用法：sh $0 [apply|status|restore backup-XXXXXX]"
        say '恢复状态页“重新测速”和 QoS 页“开始测速”，不立即测速。'
        exit 0 ;;
    apply|status) [ "$#" -le 1 ] || die '参数过多。' ;;
    restore) [ "$#" -eq 2 ] || die 'restore 需要 apply 输出的备份编号。' ;;
    *) die '只支持 apply、status、restore。' ;;
esac
[ "$(id -u)" = 0 ] || die '请以 root 运行。'
for tool in awk md5sum cmp cp mv mktemp lua; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令：$tool"
done
regular "$VERSION_FILE" || die '无法读取固件版本。'
ROM=$(awk '$1=="option" && $2=="ROM" {gsub(/[\047\042]/,"",$3); print $3}' "$VERSION_FILE")
MODEL=$(awk '$1=="option" && $2=="HARDWARE" {gsub(/[\047\042]/,"",$3); print $3}' "$VERSION_FILE")
[ "$ROM" = 1.0.168 ] && [ "$MODEL" = RA70 ] || die '仅支持 RA70 原厂稳定版 1.0.168。'
for target in "$INDEX" "$QOS" "$SHARED"; do
    regular "$target" || die "不支持缺失文件或符号链接：$target"
done
INDEX_STATE=$(state "$INDEX" "$INDEX_STOCK" "$INDEX_FIXED")
QOS_STATE=$(state "$QOS" "$QOS_STOCK" "$QOS_FIXED" "$QOS_PREVIOUS")
SHARED_STATE=$(state "$SHARED" "$SHARED_STOCK" "$SHARED_FIXED" "$SHARED_PREVIOUS" "$SHARED_LEGACY")
[ "$INDEX_STATE" != unknown ] && [ "$QOS_STATE" != unknown ] && [ "$SHARED_STATE" != unknown ] || die '页面或共享脚本存在未知修改，拒绝覆盖。'
if [ "$ACTION" = status ]; then
    say "状态页：$INDEX_STATE；QoS 页：$QOS_STATE；共享脚本：$SHARED_STATE"
    exit 0
fi
if [ "$ACTION" = apply ]; then
    if [ "$INDEX_STATE/$QOS_STATE/$SHARED_STATE" = enabled/enabled/enabled ]; then
        say '两个测速入口均已开启，无需重复安装。'
        exit 0
    fi
    case "$INDEX_STATE/$QOS_STATE/$SHARED_STATE" in
        original/original/original) ;;
        enabled/previous/previous|enabled/enabled/previous) UPGRADE=1 ;;
        *) die '页面或共享脚本状态不一致，请先用原备份 restore 恢复。' ;;
    esac
fi

mkdir "$LOCK" 2>/dev/null || die "已有操作或残留锁：$LOCK"
LOCKED=1
umask 077
[ ! -L "$BASE" ] || die '备份根目录不能是符号链接。'
mkdir -p "$BASE"
chmod 0700 "$BASE"
if [ "$ACTION" = restore ]; then
    case "$2" in backup-*) ;; *) die '备份编号格式错误。' ;; esac
    case "$2" in *[!a-zA-Z0-9-]*) die '备份编号不能包含路径或特殊字符。' ;; esac
    BACKUP=$BASE/$2
    [ -d "$BACKUP" ] && [ ! -L "$BACKUP" ] || die '备份目录无效。'
    for entry in index qos shared; do
        regular "$BACKUP/$entry.original" || die '原始备份缺失或为符号链接。'
    done
    [ "$(hash "$BACKUP/index.original")" = "$INDEX_STOCK" ] || die '状态页原始备份摘要不符。'
    [ "$(hash "$BACKUP/qos.original")" = "$QOS_STOCK" ] || die 'QoS 原始备份摘要不符。'
    [ "$(hash "$BACKUP/shared.original")" = "$SHARED_STOCK" ] || die '共享脚本原始备份摘要不符。'
    if [ "$INDEX_STATE/$QOS_STATE/$SHARED_STATE" = original/original/original ]; then
        say '两个页面均为原厂内容，无需恢复。'
        exit 0
    fi
elif [ "$UPGRADE" = 1 ]; then
    BACKUP=
    for candidate in "$BASE"/backup-*; do
        [ -d "$candidate" ] && [ ! -L "$candidate" ] || continue
        regular "$candidate/index.original" && regular "$candidate/qos.original" && regular "$candidate/shared.original" || continue
        [ "$(hash "$candidate/index.original")" = "$INDEX_STOCK" ] || continue
        [ "$(hash "$candidate/qos.original")" = "$QOS_STOCK" ] || continue
        [ "$(hash "$candidate/shared.original")" = "$SHARED_STOCK" ] || continue
        BACKUP=$candidate
        break
    done
    [ -n "$BACKUP" ] || die '升级需要旧版安装时保留的完整原厂备份。'
else
    BACKUP=$(mktemp -d "$BASE/backup-XXXXXX")
    cp -p "$INDEX" "$BACKUP/index.original"
    cp -p "$QOS" "$BACKUP/qos.original"
    cp -p "$SHARED" "$BACKUP/shared.original"
fi
WORK=$(mktemp -d "$BASE/operation-XXXXXX")
cp -p "$INDEX" "$WORK/index.before"
cp -p "$QOS" "$WORK/qos.before"
cp -p "$SHARED" "$WORK/shared.before"
NEW_INDEX=$(mktemp "${INDEX}.speedtest.XXXXXX")
NEW_QOS=$(mktemp "${QOS}.speedtest.XXXXXX")
NEW_SHARED=$(mktemp "${SHARED}.speedtest.XXXXXX")
cp -p "$INDEX" "$NEW_INDEX"
cp -p "$QOS" "$NEW_QOS"
cp -p "$SHARED" "$NEW_SHARED"
if [ "$ACTION" = apply ]; then
    lua - "$BACKUP" "$NEW_INDEX" "$NEW_QOS" "$NEW_SHARED" <<'PATCH'
local function read(name)
    local f=assert(io.open(arg[1]..'/'..name..'.original','rb'))
    local s=f:read('*a'); f:close(); return s
end
local function replace(s,old,new)
    local first,last=s:find(old,1,true)
    assert(first,'Missing patch anchor')
    assert(not s:find(old,last+1,true),'Duplicate patch anchor')
    return s:sub(1,first-1)..new..s:sub(last+1)
end
local index=read('index')
local button=[[<a id="btnSpeedTest" href="#" class="btn btn-primary btn-m"><span id="retestSpeed"><%:重新测速%></span></a>]]
index=replace(index,'<!-- '..button..' -->',button)
local qos=read('qos')
local limit=[[<a href="#" id="btnBandset" class="btn btn-dft btn-m" data-upband="" data-downband=""><span><%:限速设置%></span></a>]]
local test=[[<a href="#" class="btn btn-primary btn-m btnBandTest"><span><%:开始测速%></span></a>]]
qos=replace(qos,limit,test..'\n                                    '..limit)
qos=replace(qos,"                    $('.result-tip').show();", "                    $('.result-tip').show();\n                    $.pub('speed:history');")
local shared=read('shared')
shared=replace(shared,'            data: { upload: upload, download: download },','            data: { upload: upload, download: download, manual: 1 },')
local resultLimit=[[<a href="#" id="btnBandset" class="btn btn-dft btn-m" data-upband="{$upband*8}" data-downband="{$downband*8}"><span><%:限速设置%></span></a>]]
shared=replace(shared,resultLimit,test..'\n         '..resultLimit)
local helper=[=[    var renderQosSpeed = function(downband, upband){
        downband = Number(downband);
        upband = Number(upband);
        if (!$('#speedresult').length || !isFinite(downband) || !isFinite(upband) || downband <= 0) {
            return;
        }
        $('#speedresult').html($('#tmplBandResult2').html().tmpl({
            downband: (downband/8).toFixed(2),
            upband: (upband/8).toFixed(2)
        }));
        $('.mod-bandwidth .nospeed').hide();
        $('.mod-bandwidth .hasspeed').show();
        $('.result-tip').hide();
    };
]=]
shared=replace(shared,'    var getDownloadSpeed = function(){',helper..'    var getDownloadSpeed = function(){')
local first=assert(shared:find('    var getDownloadSpeed = function(){',1,true))
local last=assert(shared:find("    $.sub( 'speed:test',",first,true))
shared=shared:sub(1,first-1)..[=[    var runningTest = null;
    var requestSpeedApi = function(route, data, stage){
        var dtd = $.Deferred();
        $.ajax({
            url: route, type: 'POST', data: data, dataType: 'json', timeout: 90000,
            success: function(rsp){
                if (rsp && rsp.code == 0) { dtd.resolve(rsp); }
                else { dtd.reject({stage:stage, code:rsp && rsp.code, msg:rsp && rsp.msg}); }
            },
            error: function(xhr, status){
                dtd.reject({stage:stage, http:xhr && xhr.status, status:status});
            }
        });
        return dtd.promise();
    };
    var speedErrorText = function(error){
        error = error || {};
        var stage = error.stage == 'save' ? '测速已完成，但保存限速失败' : '测速失败';
        if (error.http) { return stage + '（HTTP ' + error.http + '，后端未正常响应），请稍候重试。'; }
        if (error.status == 'timeout') { return stage + '（请求超时），请等待后台测速结束后再试。'; }
        if (error.msg) { return stage + '：' + error.msg + (error.code ? '（' + error.code + '）' : ''); }
        return stage + '（未取得有效带宽结果），未写入新的限速值。';
    };
    var speedTest = function(){
        if (runningTest) { return runningTest; }
        var dtd = $.Deferred();
        runningTest = dtd.promise();
        var result = runningTest;
        dtd.always(function(){ runningTest = null; });
        requestSpeedApi('<%=luci.dispatcher.build_url("api","misystem","bandwidth_test")%>', {new:1}, 'measure').done(function(rsp){
            var download = Number(rsp.bandwidth), upload = Number(rsp.bandwidth2);
            if (!isFinite(download) || !isFinite(upload) || download <= 0 || upload <= 0) {
                dtd.reject({stage:'measure', code:1588, msg:'上传或下载未取得有效结果，请重新测试'});
                return;
            }
            requestSpeedApi('<%=luci.dispatcher.build_url("api","misystem","set_band")%>', {upload:upload, download:download, manual:1}, 'save').done(function(){
                dtd.resolve(download, upload, rsp.download, rsp.upload);
            }).fail(function(error){
                dtd.reject(error);
            });
        }).fail(function(error){
            dtd.reject(error);
        });
        return result;
    };

]=]..shared:sub(last)
shared=shared:gsub('var showErr = function%(%)%{', 'var showErr = function(error){')
shared=replace(shared,"            dlg.content( $( '#tmplSpeedTestErr' ).html() );", "            var view = $('<div>').html($('#tmplSpeedTestErr').html());\n            view.find('p').first().text(speedErrorText(error));\n            dlg.content(view.html());")
shared=replace(shared,"            dlg.content( $( '#tmplBandTestErr' ).html() );", "            var view = $('<div>').html($('#tmplBandTestErr').html());\n            view.find('p').first().text(speedErrorText(error));\n            dlg.content(view.html());")
shared=shared:gsub('%.fail%(function%(%)%{\n%s+showErr%(%)%s*;', '.fail(function(error){\n                showErr(error);')
local oldResult=[=[            var result2 = tpl2.tmpl( {
                downband: downband,
                upband: upband
            } );
            dlg.content( result );
            $('#speedresult').html( result2 );]=]
shared=replace(shared,oldResult,[=[            dlg.content( result );
            renderQosSpeed(downband, upband);]=])
local attrs=[=[                $( '#btnBandset' ).attr('data-upband', bandwidth2.toFixed(2)).attr('data-downband', bandwidth.toFixed(2));]=]
shared=replace(shared,attrs,attrs..'\n                renderQosSpeed(bandwidth, bandwidth2);')
for i,s in ipairs({index,qos,shared}) do
    local f=assert(io.open(arg[i+1],'wb')); assert(f:write(s)); assert(f:close())
end
PATCH
    [ "$(hash "$NEW_INDEX")" = "$INDEX_FIXED" ] || die '状态页补丁摘要不符。'
    [ "$(hash "$NEW_QOS")" = "$QOS_FIXED" ] || die 'QoS 补丁摘要不符。'
    [ "$(hash "$NEW_SHARED")" = "$SHARED_FIXED" ] || die '共享脚本补丁摘要不符。'
else
    cp -p "$BACKUP/index.original" "$NEW_INDEX"
    cp -p "$BACKUP/qos.original" "$NEW_QOS"
    cp -p "$BACKUP/shared.original" "$NEW_SHARED"
fi
lua - "$NEW_INDEX" "$NEW_QOS" "$NEW_SHARED" <<'LUA'
local parser=assert(package.loadlib('/usr/lib/lua/luci/template/parser.so','luaopen_luci_template_parser'))()
for i=1,3 do
    local compiled,message=parser.parse(arg[i])
    assert(type(compiled)=='function',message)
end
LUA
cmp -s "$INDEX" "$WORK/index.before" && cmp -s "$QOS" "$WORK/qos.before" && cmp -s "$SHARED" "$WORK/shared.before" || die '页面在操作期间发生变化，未覆盖。'
COMMITTING=1
mv -f "$NEW_INDEX" "$INDEX"
mv -f "$NEW_QOS" "$QOS"
mv -f "$NEW_SHARED" "$SHARED"
COMMITTING=0
say "完成：$ACTION。未启动测速、未修改 QoS 配置、未重启服务。"
say "原始备份：$BACKUP"
say "恢复命令：sh $0 restore ${BACKUP##*/}"
say '请强制刷新路由状态页或 QoS 设置页后，手动点击测速。'
