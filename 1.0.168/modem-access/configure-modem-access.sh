#!/bin/sh
# 小米 AX9000 原厂 1.0.168，PPPoE 拨号，桥接光猫管理页。
# 默认配置并验证。只检查时运行 sh configure-modem-access.sh status
set -eu
umask 077

pc=10.31.0.2
modem=192.168.1.1
local_ip=192.168.1.2
config_dir=/etc/config
firewall_service=/etc/init.d/firewall
mode=${1:-apply}
say() { printf '%s\n' "$*"; }
die() { say "$*" >&2; exit 1; }
usage() { say '用法为 sh configure-modem-access.sh [apply|status]，省略参数即配置。'; }
[ "$#" -le 1 ] || { usage; exit 1; }
case "$mode" in apply|status) ;; -h|--help) usage; exit 0 ;; *) usage; exit 1 ;; esac
[ "$(id -u)" = 0 ] || die '请在路由器上以 root 运行。'
for tool in uci ubus ip iptables curl cmp mktemp flock; do
    command -v "$tool" >/dev/null 2>&1 || die "缺少命令 $tool"
done
[ -x "$firewall_service" ] || die '找不到原厂防火墙服务。'
if [ "$mode" = apply ]; then
    exec 9>/var/lock/modem-mgmt-pc.lock
    flock -n 9 || die '已有一份脚本正在配置光猫访问，请稍后重试。'
fi

[ "$(uci -q get network.wan.proto)" = pppoe ] || die '当前 WAN 不是 PPPoE，请核对光猫桥接和拨号方式。'
wan=$(uci -q get network.wan.ifname) || die '无法读取 PPPoE 的底层 WAN 设备。'
case "$wan" in ''|*[!a-zA-Z0-9_.-]*|br-*|ppp*|lo) die "不支持的 WAN 设备 $wan" ;; esac
ip link show dev "$wan" >/dev/null || die "找不到 WAN 设备 $wan"
case " $(ip -4 route get "$pc") " in *' dev br-lan '*) ;; *) die "$pc 当前不经 br-lan，请核对电脑的 LAN 网段。" ;; esac
for pkg in network firewall; do
    pending=$(uci changes "$pkg") || die "无法读取 $pkg 配置。"
    [ -z "$pending" ] || die "$pkg 有尚未提交的 UCI 更改，请先处理后重试。"
done

# 已有相同名字的其他防火墙区域时，避免生成指向错误区域的规则。
for section in $(uci -q show firewall | sed -n "s/^\(firewall\.[^.]*\)\.name='modem'$/\1/p"); do
    [ "$section" = firewall.modem_mgmt ] || [ "$(uci -q get "$section")" != zone ] || die "防火墙区域 modem 已由 $section 使用。"
done
# 防止接管已在其他接口使用的光猫管理子网。
conflict=$(ip -4 route show scope link | awk -v wan="$wan" '
    $1 == "192.168.1.0/24" {for (i=1; i<NF; i++) if ($i=="dev" && $(i+1)!=wan) print $(i+1)}')
[ -z "$conflict" ] || die "192.168.1.0/24 已用于其他接口 $conflict"

# 输出所需的 UCI 差异。只调整这三个具名配置段内的选项，保留规则顺序。
plan_section() {
    section=$1 kind=$2
    shift 2
    current=$(uci -q get "$section" || :)
    case "$current" in "$kind") ;; '') printf 'set %s=%s\n' "$section" "$kind" ;; *) die "$section 已用作 $current" ;; esac
    for pair do
        key=$section.${pair%%=*}
        value=${pair#*=}
        current=$(uci -q get "$key" || :)
        [ "$value" != "$current" ] || continue
        case "$key" in
            *.network|*.masq_src|*.masq_dest|*.dest_port)
                [ -z "$current" ] || printf 'delete %s\n' "$key"
                for item in $value; do printf 'add_list %s=%s\n' "$key" "$item"; done ;;
            *) if [ -n "$value" ]; then printf "set %s='%s'\n" "$key" "$value"; else printf 'delete %s\n' "$key"; fi ;;
        esac
    done
}
network_plan=$(plan_section network.modem_mgmt interface proto=static ifname="$wan" ipaddr="$local_ip" \
    netmask=255.255.255.0 defaultroute=0 gateway= auto= disabled=)
zone_plan=$(plan_section firewall.modem_mgmt zone name=modem family=ipv4 network=modem_mgmt \
    input=REJECT output=ACCEPT forward=REJECT masq=1 masq_src="$pc/32" masq_dest="$modem/32" custom_chains=0 enabled=)
rule_plan=$(plan_section firewall.modem_mgmt_pc rule 'name=PC to modem web' family=ipv4 src=lan \
    src_ip="$pc/32" dest=modem dest_ip="$modem/32" proto=tcp 'dest_port=80 443' target=ACCEPT enabled=)
packages=
[ -z "$network_plan" ] || packages=network
[ -z "$zone_plan$rule_plan" ] || packages="${packages:+$packages }firewall"

