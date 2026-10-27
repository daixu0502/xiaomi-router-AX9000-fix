# 1.0.140 工具下载

适用于 AX9000 / RA70 原厂开发版 1.0.140。本版修复以单文件脚本提供，点击下方链接获取；当前没有单独的打包归档。

| 工具 | 脚本 | 使用说明 |
| --- | --- | --- |
| Docker 自启修复 | [下载](../../1.0.140/docker-autostart/install-router-docker-autostart.sh) | [说明](../../1.0.140/docker-autostart/README.md) |
| Docker 镜像代理 | [下载](../../1.0.140/docker-proxy/docker-mihomo-proxy.sh) | [说明](../../1.0.140/docker-proxy/README.md) |
| WAN MAC 页面修复 | [下载](../../1.0.140/web-wan-mac/fix-router-web-mac.sh) | [说明](../../1.0.140/web-wan-mac/README.md) |
| DHCP 页面修复 | [下载](../../1.0.140/web-dhcp/fix-router-dhcp-web.sh) | [说明](../../1.0.140/web-dhcp/README.md) |

通过 root SSH 按对应说明执行。Docker 自启要求已有原厂 Docker 和数据盘；代理切换默认会重启 Docker。不要在 1.0.168 使用本版 DHCP 脚本。

共用 SSH 安装包见 [common](../common/README.md)，SSH 恢复见[完整工具目录](../../ssh-reopen/README.md)。

[仓库说明](../../README.md) · [安装包目录](../README.md)
