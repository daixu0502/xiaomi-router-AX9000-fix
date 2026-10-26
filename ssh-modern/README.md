# AX9000 SSH 现代算法修复

## 功能与适用范围

目标固件：**小米 AX9000（RA70）原厂开发版 1.0.140**，原厂 Dropbear 为 `2017.75`。型号和 ROM 版本号于 2026-10-26 从设备的 `/usr/share/xiaoqiang/xiaoqiang_version` 只读核对，适用发行类型按原厂开发版标注。其他 ROM 版本或机型未验证，实际安装仍须通过原启动脚本、配置和程序摘要检查。下文的 `2026.94` 是升级后的 Dropbear 版本，不是小米固件版本。

针对已核对的 AX9000 原厂 Dropbear 2017.75：该构建仅编译了 RSA 支持，无法通过配置开启其他主机密钥算法。本功能从 [Dropbear 官方 2026.94 源码](https://github.com/mkj/dropbear/releases/tag/DROPBEAR_2026.94) 构建 ARM64 musl 静态程序，安装至 `/data/router-ssh-modern/bin/dropbear`，由原厂 procd 服务管理。

正式端口仍为 **3964**。保留原密码认证策略、`/etc/config/dropbear`、原 RSA 主机密钥及 `/etc/dropbear/authorized_keys` 路径，不新增授权公钥、不修改防火墙。

已实际验证原密码登录支持以下主机签名算法：

- `ssh-ed25519`
- `ecdsa-sha2-nistp256`
- `rsa-sha2-256`：沿用原 RSA 密钥及指纹，替代 SHA-1 签名的 `ssh-rsa`。

同时验证 `curve25519-sha256@libssh.org` 密钥交换、`aes256-ctr` 加密及 `hmac-sha2-256`。程序还支持 ChaCha20-Poly1305、SNTRUP/ML-KEM 混合密钥交换；这些由 `dropbear -Q` 查询确认，未逐一做完整登录测试。此构建不提供 `ssh-rsa`、SHA-1 HMAC 或旧 SHA-1 DH 交换。

Windows OpenSSH 已验证可在无 `+ssh-rsa` 兼容参数时协商 Ed25519。新的 Ed25519/ECDSA 主机密钥与原 RSA 密钥是不同密钥；首次出现指纹提示时，可经原可信连接运行密钥工具核对，不应直接删除原有信任记录。安装脚本不会修改电脑端 `known_hosts`。

新主机密钥在路由器生成，私钥仅保存在 `/data/router-ssh-modern/keys/`，不包含在源码、测试或安装包中。

## 安装包与分阶段安装

从源码仓库根目录的 `dist/router-ssh-modern-2026.94-aarch64-v2.tar.gz` 下载完整安装包，包含修复脚本、已编译程序、摘要、构建配置和许可证。仅复制 `.sh` 文件不足以安装，首次准备需要同包的 `bin/dropbear`。

脚本只接受已核对的原厂启动脚本、配置及附带程序，版本不符会停止。初始流程：

1. 上传并解压安装包，在路由器 root SSH 会话中执行：

   ```sh
   sh fix-router-ssh-modern.sh prepare
   ```

   这一步保留正式 SSH，只在路由器 `127.0.0.1:13964` 启动候选服务。

2. 从电脑通过原 SSH 建立本地转发，并保持连接；原厂服务仍可能需要临时的旧算法选项：

   ```sh
   ssh -o HostKeyAlgorithms=+ssh-rsa -p 3964 -L 13964:127.0.0.1:13964 root@10.31.0.1
   ```

   在另一个终端连接候选服务，用原密码登录。首次主机密钥提示应与路由器上新生成的公钥指纹核对：

   ```sh
   ssh -p 13964 root@127.0.0.1
   sh /data/router-ssh-modern/fix-router-ssh-modern.sh candidate-ok
   ```

3. 回到原路由器会话，执行：

   ```sh
   sh /data/router-ssh-modern/fix-router-ssh-modern.sh activate
   ```

   脚本保留原端口并启动 **120 秒超时回退**。从电脑重新连接正式端口，用原密码登录，再执行：

   ```sh
   ssh -p 3964 root@10.31.0.1
   sh /data/router-ssh-modern/fix-router-ssh-modern.sh confirm
   ```

   只有来自正式端口新版 Dropbear 的 SSH 会话才能确认。未确认会自动恢复原厂启动脚本和服务。

已经安装并确认新版服务的设备无需再次执行准备流程，可直接查询状态。

## Ed25519 密钥免密码登录

下面步骤使用 Windows PowerShell 和 OpenSSH 客户端。路由器需已完成上述升级。示例地址为 `10.31.0.1`、端口为 `3964`，使用 root 用户。

仅指定主机算法仍使用原密码登录：

```powershell
ssh -o HostKeyAlgorithms=ssh-ed25519 -p 3964 root@10.31.0.1
```

要改为使用电脑上的 Ed25519 私钥认证，需要生成密钥对并把公钥添加到路由器。

### 1. 在电脑生成密钥对

```powershell
$keyPath = Join-Path $env:USERPROFILE '.ssh\ax9000_ed25519'
New-Item -ItemType Directory -Force -Path (Split-Path $keyPath) | Out-Null
if (-not (Test-Path -LiteralPath $keyPath)) {
    ssh-keygen -t ed25519 -a 64 -f $keyPath
}
```

按提示设置可选的密钥口令。若该路径已经有密钥，直接复用成对的私钥与 `.pub` 文件，或更换文件名，勿覆盖原私钥。

### 2. 追加公钥到路由器

继续在同一个 PowerShell 窗口执行，首次需要输入路由器原密码：

```powershell
Get-Content "$keyPath.pub" | ssh -p 3964 root@10.31.0.1 'umask 077; mkdir -p /etc/dropbear; printf "\n" >> /etc/dropbear/authorized_keys; cat >> /etc/dropbear/authorized_keys; chmod 700 /etc/dropbear; chmod 600 /etc/dropbear/authorized_keys'
```

这里只追加 `.pub` 公钥，保留原有授权内容。当前新版服务使用 `/etc/dropbear/authorized_keys`；私钥保留在电脑，不上传到路由器或 GitHub。

### 3. 使用私钥登录并验证

```powershell
ssh -i $keyPath -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -o HostKeyAlgorithms=ssh-ed25519 -p 3964 root@10.31.0.1
```

`PreferredAuthentications=publickey` 禁止这次验证静默回退到路由器密码。设置过密钥口令时仍可能要求输入该口令，它与路由器密码不同。

以后在新的 PowerShell 窗口，可直接使用完整路径：

```powershell
ssh -i "$env:USERPROFILE\.ssh\ax9000_ed25519" -o IdentitiesOnly=yes -o HostKeyAlgorithms=ssh-ed25519 -p 3964 root@10.31.0.1
```

若提示 `Permission denied (publickey)`，检查上传的是配套 `.pub`、授权文件权限正确，以及当前服务确实为新版 Dropbear。密码登录保留，可用于修复授权文件。

## 状态、恢复与启动保护

```sh
sh /data/router-ssh-modern/fix-router-ssh-modern.sh status
sh /data/router-ssh-modern/fix-router-ssh-modern.sh restore
```

恢复可能中断当前 SSH 连接；原端口、密码、RSA 密钥与新程序/密钥备份均保留。恢复后的原厂服务重新只提供原有算法。若启动脚本有其他修改，恢复会拒绝覆盖，需先人工核对。

备份目录 `/data/router-ssh-modern/` 包含原始与已管理的启动脚本、原配置副本、程序和新密钥，应保留。若启动时新版程序或新密钥不可用，启动脚本选回原厂 Dropbear，保留原有登录入口。原来的 `ssh_en` 条件、procd 管理与启停方式不变。当前没有重启路由器，开机分支通过本地隔离测试验证。

## 验证与构建

三种主机算法均在回环候选端口和正式端口使用原密码登录成功，公钥通过原可信连接核对。原 RSA 密钥及配置摘要不变。五项本地 BusyBox 检查覆盖未验证候选禁止切换、未确认自动回退、新连接确认要求、拒绝覆盖后续修改，以及持久材料缺失时的开机回退。测试代码仅保留本地，不提交 GitHub。

在 x86_64 Linux/WSL 中重建：

```sh
sh ssh-modern/build-router-ssh-modern.sh build
```

在源码仓库根目录执行上述命令。构建工具下载固定版本的官方源码和 Zig 0.14.1，按固定 SHA-256 核验，编译为 `aarch64-linux-musl` 静态程序。缓存位于仓库根目录的本地 `.tools/ssh-modern/`，中间构建位于 `/tmp/ax9000-ssh-build-*`，安装包及归档 SHA-256 输出至根目录 `dist/`。`package` 子命令可重新打包已构建程序，并写入该次程序的校验值。

源码 SHA-256：`e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81`。
编译器归档 SHA-256：`24aeeec8af16c381934a6cd7d95c807a8cb2cf7df9fa40d359aa884195c4716c`。

安装包不含密码、私钥、设备授权公钥、配置副本或本地测试。

[仓库主页](https://github.com/daixu0502/xiaomi_router_AX9000_docker-fix)
