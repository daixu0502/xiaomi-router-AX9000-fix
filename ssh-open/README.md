# AX9000 从 Web 后台开启 SSH（WSL）

参考所提供 XMiR-Patcher 压缩包的菜单 2，为 WSL/Linux 独立实现。使用已认证的原厂 Web 接口，依次尝试 `start_binding → arn_switch → smartcontroller`，确认 root 命令执行、核对原厂文件后开启 SSH。Python 仅使用标准库，不需要 pip、Windows EXE、Telnet 或预先可用的 SSH。

适用范围限定为 **AX9000 / RA70 原厂 1.0.140、1.0.168**。两版启动文件已离线核对；**Web 漏洞和完整开启流程尚未在真实设备上验证，不能保证这些固件仍有可利用漏洞**。如果接口已修复，工具会报失败，不能靠忽略检查继续。

## 下载与准备

下载 [完整工具包](../dist/common/router-ssh-open-wsl-v1.0.0.tar.gz) 和 [SHA-256](../dist/common/router-ssh-open-wsl-v1.0.0.tar.gz.sha256)，在 WSL 中执行：

```bash
sudo apt update
sudo apt install python3 openssh-client
sha256sum -c router-ssh-open-wsl-v1.0.0.tar.gz.sha256
tar -xzf router-ssh-open-wsl-v1.0.0.tar.gz
cd router-ssh-open-wsl
bash open-ssh-wsl.sh 192.168.31.1 --check
```

Python 要求 3.8+。WSL 必须能访问路由器 LAN 地址，先在浏览器完成原厂初始化。使用源码时保留本目录的 `.sh`、`.py` 三个执行文件，在仓库根目录运行：

```bash
bash ssh-open/open-ssh-wsl.sh 192.168.31.1 --check
```

`--check` 只读取公开设备信息、检查指定端口的 SSH 协议响应，不登录 Web、不探测漏洞、不写配置。它不能判断漏洞是否可用，也不能证明 root 认证成功。

## 开启与登录验证

在完整工具目录中执行，地址按实际 LAN 地址修改：

```bash
bash open-ssh-wsl.sh 192.168.31.1
```

按提示隐藏输入 **Web 后台管理密码**。工具取得 Web 令牌后尝试接口，通过诊断值读回确认命令执行。它会备份原启动脚本和 SSH 配置，只将唯一的 `channel=` 改为 `channel="debug"`，设置 NVRAM `ssh_en=1`，启用并启动原厂 Dropbear。结果与仓库 SSH 恢复工具产生的启动脚本一致。

默认 **保留现有 root 密码、SSH 端口与认证配置**，不会自动设置 `root/root`。Web 管理密码与 root 密码不一定相同。需要在开启时设置一个明确的新 root 密码，可使用：

```bash
bash open-ssh-wsl.sh 192.168.31.1 --set-password
```

通过原厂文件检查后才隐藏输入、确认新密码，至少 8 字符。新密码影响 root 的 SSH/Telnet 登录。密码不作为本机命令行参数或日志保存；Web 命令使用 POST。smartcontroller 路线会暂存含编码命令的文件，权限为 600，正常/异常清理会尝试删除；断电或失联后可能残留。编码不等于加密，请在可信 LAN 使用。

工具从路由器配置读取实际端口，等待 SSH 响应，再调用 WSL OpenSSH 验证 root 登录。请核对主机指纹；工具不会关闭主机密钥检查、清除 `known_hosts` 或修改全局 SSH 配置。看到 `SSH_ROOT_OK` 和最终验证成功才表示实际 root 登录通过。

若指定端口已经有 SSH，直接验证登录，跳过漏洞和配置修改。此时不接受 `--set-password`；请在已有 SSH 中执行 `passwd root`。发现配置中的其他端口已有 SSH 时，也会保留服务与密码并转入登录验证。

## 参数

