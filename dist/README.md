# 安装包与下载入口

## 仓库说明

`dist/` 按固件版本保存分发内容，目录、安装包和摘要均提交到 GitHub。两版共用的工具放在 `common/`。

## 工具说明

| 目录 | 内容 |
| --- | --- |
| [1.0.140](1.0.140/README.md) | 原厂开发版的 Docker 自启、代理、MAC 与 DHCP 单文件修复下载入口 |
| [1.0.168](1.0.168/README.md) | 原厂稳定版的 Docker 与原厂页面恢复离线包、MAC 与 DHCP `/16` 修复入口 |
| [common](common/README.md) | 两版共用的 SSH 现代算法安装包及 SSH 恢复工具链接 |

## 工具链接

| 安装包 | 校验 | 使用说明 |
| --- | --- | --- |
| [1.0.168 Docker 与原厂页面](1.0.168/router-docker-1.0.168-v1.1.0.tar.gz) | [SHA-256](1.0.168/router-docker-1.0.168-v1.1.0.tar.gz.sha256) | [说明](../1.0.168/docker/README.md) |
| [1.0.168 Docker 独立代理脚本](1.0.168/docker-mihomo-proxy-1.0.168-v1.0.0.sh) | [SHA-256](1.0.168/docker-mihomo-proxy-1.0.168-v1.0.0.sh.sha256) | [说明](../1.0.168/docker-proxy/README.md) |
| [两版共用 SSH 现代算法](common/router-ssh-modern-2026.94-aarch64-v2.tar.gz) | [SHA-256](common/router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256) | [说明](../ssh-modern/README.md) |

## 使用说明

下载完整安装包和同名 `.sha256` 文件，在两者所在目录执行 `sha256sum -c 包名.tar.gz.sha256`，然后解包并按对应工具说明安装。单文件修复从相应固件目录的下载入口获取，通过 root SSH 执行。

## 注意事项

- 固件专用工具不能跨版本套用，共用 SSH 工具仍有启动结构与配置检查。
- 1.0.168 Docker 包默认不启动服务，需已恢复 root SSH 和已挂载的 ext4 外接盘；Portainer 镜像需另行配置。
- 1.0.168 工具仍待真机验收；现有离线/隔离检查不代表实际容器与浏览器回归已完成。
- 安装包不包含原厂 ROM、测试代码、设备密码、私钥或配置备份。

[返回仓库说明](../README.md)
