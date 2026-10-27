# AX9000 自定义集成固件的校验与刷入可行性

核对日期：2026-10-26。使用本地两份原厂 ROM，并通过现有 SSH 对目标路由器做只读核对。本次未执行上传改包、擦除、刷写、改启动标志或重启。

## 结论

**原厂有固件验证，而且包含 RSA 数字签名。修改原包后只重算 CRC，不能通过未修改的原厂验签。** 当前已 root 的国行设备具有另一条可行路径：生成符合原厂布局的自定义 UBI 系统镜像，通过专用 root 刷写流程写入非当前系统分区。该路径仍需镜像构建、容量检查、备份、读回验证及首次启动验证，不能把本次检查等同于“已验证某个改包可启动”。

优先候选方案是保留 1.0.168 的内核、设备树、驱动和 Bootloader，仅修改 SquashFS 用户空间并重建 UBI；在原厂文件系统布局内增加 Docker 服务、初始化和管理组件。引擎及容器数据优先保留在外接 ext4 磁盘。

## 1. 原厂升级流程确实先验包

两份 ROM 中的 `/bin/flash.sh` 都在停止服务和写入系统前调用：

```sh
mkxqimage -v "$1"
```

返回非零时进入 `Check Failed!!!` 分支并退出。稳定版的 `/bin/mkxqimage` 是 ARM64 ELF，包含以下实际依赖、调用符号与错误信息：

- `libcrypto.so.1.0.0`
- `PEM_read_RSA_PUBKEY`、`EVP_sha1`、`EVP_VerifyFinal`
- `/usr/share/xiaoqiang/public.pem`
- `Model mismatch`
- `Image checksum is invalid`
- `Image verify failed, not formal image`

因此除了封装和机型检查，还存在签名验证，不是仅靠文件名、MD5 或 CRC 判断。

已通过设备上 `/bin/mkxqimage` 的 MD5 `7a0b981f31f2a6c466fb2cdffe5ce377` 确认，当前路由器使用的是本地开发版中的对应程序；稳定版程序 MD5 为 `0f7e2194b402b20d047d64a4bbd2e9f7`。两者不能假定为同一个二进制。

## 2. 在电脑上完成了签名正反验证

两份 ROM 均采用 `HDR1` 外层封装。末尾签名块为 272 字节，包含 16 字节块头和 256 字节签名。使用固件内的公开密钥恢复 PKCS#1 v1.5 DigestInfo，并用 OpenSSL 验证，确认算法为 RSA-2048/SHA-1。

| 检查 | 开发版 1.0.140 | 稳定版 1.0.168 |
| --- | --- | --- |
| 原包 JAMCRC | 通过 | 通过 |
| 原包 RSA 签名 | 通过 | 通过 |
| 在内存中改变 root.ubi 中一个字节，重算 JAMCRC | CRC 通过 | CRC 通过 |
| 上述变更后的 RSA 签名 | 失败 | 失败 |

签名数据范围为文件偏移 `[12, sign_offset)`，覆盖机型、分段表、版本数据及完整 `root.ubi`。JAMCRC 覆盖 `[12, EOF)`。原包签名偏移分别为：开发版 `44732680`；稳定版 `44696244`。

改动实验只在电脑内存中进行，未保存可刷写改包，也未上传设备。原始文件保持不变。

固件内只有用于验证的公开密钥。本次没有厂商签名私钥，因此不能为改包生成原厂信任的签名。替换改包里的公钥，也不能改变当前运行系统在验包时使用的信任密钥。

## 3. 当前实机的启动与分区情况

只读 SSH 取得的结果：

| 项目 | 当前值 |
| --- | --- |
| ROM | RA70 开发版 1.0.140 |
| 内核 | Linux 4.4.60 / aarch64 |
| `flag_boot_rootfs` | `1` |
| 启动参数 | `ubi.mtd=rootfs_1 root=mtd:ubi_rootfs rootfstype=squashfs rootwait uart_en=1 swiotlb=1 coherent_pool=2M` |
| `mtd21` | `rootfs`，`0x03800000`，56 MiB |
| `mtd22` | `rootfs_1`，`0x03800000`，56 MiB |
| NAND 擦除块 | `0x20000`，128 KiB |
| 当前系统 UBI 卷 | `kernel`、`ubi_rootfs`、`rootfs_data` |
| `/sys/devices/system/qfprom/qfprom0/authenticate` | `0`（带字符串终止符） |