```bash
bash open-ssh-wsl.sh --help

# 已知使用自定义 SSH 端口时，先检测该端口
bash open-ssh-wsl.sh 10.31.0.1 --ssh-port 3964

# 只尝试一条路线，避免自动进入后续路线
bash open-ssh-wsl.sh 192.168.31.1 --method start_binding
bash open-ssh-wsl.sh 192.168.31.1 --method arn_switch
bash open-ssh-wsl.sh 192.168.31.1 --method smartcontroller

# 只确认 SSH 响应，跳过交互式 root 登录验证
bash open-ssh-wsl.sh 192.168.31.1 --skip-ssh-login
```

`--web-port` 改变电脑连接的 HTTP 端口；`--ssh-port` 改变首次检查端口。两者都不修改路由器端口设置。目标只接受单个 IPv4 地址，不扫描网段。LAN HTTP 请求不继承 WSL 的代理环境变量。

## 修改范围与故障处理

- 本工具对应菜单 2 的原厂 SSH 开启部分，**不执行菜单 6，不写 Bdata、不加载模块、不刷分区、不安装替代 Dropbear**，也不额外开启 Telnet、UART 或修改启动等待。
- `ssh_en` 与启动文件可用于普通重启；OTA、恢复出厂或重刷可能覆盖它们，**不承诺跨升级/重置保留 SSH**。已有硬固化 Telnet 入口时可用 [ssh-reopen](../ssh-reopen/README.md)。
- 型号、版本、原厂 Dropbear 二进制及启动脚本摘要必须匹配。现代 SSH 管理脚本、第三方替换或其他修改会拒绝执行；不覆盖原有现代 SSH。
- 会临时使用 `diag.config.iperf_test_thr` 传递状态和结果，结束时恢复读取到的数字值，只写这个诊断字段。恢复失败将返回失败；中途断电/网络中断时请核对该字段，不要同时运行其他诊断或开启工具。
- smartcontroller 路线需要能确认智能场景数量为 0；有已有场景或响应格式未知时停止，避免按时间触发用户任务。不执行 `reset_scenes`。创建的 `wsl_` 场景逐个按 ID 删除；创建响应丢失时可能不知道 ID，需人工检查残留。
- smartcontroller 会用当前路由器时间调用一次原厂设时接口，激活场景执行器，可能带来数秒时间偏移；不使用原工具的 2033 年测试。指令限制为 21 字节，分块传输可能耗时数分钟，期间会持续输出进度。
- 路由器备份目录为终端打印的 `/etc/ssh-open-backup.XXXXXX`，含原 `dropbear.init`、`dropbear.config`、`ssh_en`；权限受保护。它不含 root 密码备份，升级/重置可能删除备份。
- 启动步骤返回失败时尝试恢复启动脚本、`ssh_en` 和服务启用状态，并明确报告回滚失败。已经成功启动之后的改密、端口检查或登录失败，不自动撤销已完成操作；HTTP 超时也不代表命令没执行。请先核对实际状态。
- `/tmp/router-ssh-open.lock` 防止开启步骤并发。异常留下锁时，确认没有其他操作后再删除空锁目录；不绕过摘要或直接重复改密来排查。

## 文件与验证

| 文件 | 用途 |
| --- | --- |
| `open-ssh-wsl.sh` | WSL/Linux 入口 |
| `open_ssh.py` | Web 认证、三条接口路线、结果读回与 SSH 登录验证 |
| `router-open-ssh.sh` | 原厂文件核对、备份、开启和启动失败回滚 |
| `build-package.py` | 生成 `dist/common/` 工具包与摘要 |
| [来源说明](SOURCES.md) | 参考样本、接口来源与实现差异 |

本地验证使用 WSL、临时固件文件样本及回环 HTTP/服务桩，不访问真实路由器。测试代码只保留本地，不进入分发包或 Git 索引。真实固件中的接口过滤、场景调度、密码修改及 SSH 可达性仍需实机验收。

[返回仓库说明](../README.md)
