#!/bin/sh
set -eu
. /data/router-docker-1.0.168/runtime/common.sh
find_disk || die '指定 Docker 磁盘未就绪。'
check_engine || die 'Docker 程序摘要不匹配。'
docker_cli "$@"
