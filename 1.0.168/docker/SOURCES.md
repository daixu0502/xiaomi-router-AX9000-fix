# 组件来源与固定摘要

核对日期：2026-10-27。本工具独立实现部署、cgroup 补齐、procd 托管和 LuCI API。页面、CSS 和安装示意图来自用户提供的原厂开发版 ROM；页头基于用户提供的原厂稳定版 ROM，仅增加 Docker 导航。保留原厂样式，修改 API 路径、磁盘说明、第三方管理提示和停用语义。

| 组件 | 来源 |
| --- | --- |
| Docker 页面/CSS/示意图 | `miwifi_ra70_all_develop_1.0.140.bin` |
| 稳定版页头 | `miwifi_ra70_firmware_cc424_1.0.168.bin`，原文件 MD5 `9678b0beb974771986b1d6df3ef7dbc8` |
| Docker ARM64 程序 | [小米 CDN 固定地址](https://cdn.cnbj1.fds.api.mi-img.com/opensource/AX9000-stable-firmware/docker/docker-19.03.15-ce.tgz) |

Docker 包 SHA-256：`030359d3cc1aac326409c6c37cc2ef5c1b9e5f1ddf97d722f5b8ab2cfa711d13`。本地下载后，八个程序的 MD5 均与开发版 `/etc/init.d/mi_docker` 内的常量一致。安装同时校验压缩包 SHA-256 和解包程序摘要。每个部署文件的 SHA-256 位于 `payload/SHA256SUMS`。

| 文件 | 原厂 MD5 |
| --- | --- |
| containerd | `235fa0fb58ba77823a94fed6c1326956` |
| containerd-shim | `8af168bd148c238415bb5ace6f71d47e` |
| ctr | `e78943af421a291839c080370bf41ad6` |
| docker | `a8523af0f057113d60743a459cedf8b6` |
| docker-init | `6a32bd7aa96f8bf145444d98871e2ce0` |
| docker-proxy | `454a3aca9c22c178679dd349ab7084ea` |
| dockerd | `00ce99e358584f046c6d9aada7f65146` |
| runc | `c08c14d59908856a54416d369052e1ba` |

厂商包名和 Docker CLI 显示 19.03.15，但 dockerd 为厂商 `dev` 构建，不能描述为未经修改的上游 19.03.15。离线包包含原厂程序，不含容器镜像、Portainer 镜像、原厂 ROM、用户数据或凭据。

[Docker 官方二进制安装文档](https://docs.docker.com/engine/install/binaries/)要求正确挂载 cgroupfs，并通过实际容器验证；一般内核版本条件不能替代本设备的运行验收。当前不据此推断新版引擎的兼容上限。