route_ready() {
    route=$(ip -4 route get "$modem") || return 1
    case " $route " in *" dev $wan "*) ;; *) return 1 ;; esac
    case " $route " in *" src $local_ip "*) return 0 ;; *) return 1 ;; esac
}
firewall_ready() {
    for port in 80 443; do
        iptables -C zone_lan_forward -s "$pc/32" -d "$modem/32" -p tcp --dport "$port" \
            -m comment --comment '!fw3: PC to modem web' -j zone_modem_dest_ACCEPT || return 1
    done
    iptables -C zone_modem_dest_ACCEPT -o "$wan" -m comment --comment '!fw3' -j ACCEPT &&
    iptables -t nat -C POSTROUTING -o "$wan" -m comment --comment '!fw3' -j zone_modem_postrouting &&
    iptables -t nat -C zone_modem_postrouting -s "$pc/32" -d "$modem/32" -m comment --comment '!fw3' -j MASQUERADE
}

work=''
backup=''
published=''
swap=''
replace_config() {
    # 保留当前文件的权限和属主，同目录改名使单文件替换具有原子性。
    swap=$(mktemp "$config_dir/.modem-mgmt.XXXXXX") || return 1
    if ! cp -p "$config_dir/$1" "$swap" || ! cat "$2" >"$swap" || ! mv -f "$swap" "$config_dir/$1"; then
        rm -f "$swap"
        swap=
        return 1
    fi
    swap=
}
finish() {
    rc=$?
    trap - EXIT HUP INT TERM
    set +e
    restored=
    for pkg in $published; do
        if cmp -s "$config_dir/$pkg" "$work/$pkg"; then
            if replace_config "$pkg" "$backup/$pkg"; then restored="$restored $pkg"; else say "恢复 $pkg 失败，备份在 $backup" >&2; fi
        elif ! cmp -s "$config_dir/$pkg" "$backup/$pkg"; then
            say "$pkg 已被其他进程更改，请核对备份 $backup" >&2
        fi
    done
    case "$restored " in *' network '*) ubus call network reload >/dev/null || say '恢复后重载网络配置失败。' >&2 ;; esac
    case "$restored " in *' firewall '*|*' network '*) "$firewall_service" reload 9>&- || say '恢复后重载防火墙失败。' >&2 ;; esac
    [ -z "$restored" ] || say "已恢复本次替换的配置$restored" >&2
    [ -z "$swap" ] || rm -f "$swap"
    [ -z "$work" ] || rm -rf "$work"
    exit "$rc"
}
trap finish EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if [ "$mode" = status ]; then
    [ -z "$packages" ] || die "持久配置有待更新的项目：$packages"
    route_ready || die "到 $modem 的实际路由未通过 $wan 使用 $local_ip"
    firewall_ready 2>/dev/null || die '转发或 NAT 规则尚未生效。'
else
    if [ -n "$packages" ]; then
        work=$(mktemp -d /tmp/modem-mgmt.XXXXXX)
        mkdir "$work/delta"
        backup=$(mktemp -d /data/modem-mgmt-backup.XXXXXX)
        for pkg in $packages; do
            cp -p "$config_dir/$pkg" "$backup/$pkg"
            cp -p "$backup/$pkg" "$work/$pkg"
        done
        say "本次变更前的配置已备份到 $backup"
        printf '%s\n' "$network_plan" "$zone_plan" "$rule_plan" | uci -c "$work" -P "$work/delta" batch
        for pkg in $packages; do
            # 此版 UCI 的 -P 只暂存。导出结果并独立复读，保留匿名段和原顺序。
            uci -N -c "$work" -P "$work/delta" export "$pkg" >"$work/exported"
            sed '1{/^package /d;}' "$work/exported" >"$work/$pkg"
            uci -N -c "$work" export "$pkg" >"$work/reparsed"
            cmp -s "$work/exported" "$work/reparsed" || die "$pkg 候选配置复读校验失败。"
        done
        for pkg in $packages; do
            pending=$(uci changes "$pkg")
            if [ -n "$pending" ] || ! cmp -s "$config_dir/$pkg" "$backup/$pkg"; then
                die "$pkg 在配置期间发生变化，请重试。"
            fi
            published="$pkg $published"
            replace_config "$pkg" "$work/$pkg" || die "无法写入 $pkg 配置。"
        done
    fi
    if [ -n "$network_plan" ] || ! route_ready; then
        ubus call network reload >/dev/null || die 'netifd 重载配置失败。'
        tries=0
        until route_ready; do
            [ "$tries" -lt 8 ] || die "等待 $wan 的光猫管理地址生效超时。"
            ubus call network.interface.modem_mgmt up >/dev/null 2>&1 || :
            sleep 1
            tries=$((tries + 1))
        done
    fi
    if [ -n "$zone_plan$rule_plan" ] || ! firewall_ready 2>/dev/null; then
        "$firewall_service" reload 9>&- || die '防火墙重载失败。'
    fi
    route_ready || die '光猫的实际路由校验失败。'
    firewall_ready 2>/dev/null || die '转发或 NAT 校验失败。'
    published=
fi

say "配置已生效。已放行 $pc 经 $wan 到 $modem 的 TCP 80、443。"
http=$(curl --noproxy '*' --interface "$local_ip" --connect-timeout 3 --max-time 6 \
    -s -o /dev/null -w '%{http_code}' "http://$modem/") || http=000
case "$http" in
    2??|3??|401|403) say "光猫管理页返回 HTTP $http，请在电脑上直连 http://$modem/" ;;
    *) say "路由与防火墙校验通过，路由器探测光猫管理页得到 HTTP $http，请检查光猫的管理地址和服务。" >&2; exit 2 ;;
esac
say "电脑使用 Clash Verge 时，将 IP-CIDR,$modem/32,DIRECT,no-resolve 放在 MATCH 之前。"
