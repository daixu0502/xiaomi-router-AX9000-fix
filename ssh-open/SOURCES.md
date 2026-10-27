# 来源与实现边界

参考用户提供的 `小米路由器ssh一键获取工具.zip`，SHA-256：

`548db008f691ec67f39c5fe8a5c09b2a48b0130d86724193137ad0a1b2aba277`

该样本内部为 [XMiR-Patcher](https://github.com/openwrt-xiaomi/xmir-patcher)。参考其菜单 2 的 `connect.py`、`connect6.py`、`connect5.py` 和 `gateway.py`，按 AX9000 的活动路线顺序，实现 Web 登录协议、`start_binding` / `arn_switch` / smartcontroller 的接口调用。smartcontroller 命令注入为 CVE-2023-26319，原研究作者 Julien R. (SoEasY)、Marin Duroyon，见 [Thalium 原研究](https://blog.thalium.re/posts/rooting-xiaomi-wifi-routers/)。

本目录为 Python 标准库与 Shell 的独立实现，不分发原压缩包的 Python 运行时、第三方库、Dropbear 二进制、内核模块或 Bootloader。没有将样本所有菜单或机型支持迁移进来。

与样本菜单 2 的主要差异：默认保留 root 密码；用原厂摘要约束更改；只改 `channel="debug"` 与 NVRAM `ssh_en`；不做 Telnet/替代 Dropbear 回退；诊断字段恢复原值；不用 2033 年设时探测；不清空智能场景；使用显式完成标记和真实 SSH 认证验证。没有引入当前上游新增的 connect7 路线或永久 SSH 菜单。

协议和离线组件相符不代表漏洞对 1.0.140/1.0.168 必然有效。分发包不包含固化模块，不能用于证明 Bdata 修改或跨 OTA 固化成功。
