# AX9000 SSH 工具

## 仓库说明

本目录合并原来的 Web 开启 SSH、固化后 Telnet 恢复、现代算法升级三个工具，并增加 SSH 固化。适用于 **小米 AX9000 / RA70 原厂 1.0.140、1.0.168**，统一入口为 `ssh.sh`。

| 命令 | 用途 |
| --- | --- |
| `open` | 使用 Web 管理密码尝试开启原厂 SSH，不要求已有 Telnet |
| `recover` | 通过已有硬固化 Telnet 入口，在升级/重置后恢复 SSH |
| `modern` | 升级 Dropbear 算法，保留候选登录与超时回退 |
| `persist` | 安装开机自动修复，或备份后固化 Bdata 的 SSH/Telnet 开关 |

主入口、SSH 部署、开机修复和现代算法流程使用 Shell；Web/Telnet 协议及电脑端 Bdata CRC/字段校验使用 Python 标准库。Bdata 的只读限制需要内核模块解除，无法只靠 Shell 或 Python 绕过。包内模块固定来源与摘要，附带源码和许可证；不会强制加载不匹配模块。

下载 [完整工具包](../dist/common/router-ssh-v2.0.0.tar.gz) 和 [SHA-256](../dist/common/router-ssh-v2.0.0.tar.gz.sha256)。安装包不含设备密码、私钥、授权公钥或 Bdata 备份。仓库地址：[xiaomi-router-AX9000-fix](https://github.com/daixu0502/xiaomi-router-AX9000-fix)。

## 使用教程

### 准备工具

在电脑 WSL/Linux 中安装依赖并解包：

```sh
sudo apt install python3 openssh-client
sha256sum -c router-ssh-v2.0.0.tar.gz.sha256
tar -xzf router-ssh-v2.0.0.tar.gz
cd router-ssh
sha256sum -c SHA256SUMS
sh ssh.sh --help
```

源码使用者进入仓库 `ssh/`，命令相同。示例使用地址 `192.168.31.1`、SSH 端口 `22`；修改为实际地址。已有 SSH 使用 3964 等端口时，为 `persist`、`modern` 加 `--ssh-port 3964`，为 `open`、`recover` 同样指定实际端口。Python 要求 3.8+，路由器端不需要 Python。

### 从 Web 开启 SSH

```sh
sh ssh.sh open 192.168.31.1 --check
sh ssh.sh open 192.168.31.1 --set-password
```

`--check` 只读型号/版本并检查 SSH 响应；第二条按提示输入 Web 管理密码及新的 root 密码，尝试 `start_binding → arn_switch → smartcontroller`。去掉 `--set-password` 则保留原 root 密码，不自动设为 `root`。已有 SSH 时转入登录验证，停止漏洞和配置修改。

Web 管理密码与 root 密码不一定相同。最终会调用 OpenSSH 验证 root 登录；仅有 SSH 端口响应不代表认证成功。接口已修复、原厂文件摘要不匹配或智能场景不为空时，相应路线会停止。

### 固化 SSH

先确保 SSH 已可登录，再在电脑执行软件固化：

```sh
sh ssh.sh persist 192.168.31.1 install
sh ssh.sh persist 192.168.31.1 status
```

软件固化在 `/data/router-ssh/persist/` 保存开机修复脚本，注册防火墙启动钩子，恢复 `ssh_en` 和已核对的原厂渠道判断；兼容已安装的现代 Dropbear，不覆盖其管理脚本，不重设密码和端口。

需要 Bdata 固化时，在电脑执行：

```sh
sh ssh.sh persist 192.168.31.1 harden

# 可指定本机备份位置；路径在运行 WSL 的电脑上
sh ssh.sh persist 192.168.31.1 harden --backup-dir /mnt/d/RouterBackups
```

工具先完整读取 Bdata，下载到电脑并检查 SHA-256、CRC32；验证通过才加载匹配预期内核的模块，提交 `ssh_en=1`、`telnet_en=1`。之后重新读取 Flash，下载写后数据，检查 CRC 和其他字段均保持不变，再安装软件固化。保留 UART、启动等待和设备原厂信息，不写 Bootloader。

默认离机备份位于工具目录上一级 `local/ssh-backups/`，终端打印实际路径；路由器也在 `/data/router-ssh/persist/backups/` 保留副本。**妥善保存备份，它可能含设备识别信息和私有配置，不上传 GitHub。**

取消开机修复：

```sh
sh ssh.sh persist 192.168.31.1 remove
```

这只移除本工具的启动钩子，保留当前 SSH、密码、Bdata 开关和备份。不会自动把整个 Bdata 分区刷回。

### 升级或重置后恢复 SSH

如果硬固化保留的 Telnet 入口仍可连接，在电脑运行：

```sh
sh ssh.sh recover 192.168.31.1
```

按提示输入当前 root 密码。恢复出厂后的初始密码可用机身 SN 在 [miwifi.dev](https://miwifi.dev/ssh) 计算；它不同于 Web 密码。恢复默认保留密码和配置端口，`--set-password` 可显式改密。工具不能创建不存在的 Telnet 入口。

### 升级现代 SSH 算法

以下以正式端口 `22` 为例，在电脑准备候选服务：

```sh
sh ssh.sh modern 192.168.31.1 prepare
```

另开 WSL 终端建立转发并保持连接：

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa -p 22 -L 13964:127.0.0.1:13964 root@192.168.31.1
```

再开终端，经候选服务登录并确认，然后切换原端口、通过新连接确认：

```sh
sh ssh.sh modern 127.0.0.1 candidate-ok --ssh-port 13964
sh ssh.sh modern 192.168.31.1 activate
sh ssh.sh modern 192.168.31.1 confirm
```

`activate` 后须在 **120 秒内**从新服务连接执行 `confirm`，否则自动回退。脚本检查候选/正式端口和新版进程祖先，不能从旧连接跳过验证。支持已核对的原厂 22、既有 3964 配置，保留密码策略、原 RSA 密钥和授权公钥。

```sh
sh ssh.sh modern 192.168.31.1 status
sh ssh.sh modern 192.168.31.1 restore
```

`restore` 会恢复原厂启动方式，可能中断当前 SSH；程序、密钥与备份保留。路由器上原有 `/data/router-ssh-modern/` 路径继续使用，已部署设备不需要迁移运行数据。

### 公钥登录

现代算法升级确认后，可在 WSL 中生成或复用自己的 Ed25519 密钥并追加公钥：

```sh
[ -e "$HOME/.ssh/ax9000_ed25519" ] || ssh-keygen -t ed25519 -a 64 -f "$HOME/.ssh/ax9000_ed25519"
cat "$HOME/.ssh/ax9000_ed25519.pub" | ssh root@192.168.31.1 'umask 077; mkdir -p /etc/dropbear; printf "\n" >> /etc/dropbear/authorized_keys; cat >> /etc/dropbear/authorized_keys; chmod 700 /etc/dropbear; chmod 600 /etc/dropbear/authorized_keys'
ssh -i "$HOME/.ssh/ax9000_ed25519" -o IdentitiesOnly=yes -o PreferredAuthentications=publickey root@192.168.31.1
```

私钥保留在电脑，仅追加 `.pub` 公钥，保留已有授权。自定义端口时给两条 `ssh` 命令添加对应 `-p`。

### 在路由器内执行

将完整包上传并解压后，在路由器 root SSH 中也可执行 `sh ssh.sh persist status`、`sh ssh.sh persist install` 或 `sh ssh.sh modern prepare`。Bdata 固化优先使用上面的电脑命令，确保写入前已有离机备份；电脑侧的 CRC/字段比较不能省略。查看完整参数用 `sh ssh.sh --help`。

## 注意事项

- **1.0.168 的完整 Web 开启、模块加载、Bdata 固化及跨重启流程尚未实机验收。** 1.0.140 的既有现代算法有登录验证；本轮新增固化只做本地模拟。型号和 vermagic 匹配不等于内核 ABI 一定兼容，加载失败会停止，不使用强制加载。
- **固化不等于 OTA/重置后必然自动 SSH。** 原厂可能清理配置及启动入口，release 判断仍可能恢复；Bdata 开关用于保留恢复条件，升级后需先检查状态，必要时执行 `recover`。不能保证未来固件保留 Telnet。
- 内核模块只接受本包摘要和 `4.4.60 / aarch64 / SMP PREEMPT` 配置。该上游模块没有卸载入口，解锁的 MTD 可写标志可能保留到重启；工具不自动重启，不声称卸载模块即可重新只读。
- 固化只通过 `bdata set/commit` 修改两个开关，不直接擦写或恢复整分区。写入/读回失败可能留下部分变化，先保存输出与备份、核对状态，不盲目重复操作。
- Web 开启会临时使用一个诊断字段传递结果，退出时尝试恢复。smartcontroller 可能暂存权限 600 的编码命令、创建临时场景和调用当前时间设时接口；网络中断后需检查残留。编码不等于加密，Web HTTP、Telnet 仅用于可信 LAN。
- 不同时运行固化、Web 开启、现代算法切换或网络配置修改。现代算法等待确认时，开机修复会暂缓；检测到未知启动脚本、外部钩子或未提交防火墙配置会拒绝覆盖。
- 请核对 SSH 主机指纹，不删除信任记录来跳过身份检查。工具不修改电脑全局 SSH 配置、不关闭主机密钥验证，也不默认重设 root 密码。
- `local/`、测试、构建缓存、密钥和 Bdata 备份保持本地；使用自定义备份目录时同样自行保护。工具包和源码清单不包含这些材料。
