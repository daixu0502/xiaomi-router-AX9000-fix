# 两版共用 SSH 安装包

适用于 AX9000 / RA70 原厂开发版 1.0.140 与稳定版 1.0.168，安装时仍检查启动脚本和已核对的 22/3964 配置。

| 工具 | 下载 | 使用说明 |
| --- | --- | --- |
| SSH 现代算法升级 | [安装包](router-ssh-modern-2026.94-aarch64-v2.tar.gz) · [SHA-256](router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256) | [分阶段安装](../../ssh-modern/README.md) |
| 固化后 SSH 恢复 | [完整工具目录](../../ssh-reopen/) | [WSL 使用说明](../../ssh-reopen/README.md) |

SSH 安装包包含静态 Dropbear 2026.94、修复脚本、程序摘要、来源和许可证。首次安装需要完整包，不能只复制 `.sh`。

```sh
sha256sum -c router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256
tar -xzf router-ssh-modern-2026.94-aarch64-v2.tar.gz
sha256sum -c SHA256SUMS
```

在路由器 root SSH 会话按工具说明执行 `prepare → candidate-ok → activate → confirm`。保留原连接并核对新密钥指纹，未确认时自动回退。安装包不含设备密码、私钥、配置备份或授权公钥。

1.0.140 已有真实 SSH 登录验证；1.0.168 的共用依据为相同组件及隔离测试，尚待实机验证。恢复工具依赖已硬固化且仍可访问的 Telnet 入口。

[仓库说明](../../README.md) · [安装包目录](../README.md)
