#!/bin/sh
# Finite startup observer. It can signal only the exact daemon passed by launch.sh.
set -eu
. /data/router-docker-1.0.168/runtime/common.sh
[ "$#" = 5 ] || die '启动检查参数不完整。'
daemon_pid=$1; daemon_start=$2; daemon_exe=$3; ENGINE=$(dirname "$4"); limit=$5
for value in "$daemon_pid" "$daemon_start" "$limit"; do
    case "$value" in *[!0-9]*|'') die '启动检查参数错误。' ;; esac
done
[ "$daemon_pid" -gt 1 ] && [ "$daemon_start" -gt 0 ] && [ "$limit" -ge 1 ] && [ "$limit" -le 240 ] || die '启动检查参数越界。'
note() { logger -t router-docker168 "$*" 2>/dev/null || printf '%s\n' "$*"; }
trap 'exit 0' TERM INT HUP
# The observer may be scheduled immediately before the parent executes dockerd.
n=0
until same_process "$daemon_pid" "$daemon_start" "$daemon_exe"; do
    [ "$(process_start "$daemon_pid" 2>/dev/null)" = "$daemon_start" ] || exit 0
    [ "$n" -lt 10 ] || { note '启动检查未匹配到预期程序，未发送信号。'; exit 0; }
    sleep 1; n=$((n+1))
done
end=$(($(uptime_seconds)+limit))
while same_process "$daemon_pid" "$daemon_start" "$daemon_exe"; do
    if api_ready; then
        note "Docker API 已就绪，PID=$daemon_pid，由 procd 托管。"
        exit 0
    fi
    [ "$(uptime_seconds)" -lt "$end" ] || break
    sleep 2
done
same_process "$daemon_pid" "$daemon_start" "$daemon_exe" || exit 0
note "Docker API 在 ${limit} 秒内未就绪；向本次 PID=$daemon_pid 发送 TERM，进程退出后由 procd 有限重试。"
same_process "$daemon_pid" "$daemon_start" "$daemon_exe" && kill -TERM "$daemon_pid"
exit 1
