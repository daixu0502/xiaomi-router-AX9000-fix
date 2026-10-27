# AX9000 SSH 综合工具下载

## 仓库说明

原 Web 开启、Telnet 恢复和现代算法工具已合并，并增加开机修复及备份后 Bdata 固化。适用于 RA70 原厂 1.0.140 / 1.0.168；新增固化待实机验证。

[完整工具包](router-ssh-v2.0.0.tar.gz) · [SHA-256](router-ssh-v2.0.0.tar.gz.sha256) · [统一使用说明](../../ssh/README.md) · [仓库首页](../../README.md)

## 使用教程

在 WSL/Linux 校验并解包：

```sh
sha256sum -c router-ssh-v2.0.0.tar.gz.sha256
tar -xzf router-ssh-v2.0.0.tar.gz
cd router-ssh
sha256sum -c SHA256SUMS
sh ssh.sh --help
```

`open` 从认证后的 Web 接口开启；`recover` 使用已有 Telnet；已有 SSH 后可用 `persist` 固化、`modern` 分阶段升级算法。完整参数和备份步骤见统一说明。

## 注意事项

- 固化前必须保留离机 Bdata 备份；包内不含设备密码、私钥、公钥配置或分区备份。
- 内核模块和 Bdata 写入未实机验收；不强制加载，不自动重启，不承诺跨 OTA/重置自动 SSH。
- 软件固化和现代算法保留现有 SSH 配置，遇到未知文件摘要或正在等待确认的切换会停止。
- 已清理旧 SSH 分发包，当前使用统一包；已部署的 `/data/router-ssh-modern/` 运行路径继续保留。
