# 1.0.168 Docker 与原厂页面恢复

适用于 **AX9000 / RA70 国行原厂稳定版 1.0.168**，在刷入原版固件并恢复 root SSH 后执行。通过可写文件系统补齐服务、管理 API 和“高级设置 → DOCKER”，不用制作或刷入修改版 ROM。

**当前为待真机验收版本**：已固定小米 Docker 程序和页面来源，并做离线安装/回退、原厂 Lua 及页面测试；尚未在 1.0.168 真机运行容器。安装默认只准备程序和页面，使用 `--start` 或网页开关才会启动 Docker。不要把离线验证理解为实机兼容保证。

## 准备与安装

**1.0.168 原厂本身支持 ext4**：实际内核配置为 `CONFIG_EXT4_FS=y`、`CONFIG_JBD2=y`、`CONFIG_FS_MBCACHE=y`；原厂 `40-mount` 热插拔脚本保留识别文件系统并挂载到 `/extdisks/设备名` 的流程，默认 `anon_mount=1`。缺失的是 Docker 服务与页面，不是 ext4 驱动。此工具复用原厂挂载，只接受已成功挂载的 ext4 分区，不自动格式化，也不把“尚未挂载”当作“不支持 ext4”。

1. 刷入原版 1.0.168，恢复 root SSH。SSH 工具的前提见[共用说明](../../ssh-modern/README.md)。脚本本身不能恢复 SSH。
2. 连接已格式化为 ext4 的 USB 盘，用 `cat /proc/mounts` 确定实际挂载点，例如 `/extdisks/sda1`。必须为可读写、允许执行的真实挂载点；也支持已有 `/mnt/docker_disk`。脚本不分区、不格式化、不挑选第一块盘，后续按 UUID 查找同一分区。新装至少需 256 MiB 可用空间，镜像/容器另需空间。
3. 将 [1.0.168 离线安装包](../../dist/1.0.168/router-docker-1.0.168-v1.0.0.tar.gz) 上传并解包到 USB 盘；包内含已核对的原厂 Docker 下载包，不占用路由器内置存储保存大包。

```sh
cd /extdisks/sda1
tar -xzf router-docker-1.0.168-v1.0.0.tar.gz
cd router-docker-1.0.168

# 核对状态，不安装
sh install-router-docker.sh status

# 将示例路径换成已确认的真实挂载点；准备程序与页面，不立即启动
sh install-router-docker.sh apply --disk /extdisks/sda1

# 或明确要求安装后启动
sh install-router-docker.sh apply --disk /extdisks/sda1 --start
```

使用源码目录时必须保留完整 `payload/` 和 `SHA256SUMS`。如果未提供同目录原厂包，脚本从小米 CDN 下载并强制校验 SHA-256；也可使用 `--archive /外接盘/docker-19.03.15-ce.tgz` 指定离线包。HTTPS 校验保持开启，不使用 `curl -k`；证书/时间异常时使用离线包。

已有旧盘时，保留原 `mi_docker/` 目录。八个程序与原厂摘要一致则复用，数据仍位于该盘 `mi_docker/lib/docker/`。程序版本不同或缺损时拒绝覆盖；脚本不会自动升级/降级引擎或删除数据。刷固件前应另外保存重要容器数据。

## 原厂后台页面

重新登录或刷新管理后台，在“高级设置 → DOCKER”操作。原厂页面样式来自 1.0.140，适配后使用独立的 `api/routerdocker168/`，沿用后台管理员会话和 `stok` 鉴权，写操作仅接受 POST。原厂 1.0.168 的页面控制器、网络 API、功能开关、DHCP/MAC 配置保持原文件。

- “运行 Docker”开关：由 procd 启停，启动时等待指定磁盘最多 300 秒；一小时内连续失败最多尝试三次，间隔 10 秒。
- “安装 Docker”：复用已核对的程序，或重新下载并核对原厂包。
- “停用并保留数据”：关闭服务和安装标记；程序、镜像、容器、卷不删除。
- “安装第三方管理”：可选，需先通过 SSH 配置已单独验证兼容的 **ARM64 Portainer CE 镜像摘要**。不默认安装 `latest`，不使用原厂 `admin/admin`。创建的 `router-portainer168` 仅发布 LAN IPv4 的 9001 端口，首次访问创建管理员账户；已有同名容器拒绝重建。

```sh
# 先独立确认所选 Portainer 与原厂 Engine/API 1.40 的兼容性。
# 将占位符换成已核对的 64 位 SHA-256 摘要，不能原样执行。
uci set mi_docker.settings.portainer_image='portainer/portainer-ce@sha256:<已核对的ARM64镜像摘要>'
uci commit mi_docker
```

第三方管理页为可选组件，不影响 Docker CLI 或原厂开关。LAN 地址变化后需人工核对管理容器端口绑定。Docker 数据有对应容器时，按自身 restart policy 恢复；不会强行启动所有历史容器，也不删除或重建已有 Portainer。

## 状态、日志和回退

```sh
sh install-router-docker.sh status
sh install-router-docker.sh start
sh install-router-docker.sh stop
docker info
docker ps -a
logread -e dockerd
cat /tmp/router-docker168-job.log
cat /tmp/router-docker168.result

# 停止 Docker 并恢复部署前页面与配置，保留 USB 数据和备份
sh install-router-docker.sh restore
```

运行文件、原厂备份与安装记录在 `/data/router-docker-1.0.168/`，日志和操作结果在 `/tmp/`。回退前核对已部署文件和备份摘要，安装后文件被其他工具改变时拒绝覆盖。原厂已有的 `S99mi_docker` 残留链接保留，新增停止链接回退时移除。额外挂载的 cgroup 留到下次重启，避免影响其他进程；脚本不改写稳定版 `cgroup_init` 及其资源分组，不修改 `/etc/profile`，Docker API 仅监听本地 Unix socket。

OTA、出厂恢复或再次刷机后，需要重新恢复 SSH 并重新执行部署；不宣称这些操作后自动保留。回退或停用不删除外接盘数据。

## 固定组件与验证

此版使用小米包 `docker-19.03.15-ce.tgz`：CLI 19.03.15、厂商构建 dockerd `dev` / API 1.40、containerd 1.3.9、runc 1.0.0-rc10。它是恢复原厂功能的兼容基线，**不是固件支持的最高 Docker 版本**。Linux 4.4.60 缺少 seccomp 的既有限制仍然存在。组件摘要、来源及与上游版本的区别见 [SOURCES.md](SOURCES.md) 和[固件分析](../docs/ax9000-1.0.168-docker-feasibility.md)。

离线验证不启动 WSL Docker，也不接触在线路由器；覆盖型号/版本/文件保护、指定磁盘、原厂摘要、重复部署、故障回退、卸载保留数据、LuCI API 鉴权注册与参数保护。真机仍需验证 `docker info`、本地测试容器、bridge DNS/出网/端口映射、bind/volume 持久化、资源限制和重启后的同 UUID 磁盘恢复。原厂页面浏览器端到端验收同样待完成。

重新打包（在仓库根目录执行，Python 3.10+）：

```sh
python3 1.0.168/docker/build-package.py --engine-archive .tools/docker168-downloads/docker-19.03.15-ce.tgz
```

[返回 1.0.168](../README.md)