按该平台公开实现，`authenticate` 首字符为 `0` 表示认证检查未开启。这是支持自定义镜像启动的证据，不能外推到所有国行、国际版或其他设备。公开实现参考：[Qualcomm 平台 sysupgrade 认证检查代码](https://nest-open-source.googlesource.com/manifest_repos/bootloader/+/refs/heads/main/tools/sysupgrade.c)。

当前 U-Boot 的字符串同时含有“安全启动熔丝启用/未启用”两条消息，仅看到这些字符串不能证明功能已启用；这里以实机状态接口为判断依据。

## 4. 内层 FIT 与根文件系统校验

两份原厂内核卷的 FIT 均含内核和设备树的 CRC32/SHA-1 哈希，没有发现 FIT `signature` 节点。每份共核对 50 个 hash 节点，全部匹配；SquashFS 根文件系统不在该内核 FIT 中。

两版内核配置均为 `# CONFIG_DM_VERITY is not set`。当前启动参数直接挂载 UBI 上的 SquashFS，没有 dm-verity 参数。因此目前没有发现针对整个 SquashFS 的 dm-verity 验证链。

这支持“保留原内核 FIT，只修改根文件系统”的方案，但不代替对自定义镜像的实机首次启动验证，也不表示整个 Bootloader 的所有路径均已反汇编审计。

## 5. 不同入口的结论

| 刷入入口 | 本次结论 |
| --- | --- |
| 未修改的原厂升级流程 | 改包签名失效，会被原厂验签拒绝 |
| root 下仍调用原厂 `/bin/flash.sh` | 仍先执行 `mkxqimage -v`，root 身份不会自动跳过 |
| root 专用 UBI 写入流程 | 有可行基础；需要按实机非当前分区、镜像容量与启动状态设计，尚未执行 |
| 修改运行系统的验签程序 | 技术上属于另一条路线，本次没有制作补丁或验证，不作为首选 |
| 原厂救砖/TFTP 入口 | 未单独验证其认证规则，不能假定接受改包 |
| U-Boot 下刷入 | 未进入或修改 U-Boot，不宣称已验证 |

原厂 `/lib/upgrade/libupgrade.sh` 的 `do_flash_firmware()` 根据 `flag_boot_rootfs` 选择另一个系统分区，并通过 `ubiformat` 写 `root.ubi`。当前非活动系统分区为 `mtd21`，该编号只代表本次读取时的状态；执行前必须重新核对，不能将其作为固定刷写编号。

`HDR1 .bin` 是升级包，`root.ubi` 是里面的系统分段，不能将完整 `.bin` 当作原始 UBI 分段直接写入。

## 6. 制作集成版本时的具体约束

- 稳定版原包仅含 `xiaoqiang_version` 和 `root.ubi`，没有 `uboot.bin`。开发版另含 `uboot.bin`；不应为了 Docker 移植把开发版 Bootloader 一并带入。
- `root.ubi` 原始大小为 42.625 MiB；物理系统分区为 56 MiB。重建时还需为 UBI 元数据、坏块预留和可写卷留空间，不能只按 SquashFS 文件大小判断是否装得下。
- 优先只集成启动、管理和安装组件，Docker 引擎与容器数据继续外置，避免挤占系统卷和可写空间。
- 保留当前可用系统、独立 SSH 恢复材料和原容器数据，首次验证使用另一系统分区，不以同时覆盖双系统作为默认流程。
- 后续官方 OTA 可以覆盖自定义系统，配置及 root 的保留需独立设计。
- 本机原厂通用 `/sbin/sysupgrade -T` 的平台检查存在失败后调用 `reboot` 的分支，因此本次没有在设备上运行该“测试”入口。不能把标准 OpenWrt 文档中 `-T` 的无刷写描述，直接等同于本机该脚本无副作用。

原始分析与验证脚本保存在本仓库忽略目录 `.tools/rom-analysis/`：`check_signatures.py`、`signature-report.json`、`inspect_boot_metadata.py`、`boot-metadata.json`。没有提交或推送 GitHub。
