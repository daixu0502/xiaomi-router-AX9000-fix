# 安装包

| 包 | 用途 | 校验 |
| --- | --- | --- |
| [router-ssh-modern-2026.94-aarch64-v2.tar.gz](router-ssh-modern-2026.94-aarch64-v2.tar.gz) | AX9000 ARM64 SSH 现代算法升级，含静态 Dropbear 2026.94 与安装器 | [SHA-256](router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256) |

v2 整理了仓库目录、使用说明和 Ed25519 密钥登录步骤，程序与已验证的 2026.94 构建相同。

该包包含 `bin/dropbear`、`fix-router-ssh-modern.sh`、README、构建来源、程序摘要、构建配置和 Dropbear/musl/Zig 许可证，不包含设备密码、私钥、配置副本、授权公钥或测试代码。

下载后可在 Linux/WSL 中检查归档摘要：

```sh
sha256sum -c router-ssh-modern-2026.94-aarch64-v2.tar.gz.sha256
```

解压后检查程序摘要，再按包内 README 分阶段安装：

```sh
tar -xzf router-ssh-modern-2026.94-aarch64-v2.tar.gz -C /path/to/empty-directory
cd /path/to/empty-directory
sha256sum -c SHA256SUMS
```

安装器在路由器上使用固定的程序 MD5 做额外一致性检查；下载的完整性以此目录发布的 SHA-256 为准。首次安装流程见 [SSH README](../ssh-modern/README.md)。

其他功能为独立 Shell 脚本，直接从各功能目录下载，无需此安装包。本地旧归档、构建依赖及缓存不收入 Git 索引，仓库仅跟踪当前核对过的版本化安装包。
