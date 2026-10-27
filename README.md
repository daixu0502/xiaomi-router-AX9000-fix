# 小米 AX9000 原厂固件工具

## 仓库说明

本仓库提供 **小米路由器 AX9000 / RA70** 原厂固件的修复与部署工具，支持原厂开发版 **1.0.140** 和国行稳定版 **1.0.168**。固件专用脚本和文档分别放在版本目录；经组件核对可共用的 SSH 工具独立保存。

仓库地址：[daixu0502/xiaomi-router-AX9000-fix](https://github.com/daixu0502/xiaomi-router-AX9000-fix)。安装包与 SHA-256 一并上传 GitHub，位于 `dist/1.0.140/`、`dist/1.0.168/` 和 `dist/common/`。原厂 ROM、测试代码、构建缓存和设备私有材料只保留本地。

## 工具说明

| 适用固件 | 工具 | 用途 |
| --- | --- | --- |
| 1.0.140 | Docker 自启修复 | 等待原 Docker 数据盘，使用 procd 托管已有 Docker |
| 1.0.140 | Docker 镜像代理 | 开关 dockerd 的 HTTP 代理，支持仅保存配置 |
| 1.0.140 | WAN MAC 页面修复 | 修复查询不到访问者 MAC 时的 WAN 页面 HTTP 500 |
| 1.0.140 | DHCP 页面修复 | 修正保存参数错配，支持 `/24`、`/16` 地址池 |
| 1.0.168 | Docker 与原厂页面恢复 | 刷原版后通过 root SSH 补齐 Docker 服务和“高级设置 → DOCKER” |
| 1.0.168 | WAN MAC 页面修复 | 使用本版模板摘要，修复 MAC 空值报错 |
| 1.0.168 | DHCP `/16` 修复 | 修正地址池计数和起始偏移，保留本版原厂 `/24` 处理 |
| 两版共用 | SSH 恢复 | 已硬固化且保留 Telnet 入口时，升级/重置后重新开启 SSH |
| 两版共用 | SSH 现代算法 | 分阶段升级 Dropbear，增加 Ed25519、ECDSA、RSA-SHA2 支持 |

## 工具链接

| 工具 | 下载 / 源码 | 使用说明 |
| --- | --- | --- |
| 1.0.140 Docker 自启 | [脚本](1.0.140/docker-autostart/install-router-docker-autostart.sh) | [说明](1.0.140/docker-autostart/README.md) |
| 1.0.140 Docker 代理 | [脚本](1.0.140/docker-proxy/docker-mihomo-proxy.sh) | [说明](1.0.140/docker-proxy/README.md) |
| 1.0.140 MAC 修复 | [脚本](1.0.140/web-wan-mac/fix-router-web-mac.sh) | [说明](1.0.140/web-wan-mac/README.md) |
| 1.0.140 DHCP 修复 | [脚本](1.0.140/web-dhcp/fix-router-dhcp-web.sh) | [说明](1.0.140/web-dhcp/README.md) |
| 1.0.168 Docker 与页面 | [离线安装包](dist/1.0.168/router-docker-1.0.168-v1.0.0.tar.gz) · [源码](1.0.168/docker/) · [SHA-256](dist/1.0.168/router-docker-1.0.168-v1.0.0.tar.gz.sha256) | [说明](1.0.168/docker/README.md) |
| 1.0.168 MAC 修复 | [脚本](1.0.168/web-wan-mac/fix-router-web-mac.sh) | [说明](1.0.168/web-wan-mac/README.md) |
| 1.0.168 DHCP `/16` | [脚本](1.0.168/web-dhcp/fix-router-dhcp16-web.sh) | [说明](1.0.168/web-dhcp/README.md) |
| SSH 恢复 | [完整工具目录](ssh-reopen/) | [说明](ssh-reopen/README.md) |
| SSH 现代算法 | [安装包](dist/common/router-ssh-modern-2026.94-aarch64-v2.tar.gz) · [SHA-256](dist/common/router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256) | [说明](ssh-modern/README.md) |

版本入口：[1.0.140](1.0.140/README.md) · [1.0.168](1.0.168/README.md) · [安装包目录](dist/README.md)。

## 使用说明

先确认设备为 RA70，并从原厂固件版本选择对应工具。单文件修复上传对应 `.sh`；Docker 和 SSH 现代算法须上传并解压完整安装包。下载包后，在包所在目录校验同名 `.sha256`：

```sh
sha256sum -c router-docker-1.0.168-v1.0.0.tar.gz.sha256
```

MAC / DHCP 修复通过路由器 root SSH 执行。以下以已上传的仓库目录和 1.0.168 为例：

```sh
sh 1.0.168/web-wan-mac/fix-router-web-mac.sh status
sh 1.0.168/web-wan-mac/fix-router-web-mac.sh apply
sh 1.0.168/web-dhcp/fix-router-dhcp16-web.sh status
sh 1.0.168/web-dhcp/fix-router-dhcp16-web.sh apply
```

1.0.168 Docker：刷入原厂 1.0.168 并恢复 root SSH 后，将离线包上传到外接盘，在包所在目录执行。将示例 `/extdisks/sda1` 换成已确认的 ext4 实际挂载点：

```sh
tar -xzf router-docker-1.0.168-v1.0.0.tar.gz
cd router-docker-1.0.168
sh install-router-docker.sh apply --disk /extdisks/sda1
sh install-router-docker.sh start
```

`apply` 默认只准备程序与页面。随后可使用原厂后台开关或 `start` 启动，`stop` 停止，`restore` 回退服务与页面。1.0.140 的 Docker 自启工具要求原厂 Docker 已经安装，不是完整安装器。

SSH 恢复在电脑 WSL/Linux 的仓库根目录运行 `bash ssh-reopen/reopen-ssh-wsl.sh 192.168.31.1`，地址按实际情况修改。SSH 现代算法升级按[分阶段安装说明](ssh-modern/README.md#安装包与分阶段安装)执行 `prepare → candidate-ok → activate → confirm`；保留原连接，完成新连接验证后再确认。

## 注意事项

- 脚本与原文件摘要、启动结构必须匹配；不要绕过保护或跨固件套用。1.0.140 与 1.0.168 的 DHCP 修复不同。
- **1.0.168 原厂支持 ext4**。Docker 部署复用原厂驱动与挂载，按 UUID 查找已挂载的 ext4 USB 分区；不分区、不格式化，不删除已有容器与卷。原厂引擎包是兼容基线，最高兼容 Docker 版本尚未确定。
- **1.0.168 的 Docker、页面修复及 SSH 兼容性已完成离线/隔离核对，仍待该固件实机验收。** 1.0.140 的 SSH 现代算法已有真实登录验证；验证范围以各工具说明为准。
- 安装 MAC/DHCP 补丁不改写现有网络设置；随后在原厂页面保存 DHCP 设置仍会执行原厂服务重启或设备重启流程。安装不能自动恢复此前写错的地址池。
- Docker 启停、代理切换和回退可能中断容器。1.0.168 页面中的 Portainer 为可选组件，需另行配置已核对的 ARM64 镜像摘要，不默认安装 `latest`。
- SSH 恢复依赖升级/重置后仍存在的硬固化 Telnet 入口；工具不能创建不存在的入口。SSH 升级保留端口和认证策略，需核对主机指纹，并保留路由器上的备份和密钥目录。
- OTA、重置、再次刷机可能覆盖部署内容；操作前保存重要数据及独立 SSH 恢复材料，完成后先检查状态再决定是否重新安装。
