# 小米 AX9000 原厂稳定版 1.0.168 修复工具

[返回仓库首页](../README.md) · [开发版 1.0.140 工具](../1.0.140/README.md)

## 针对的原厂固件

| 项目 | 已核对信息 |
| --- | --- |
| 设备 | 小米路由器 AX9000 |
| 硬件标识 | `RA70` |
| 原厂 ROM 版本 | **`1.0.168`** |
| 发行类型 | 原厂稳定版 |
| 固件构建时间 | `2023-01-30 10:28:49 UTC` |

## 功能导航

| 功能 | 说明 | 脚本 |
| --- | --- | --- |
| WAN 页面 MAC 空值 | [使用与恢复](web-wan-mac/README.md) | `web-wan-mac/fix-router-web-mac.sh` |
| `/16` DHCP 保存错误 | [使用与恢复](web-dhcp/README.md) | `web-dhcp/fix-router-dhcp16-web.sh` |
| Docker 服务与原厂页面恢复 | [部署与回退](docker/README.md) | `docker/install-router-docker.sh` |
| Docker 镜像代理 | [两种运行方式](docker-proxy/README.md) | `docker-proxy/docker-mihomo-proxy.sh` |
| SSH 综合工具（两版共用） | [使用教程与注意事项](../ssh/README.md) | `ssh/ssh.sh`；新增固化待实机验证 |

MAC 与 DHCP 修复通过 SSH 在路由器上以 root 执行。`status` 只检查；`apply`（无参数时的默认动作）安装补丁；`restore` 恢复对应备份。安装和恢复不改写 DHCP/网络配置，也不重启服务。DHCP 在页面提交时保存配置，并沿用原厂 DNS 服务重启和设备重启行为。

Docker 部署使用独立安装目录和离线包，默认动作为 `status`；`apply --disk 挂载点` 准备程序与原厂页面，`--start` 才明确要求安装后启动。需要刷原版后已恢复 root SSH 和 ext4 USB 盘，尚待 1.0.168 真机容器与浏览器验收；详见 [Docker 说明](docker/README.md)。

本版 DHCP 修复仅处理 `/16`：原厂 1.0.168 已修正 `/24` 的七参数错配；新补丁把正常 `/24` 和关闭 DHCP 请求交给原厂函数，不替换其余 API。

验证使用本地 1.0.168 原模板、原厂字节码和原生 Lua VM，在低权限进程中模拟 UCI/服务操作，并验证安装器的备份、恢复、版本保护和幂等性。尚未在实际运行 1.0.168 的浏览器页面上做端到端回归，也未安装到在线路由器。详见[问题分析](docs/ax9000-1.0.168-dhcp-mac-check.md)。

## 分析文档

- [DHCP 与 WAN MAC 问题核对](docs/ax9000-1.0.168-dhcp-mac-check.md)
- [Docker 移植可行性](docs/ax9000-1.0.168-docker-feasibility.md)
- [自定义固件签名与刷入边界](docs/ax9000-custom-firmware-verification.md)

两版共用 SSH 文档随工具保存在 [ssh/docs](../ssh/docs/ssh-common-compatibility.md)。
