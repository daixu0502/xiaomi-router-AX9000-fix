# WAN 页面 MAC 空值修复

`fix-router-web-mac.sh` 修复通过端口转发或反向代理进入 WAN 设置页面时，因查不到访问者 MAC 而产生 HTTP 500 的问题。

目标固件：**小米 AX9000（RA70）原厂开发版 1.0.140**。其他版本未验证；实际执行仍须匹配已知 WAN 模板表达式。版本核对来源见[仓库固件说明](../README.md#针对的原厂固件)。

目标文件为 `/usr/lib/lua/luci/view/web/setting/wan.htm`。原模板直接执行 `string.upper(luci.sys.net.ip4mac(remote_addr))`；MAC 查询返回 `nil` 时会报错。修复仅将该调用改为：

```lua
string.upper(luci.sys.net.ip4mac(remote_addr) or "")
```

## 使用

将脚本上传到路由器，在 root SSH 会话中执行：

```sh
sh fix-router-web-mac.sh status
sh fix-router-web-mac.sh apply
```

无参数等同于 `apply`。已修复时不会重复改写；模板版本或表达式数量不匹配时拒绝覆盖。完成后刷新 WAN 页面，并用原来的转发或反代入口复查。

## 备份和恢复

每次实际修改前，原模板及修复结果备份到 `/data/router-web-mac-fix/backup-XXXXXX/`。恢复需使用执行结果给出的实际编号：

```sh
sh fix-router-web-mac.sh restore backup-Ab12Cd
```

恢复前核对当前文件是否仍为该次修复结果；发现固件升级或其他修改时拒绝覆盖。脚本不修改 MAC、WAN 参数、防火墙或端口转发规则，不重启服务。

已使用故障模板完成本地 BusyBox 隔离检查；页面效果需在实际路由器上复查。固件升级可能覆盖模板，升级后应先运行 `status`。

[返回仓库说明](../README.md)
