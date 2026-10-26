# 小米 AX9000 原厂固件修复工具

提供 Docker 开机自启、Docker 镜像代理、Web 设置页面和 SSH 现代算法修复。各功能独立存放，按需使用。

这些脚本针对小米 AX9000 原厂固件的特定路径和启动结构，需通过 SSH 在路由器上以 root 执行。部分修复会核对原文件摘要，遇到不同固件或自定义改动会拒绝覆盖。

## 针对的原厂固件

| 项目 | 已核对信息 |
| --- | --- |
| 设备 | 小米路由器 AX9000 |
| 硬件标识 | `RA70` |
| 原厂 ROM 版本 | **`1.0.140`** |
| 发布渠道 | 稳定版（`stable`） |
| 固件构建时间 | `2021-11-12 11:49:21 UTC` |

以上信息于 2026-10-26 从目标路由器的 `/usr/share/xiaoqiang/xiaoqiang_version` 只读核对。本仓库以 **AX9000 / RA70 原厂稳定版 1.0.140** 为目标，具体功能的验证范围见下文及各目录 README。

其他 ROM 版本、开发版、第三方固件或不同机型未验证兼容。即使版本号相同，原文件若已被修改，也可能不满足脚本的结构或摘要检查；不能仅凭版本号跳过检查。底层 `OpenWrt 18.06-SNAPSHOT`、Linux 内核版本及升级后的 Dropbear 版本均不是小米 ROM 版本号。

## 功能导航

| 功能 | 目录与说明 | 脚本 | 执行影响 |
| --- | --- | --- | --- |
| Docker 开机自启 | [docker-autostart](docker-autostart/README.md) | `install-router-docker-autostart.sh` | 安装 procd 托管；运行中的 Docker 需显式允许重启 |
| Docker 镜像拉取代理 | [docker-proxy](docker-proxy/README.md) | `docker-mihomo-proxy.sh` | 默认重启 Docker；支持仅保存配置 |
| WAN 页面 MAC 空值 | [web-wan-mac](web-wan-mac/README.md) | `fix-router-web-mac.sh` | 修改 WAN 模板，不重启服务 |
| DHCP 保存后页面异常 | [web-dhcp](web-dhcp/README.md) | `fix-router-dhcp-web.sh` | 安装修复不改网络配置；页面保存沿用原厂流程 |
| SSH 现代算法 | [ssh-modern](ssh-modern/README.md) | `fix-router-ssh-modern.sh` | 分阶段验证后切换 SSH，未确认自动回退 |

## 使用入口

单文件修复可直接上传对应功能目录下的 `.sh`，按其 README 执行。SSH 升级还需要编译后的程序，请下载 [完整安装包](dist/router-ssh-modern-2026.94-aarch64-v2.tar.gz)，不要只上传安装脚本。

SSH 升级使用 Dropbear 2026.94，支持 Ed25519、ECDSA 和 RSA-SHA2，保留原端口、密码策略与原 RSA 主机密钥。[Ed25519 密钥免密码登录步骤](ssh-modern/README.md#ed25519-密钥免密码登录)包含 Windows PowerShell 生成密钥、追加公钥及登录命令。

示例中的路由器地址为 `10.31.0.1`，SSH 端口为 `3964`；按实际网络修改地址。当前 SSH 升级器会核对已验证的端口与原配置，不支持直接套用到其他配置。

## 目录约定

```text
docker-autostart/   Docker 自启脚本及 README
docker-proxy/       Docker 代理脚本及 README
web-wan-mac/        WAN 模板修复及 README
web-dhcp/           DHCP 接口修复及 README
ssh-modern/         SSH 升级、构建脚本及 README
dist/               经核对的安装包、摘要与说明
```

旧仓库根目录的两个 Docker 脚本已分别迁入 `docker-autostart/` 和 `docker-proxy/`。路由器上已经部署的 `/data/` 服务路径不受本次源码目录整理影响。

测试代码、构建工具缓存、本地配置、密码、设备私钥和授权公钥不提交到 GitHub。SSH 安装包包含程序、来源信息和许可证；包内容及 SHA-256 见 [安装包说明](dist/README.md)。

## 验证范围

Docker 自启与代理保留原有实现。WAN 空值修复、SSH 回退流程和脚本语法有本地隔离验证。DHCP 修复使用原生 Lua 和内存配置桩验证保存、重复保存及 `/24`、`/16` 掩码切换；没有通过修改在线网络配置做回归测试。SSH 三种主机算法已在候选端口和正式端口使用原密码登录验证，开机回退分支仅做隔离验证，未重启路由器。
