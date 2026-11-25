# 从 10.31.0.2 访问桥接光猫管理页

适用于小米 AX9000（RA70）原厂稳定版 **1.0.168**。光猫处于桥接模式，AX9000 负责 PPPoE 拨号。脚本让 LAN 内地址为 `10.31.0.2` 的电脑通过路由器访问光猫 `192.168.1.1` 的管理页。

电脑应经 `br-lan` 接入。请为路由器预留光猫管理网段的 `192.168.1.2`。

## 在路由器上配置

打开脚本文件，点击 GitHub 的 **Download raw file**，将文件上传到路由器的 `/tmp/` 目录。[打开 configure-modem-access.sh](configure-modem-access.sh)

以 `root` 登录路由器，在 SSH 会话中运行一次即可配置并生效。

```sh
sh /tmp/configure-modem-access.sh
```

脚本从 `network.wan.ifname` 读取拨号使用的底层网口，并给它配置 `192.168.1.2/24`。防火墙规则放行从 `10.31.0.2` 到 `192.168.1.1` 的 TCP 80、443，并为这对地址配置源地址转换，让光猫将回包发到 `192.168.1.2`。

配置保存在 UCI 中，路由器开机时自动加载。再次运行会检查已有配置，按需补齐缺少的转发或 NAT 规则。只查看当前状态时运行以下命令。

```sh
sh /tmp/configure-modem-access.sh status
```

## 从电脑验证

在 `10.31.0.2` 上用浏览器打开 [光猫 HTTP 管理页](http://192.168.1.1/)。也可以在这台电脑的 Windows PowerShell 中绕过代理测试。

```powershell
curl.exe --noproxy "*" --interface 10.31.0.2 --connect-timeout 3 --max-time 6 -sS -o NUL -w "HTTP %{http_code}\n" http://192.168.1.1/
```

现场验证中，电脑直连登录页返回 `HTTP 200`，光猫的 HTTPS 端口 443 拒绝连接。这条转发规则只放行 TCP，判断网页是否可达请使用 HTTP。

如果直连成功、浏览器却显示 `502 Bad Gateway`，检查电脑的代理分流。使用 Clash Verge 时，将以下规则放到 `MATCH` 之前，应用代理配置后重新打开 HTTP 管理页。

```text
IP-CIDR,192.168.1.1/32,DIRECT,no-resolve
```

## 配置变更与回退

脚本管理 `network.modem_mgmt`、`firewall.modem_mgmt` 和 `firewall.modem_mgmt_pc` 三个配置段。如果 `network` 或 `firewall` 有待提交的 UCI 更改，脚本会退出，待现有更改处理完毕后再运行。

写入前，脚本会把本次涉及的配置文件备份到路由器的 `/data/modem-mgmt-backup.XXXXXX/`，实际目录会显示在终端。配置加载或规则校验失败时，脚本会回退本次替换的文件。若其他进程已改动某个文件，终端会提示核对备份。

若终端已提示路由与防火墙校验通过，但 HTTP 探测失败并以状态码 `2` 退出，访问规则会保留。此时请核对光猫管理地址及其 HTTP 服务。

[返回 1.0.168 工具](../README.md)
