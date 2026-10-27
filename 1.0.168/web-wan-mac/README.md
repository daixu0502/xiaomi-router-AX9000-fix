# 1.0.168 WAN 页面 MAC 空值修复

适用于 **小米 AX9000 / RA70 原厂稳定版 1.0.168**。原模板在找不到访问者 MAC 时执行 `string.upper(nil)`，导致 WAN 设置页面 HTTP 500。反向代理、跨网段或部分转发入口可能触发。

脚本只把 `/usr/lib/lua/luci/view/web/setting/wan.htm` 中唯一的原表达式改为：

```lua
string.upper(luci.sys.net.ip4mac(remote_addr) or "")
```

不修改物理 MAC、克隆 MAC、WAN、代理、防火墙或端口转发规则，不重启服务。

## 使用

上传 `fix-router-web-mac.sh`，在 root SSH 会话执行：

```sh
sh fix-router-web-mac.sh status
sh fix-router-web-mac.sh apply
```

无参数同 `apply`。先核对固件型号/版本，再核对模板 MD5：原始 `1d1c14ccecda25a2dc4869bae662bdb9`，已修复 `aae5984a944302a3b8b5b985bf27858f`。其他内容一律拒绝覆盖。完成后刷新 WAN 页面，并从原有反代/转发入口复查。

## 备份与恢复

每次实际修改前，原文件与修复结果保存在 `/data/router-web-mac-fix-1.0.168/backup-XXXXXX/`。使用安装输出的真实编号恢复：

```sh
sh fix-router-web-mac.sh restore backup-Ab12Cd
```

恢复前确认当前文件仍与该次修复结果完全相同；未知修改、符号链接或不完整备份会被拒绝。重复安装不会新增备份。恢复不修改网络配置，备份继续保留。

已用 1.0.168 真实模板在电脑临时目录验证补丁、版本保护、备份和恢复。未部署到运行 1.0.168 的路由器，实际浏览器回归仍需安装后完成。

[返回 1.0.168 工具](../README.md)
