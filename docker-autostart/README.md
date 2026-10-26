# Docker 开机自启修复

`install-router-docker-autostart.sh` 修复 AX9000 原厂 `mi_docker` 在部分重启或磁盘挂载时序下不能自动启动的问题。脚本使用 procd 托管，等待原 Docker 磁盘挂载，并保留官方安装、卸载入口。

目标固件：**小米 AX9000（RA70）原厂稳定版 1.0.140**。其他版本未验证；实际执行仍须满足原厂启动结构和 Docker 路径检查。版本核对来源见[仓库固件说明](../README.md#针对的原厂固件)。

## 适用条件

- 路由器已有官方 Docker，程序位于 `/mnt/docker_disk/mi_docker/docker-binaries/`。
- 原 USB 磁盘及 `/mnt/docker_disk/mi_docker/lib/docker/` 数据仍存在。
- 通过 root SSH 执行。此脚本不下载 Docker、不格式化磁盘，也不恢复已经丢失的数据。

## 使用

上传本目录的脚本到路由器后执行：

```sh
# 安装配置但不立即启动或重启 Docker
sh install-router-docker-autostart.sh --no-start

# Docker 未运行时，安装并启动
sh install-router-docker-autostart.sh

# Docker 正在运行时，显式允许短暂中断并重新启动
sh install-router-docker-autostart.sh --restart
```

默认命令发现 Docker 已运行会停止操作，要求使用 `--restart` 明确允许中断。重启时记录并尝试恢复原先运行的容器。

出厂恢复后准备接回仍有原数据的 USB 盘时，应先拔下原盘，运行下面的准备命令，再接回：

```sh
sh install-router-docker-autostart.sh --prepare
```

该模式先设置官方 Docker 安装状态，避免热插拔脚本把原数据目录当作“未安装”内容处理；它不适用于空白磁盘。

## 配置、备份和检查

持久文件与首次原配置备份位于 `/data/router-docker-autostart/`。脚本设置 `mi_docker.settings.docker_install=1`、`docker_enable=1` 并启用原 `mi_docker` 服务。每次最多等待磁盘 300 秒；连续失败最多尝试 3 次，间隔 10 秒。

```sh
/etc/init.d/mi_docker status
/mnt/docker_disk/mi_docker/docker-binaries/docker info
cat /tmp/mi-docker-startup.log
tail -n 80 /tmp/mi-docker-daemon.log
```

日志在重启后清空。脚本没有一键卸载选项；手动恢复前，应核对 `/data/router-docker-autostart/mi_docker.original` 与 `mi_docker.uci.original`，确认恢复不会覆盖安装后的其他配置。

## 与代理脚本配合

安装后可使用 `/data/router-docker-autostart/proxy.sh` 管理代理。仓库的 [Docker 代理脚本](../docker-proxy/README.md)会自动转交该托管入口，统一由 procd 重启 Docker。

[返回仓库说明](../README.md)
