# AX9000 固化 SSH 后重新开启 SSH（WSL）

对应[恩山教程《小米 AX9000 SSH + 硬固化》第八步](https://www.right.com.cn/forum/thread-5695827-1-1.html)：升级原厂固件或恢复出厂设置后，通过已经固化保留的 Telnet 入口恢复 SSH。需在每次升级/重置完成、路由器重新可访问后，从电脑手动执行一次。

前提是你已经完成硬固化，Telnet 可连接，并且 `nvram get ssh_en` 为 `1`。本工具只恢复 SSH，不执行固化、刷分区、升级、重置或重启。目标型号为小米 AX9000 / RA70；**原厂开发版 1.0.140 与稳定版 1.0.168 共用本目录**，两版 Dropbear 启动脚本与默认配置完全相同。脚本按型号、SSH 开关和启动结构检查，不绑定固定 SSH 端口。

共用结论来自两份固件的内容比较与本地隔离恢复测试；不表示 1.0.168 升级后的 Telnet 入口和实际登录已验证。硬固化/Telnet 是否保留是额外前提，工具不能凭空恢复不存在的入口。其他固件仍须单独核对，见[共用条件说明](../ssh-modern/docs/ssh-common-compatibility.md)。

## 准备 Telnet 初始密码

按照你提供的方法，打开 [miwifi.dev 的 SSH 密码计算页](https://miwifi.dev/ssh)，输入路由器 **SN 序列号**计算初始密码。SN 可从机身标签查看。重置后首次登录 Telnet 时使用 `root` 和计算出的初始密码；如果之后改过 root 密码，则使用当前有效密码。

计算结果不是路由器 Web 管理密码，也不是教程最后设置的 `admin`。脚本在终端隐藏输入密码，不保存密码或 SN；无需将这些信息写入脚本。Telnet 本身仍是明文协议，请在可信的本地网络使用。

## 在 WSL 中运行

需要 Python 3.8+ 和 OpenSSH 客户端，全部 Python 代码只使用标准库，兼容移除 `telnetlib` 的新版 Python，无需 pip 或 expect。

Ubuntu/WSL 若缺依赖：

```bash
sudo apt update
sudo apt install python3 openssh-client
```

在 WSL 终端进入本目录：

```bash
cd '/path/to/xiaomi-router-AX9000-fix/ssh-reopen'
```

如果恢复出厂后使用默认地址：

```bash
bash reopen-ssh-wsl.sh 192.168.31.1
```

如果仍使用当前网络的路由器地址：

```bash
bash reopen-ssh-wsl.sh 10.31.0.1
```

执行流程：

1. 通过 Telnet 23 端口登录 root，按提示输入计算出的初始密码或当前密码。
2. 检查型号、SSH 开关及 Dropbear 启动脚本。
3. 若还未修改，将原启动脚本备份为路由器上的 `/etc/init.d/dropbear.ssh-reopen.bak.XXXXXX`，将唯一的 `channel=` 赋值改为 `channel="debug"`，检查 Shell 语法后同目录原子替换。
4. 执行 `/etc/init.d/dropbear start`，保留 root 密码、SSH 端口、授权公钥、防火墙和服务自启配置。
5. 从 `/etc/config/dropbear` 读取端口；没有显式端口时尝试默认 `22`，等待 SSH 协议响应。
6. 调用 WSL 的 `ssh` 实际验证 root 登录。第一次连接需核对主机指纹，按提示输入当前 root 密码；成功时显示 `SSH_ROOT_OK` 和完成提示。已有可用密钥时也可按现有 SSH 客户端配置认证。

无需 `sudo` 运行本工具。WSL 需能访问路由器 LAN 地址；如果原地址不通，先检查重置后的 LAN 地址、电脑网络、VPN/代理及 WSL 网络。

## 可选修改 root 密码

教程使用 `admin` 作为示例密码。本工具默认保留当前密码；如需同时改密，使用：

```bash
bash reopen-ssh-wsl.sh 192.168.31.1 --set-password
```

会在 SSH 开启命令成功后，隐藏输入并确认新密码，通过交互式 `passwd root` 修改。新密码同时用于 root 的 SSH/Telnet 登录；后续 SSH 验证使用新密码。密码不会作为命令行参数传入、不写进远端 Shell 命令或历史文件，也不会自动设置为 `admin`。

## 参数

```bash
bash reopen-ssh-wsl.sh --help

# 只改变连接和验证使用的端口，不修改路由器配置
bash reopen-ssh-wsl.sh 10.31.0.1 --telnet-port 23 --ssh-port 3964

# 只检查 SSH 协议响应，跳过实际 root 登录验证
bash reopen-ssh-wsl.sh 192.168.31.1 --skip-ssh-login
```

升级或重置后端口可能恢复为 `22`，不要机械使用旧端口 `3964`。默认自动读取配置更合适。`--skip-ssh-login` 成功只代表服务有 SSH 响应，不能证明密码或 root 登录可用。

SSH 验证仅在本次调用追加 `ssh-rsa` 兼容选项，以兼容原厂旧 Dropbear；不修改全局 SSH 配置，不关闭主机密钥检查，也不删除 `known_hosts`。固件重置导致主机指纹变化时，应先核对设备身份，再手动更新对应记录。

## 文件、恢复与故障处理

| 文件 | 用途 |
| --- | --- |
| `reopen-ssh-wsl.sh` | WSL/Linux 启动入口 |
| `reopen_ssh.py` | Telnet 登录、可选改密、端口检查和 SSH 登录验证 |
| `router-enable-ssh.sh` | 由 Python 经 Telnet 发送执行的路由器端检查与恢复逻辑 |

三个文件放在一起使用，不必上传到路由器。直接运行路由器端文件不会完成电脑侧登录和验证。

如果 Telnet 拒绝连接，检查地址、是否已完成硬固化、固件是否仍支持该入口。本工具不能在没有 Telnet 或其他管理入口时恢复 SSH。认证失败请重新检查 SN/初始密码，或使用改过的 root 密码；工具不会自动尝试多个密码。

遇到型号不符、`ssh_en` 不为 `1`、脚本结构不符或检测到本仓库的现代 Dropbear 管理脚本时，停止操作。现代 Dropbear 的状态应先用 `ssh-modern` 工具检查，避免破坏其摘要与回退管理。

修改后的脚本语法检查失败时保留原文件；`dropbear start` 返回失败时自动恢复此次备份。**后续改密、SSH 端口探测、登录验证失败或中途断线不自动撤销已经完成的操作。** 终端会提示失败，应先通过 Telnet 核对当前服务和密码，避免误以为整个过程没有生效。启动返回成功也不等于 SSH 登录成功，以最后的实际登录验证为准。

需手动恢复启动脚本时，在 Telnet 中按终端打印的实际备份路径执行（确认备份属于本次操作；不要把下面的 `XXXXXX` 原样使用）：

```sh
cp -p /etc/init.d/dropbear.ssh-reopen.bak.XXXXXX /etc/init.d/dropbear
```

这里只恢复启动脚本，不恢复密码或自动调整当前运行服务。备份位于 `/etc`，升级或恢复出厂后可能丢失；本工具不承诺跨固件保留备份。已经是 `channel="debug"` 时不会重复创建备份。工具使用 `/tmp/router-ssh-reopen.lock` 防止并发；断电留下锁时，确认没有其他恢复操作再手动清除空锁目录。

## 验证范围

开发验证在 WSL 中进行，包含 Shell 语法、Telnet 协议处理和路由器文件/服务桩模拟。未对真实路由器执行本工具，未进行真实固件升级、重置或密码修改；新版固件兼容性需要在相应设备上实际确认。本地测试位于仓库 `tests/`，按工作区约定不加入 Git 索引。
