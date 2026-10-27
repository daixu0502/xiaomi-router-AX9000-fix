# 两版共用 SSH 安装包

适用于 AX9000 / RA70 原厂开发版 1.0.140 与稳定版 1.0.168。现代算法升级检查已核对的 22/3964 配置；Web 开启工具检查原厂启动脚本与程序，保留现有端口，漏洞可用性待实机验证。

| 工具 | 下载 | 使用说明 |
| --- | --- | --- |
| SSH 现代算法升级 | [安装包](router-ssh-modern-2026.94-aarch64-v2.tar.gz) · [SHA-256](router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256) | [分阶段安装](../../ssh-modern/README.md) |
| WSL 从 Web 开启 SSH | [工具包](router-ssh-open-wsl-v1.0.0.tar.gz) · [SHA-256](router-ssh-open-wsl-v1.0.0.tar.gz.sha256) | [使用说明](../../ssh-open/README.md) |
| 固化后 SSH 恢复 | [完整工具目录](../../ssh-reopen/) | [WSL 使用说明](../../ssh-reopen/README.md) |

SSH 现代算法安装包包含静态 Dropbear 2026.94、修复脚本、程序摘要、来源和许可证。首次安装需要完整包，不能只复制 `.sh`。

```sh
sha256sum -c router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256
tar -xzf router-ssh-modern-2026.94-aarch64-v2.tar.gz
sha256sum -c SHA256SUMS
```

在路由器 root SSH 会话按工具说明执行 `prepare → candidate-ok → activate → confirm`。保留原连接并核对新密钥指纹，未确认时自动回退。安装包不含设备密码、私钥、配置备份或授权公钥。

1.0.140 已有真实 SSH 登录验证；1.0.168 的共用依据为相同组件及隔离测试，尚待实机验证。恢复工具依赖已硬固化且仍可访问的 Telnet 入口。

WSL Web 开启工具单独解包，在电脑上运行 `bash open-ssh-wsl.sh 路由器地址 --check` 做只读检查；去掉 `--check` 后尝试认证接口。不依赖 Telnet，不进行硬固化，不能保证真实固件仍有漏洞。该工具包只含 Python/Shell 与文档，不含 Dropbear 程序。

[仓库说明](../../README.md) · [安装包目录](../README.md)
