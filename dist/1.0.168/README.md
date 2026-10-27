# 1.0.168 工具下载

适用于 AX9000 / RA70 国行原厂稳定版 1.0.168。

| 工具 | 下载 | 使用说明 |
| --- | --- | --- |
| Docker 服务与原厂页面恢复 | [离线安装包](router-docker-1.0.168-v1.1.0.tar.gz) · [SHA-256](router-docker-1.0.168-v1.1.0.tar.gz.sha256) | [部署与回退](../../1.0.168/docker/README.md) |
| Docker 镜像代理 | [独立脚本](docker-mihomo-proxy-1.0.168-v1.0.0.sh) · [SHA-256](docker-mihomo-proxy-1.0.168-v1.0.0.sh.sha256) | [托管与非托管方式](../../1.0.168/docker-proxy/README.md) |
| WAN MAC 页面修复 | [脚本](../../1.0.168/web-wan-mac/fix-router-web-mac.sh) | [说明](../../1.0.168/web-wan-mac/README.md) |
| DHCP `/16` 修复 | [脚本](../../1.0.168/web-dhcp/fix-router-dhcp16-web.sh) | [说明](../../1.0.168/web-dhcp/README.md) |

核心 1.1.0 增加默认 180 秒的开机 API 就绪检查。已经安装工具 1.0.0 时，在新版完整目录执行 `sh install-router-docker.sh upgrade` 保留配置升级；当前运行的 Docker 不自动重启。代理脚本沿用 1.0.140 逻辑，`on/off` 默认重启，`--no-restart` 只保存配置。

Docker 离线包约 53 MiB，含安装器、页面和已核对的小米 ARM64 Docker 程序，不含 Portainer 镜像。刷原版后先恢复 root SSH，并确认 ext4 USB 分区已挂载；上传包至外接盘后执行：

```sh
sha256sum -c router-docker-1.0.168-v1.1.0.tar.gz.sha256
tar -xzf router-docker-1.0.168-v1.1.0.tar.gz
cd router-docker-1.0.168
sh install-router-docker.sh apply --disk /extdisks/sda1
```

示例挂载点需替换为实际值。默认只准备服务与页面，使用页面开关或 `sh install-router-docker.sh start` 启动；`restore` 回退服务和页面，外接盘数据保留。1.0.168 本身支持 ext4，工具不分区、不格式化。

当前已做离线与隔离验证，仍待 1.0.168 真机容器及浏览器验收。共用 SSH 包见 [common](../common/README.md)。

[仓库说明](../../README.md) · [安装包目录](../README.md)
