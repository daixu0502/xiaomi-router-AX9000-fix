# 1.0.168 Docker 镜像代理

独立上传并执行 `docker-mihomo-proxy.sh`，沿用 1.0.140 的两种运行方式。目标为 **AX9000 / RA70 原厂稳定版 1.0.168**，仅控制 dockerd 拉取镜像使用的 HTTP 代理。

当前脚本 **1.0.3**：兼容 Docker 恢复工具 1.1.5；保留 1.0.1 的证书路径修复。修复原厂 curl 默认未加载可用系统 CA 时的 `curl: (60)` 错误；托管与非托管模式均显式使用系统证书包，TLS 验证保持开启。

## 下载与使用

下载 [单文件脚本](../../dist/1.0.168/docker-mihomo-proxy-1.0.168-v1.0.3.sh) 和 [SHA-256](../../dist/1.0.168/docker-mihomo-proxy-1.0.168-v1.0.3.sh.sha256)，核对后上传到路由器，在 root SSH 会话执行。也可直接使用本目录源码。

```sh
sh docker-mihomo-proxy.sh status
sh docker-mihomo-proxy.sh on http://10.31.0.66:7890
sh docker-mihomo-proxy.sh off

# 仅保存配置，当前 Docker 不重启
sh docker-mihomo-proxy.sh on --no-restart http://10.31.0.66:7890
sh docker-mihomo-proxy.sh off --no-restart
```

下载脚本的文件名含版本号时，将命令中的文件名换成实际名称。默认代理为 `http://10.31.0.66:7890`，可替换为实际 `http://IPv4:端口`。Mihomo 需允许路由器访问。开启前测试经代理连接 Docker Hub；连接、TLS 或 HTTP 状态不符合预期时，不改变代理配置。

`on/off` 默认重启 Docker，会短暂中断容器；记录切换前运行的容器并尝试恢复，已经停止的容器不加入恢复清单。`--no-restart` 只保存下次启动配置。`status` 分别显示保存配置与当前 Docker 报告的实际代理。

## curl 证书错误 60

真机对照确认：原厂系统 CA 包本身可验证 Docker Hub，但 curl 默认路径可能没有加载它。1.0.1 起，在未指定自定义证书环境时，自动设置 `CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt`；已有 `CURL_CA_BUNDLE`、`SSL_CERT_FILE` 或 `SSL_CERT_DIR` 时保留调用者设置。此环境会传入托管后端，原厂证书文件不需要替换。

使用旧脚本时可临时明确指定证书路径：

```sh
CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
  sh docker-mihomo-proxy.sh on http://10.31.0.66:7890
```

如仍失败，先核对路由器时间和自定义证书环境，再用相同 CA 路径测试代理；`401` 是镜像仓库要求认证的正常响应：

```sh
curl --cacert /etc/ssl/certs/ca-certificates.crt --noproxy '' \
  -x http://10.31.0.66:7890 -sS -o /dev/null -w '%{http_code}\n' \
  https://registry-1.docker.io/v2/
```

脚本不会关闭 TLS 校验或设置不安全镜像仓库。`CURL_CA_BUNDLE` 的用途见 [curl 官方证书说明](https://curl.se/docs/sslcerts.html)。

## 两种运行方式

- **已安装 [Docker 与自启修复 1.1.0 / 1.1.1 / 1.1.2 / 1.1.3 / 1.1.4 / 1.1.5](../docker/README.md)**：独立脚本自动调用 `/data/router-docker-1.0.168/runtime/proxy.sh`，代理配置位于 `/data/router-docker-1.0.168/proxy.env`，统一通过 procd 启停。运行文件摘要保持不变；代理配置按白名单读取，不作为 Shell 代码执行。
- **未安装自启修复**：仅接受已核对的开发版原厂 `mi_docker` 移植脚本或本工具此前生成的结果，检查两处 dockerd 命令、程序路径及运行参数，备份后修改；切换启动失败时尝试恢复旧配置和 Docker。**刚刷好的原版 1.0.168 没有完整 Docker 服务，须先部署 Docker，代理脚本不会凭空安装引擎。**

托管模式接受核心 1.1.0 / 1.1.1 / 1.1.2 / 1.1.3 / 1.1.4 / 1.1.5；检测到 1.0.0 时提示先执行核心 `upgrade`，不会绕过托管去修改启动文件。没有安装托管工具时，无参数运行提供交互菜单；托管模式无参数显示状态。

## 配置、回退与注意事项

托管模式将上次代理配置保留为 `/data/router-docker-1.0.168/proxy.before.*`。正常关闭使用 `off`，不覆盖服务脚本。新配置启动失败时，通过 procd 停止本次实例，恢复旧配置并尝试恢复原来运行的容器；若实例未退出则停止恢复流程，不强杀、不启动第二个 dockerd。日志见 `logread -e router-docker168`。

未托管模式的上一版启动脚本为 `/data/docker-mihomo-proxy-toggle-1.0.168/mi_docker.previous`，记录和运行环境在同一受保护目录，日志为 `/tmp/docker-mihomo-proxy-toggle-1.0.168.log`。未知文件、其他固件和额外 daemon 参数会被拒绝。

不修改全局代理、NAS 配置、路由和容器内应用代理。配置不支持域名、IPv6 或带认证信息的代理地址。代理服务应能访问镜像仓库，但代理暂时不可用不会被当作 Docker API 启动故障；就绪检查只使用本地 Unix socket。

23 项相关隔离检查通过。已在 1.0.168 真机验证代理开启、Docker Hub TLS 校验、对已有固定摘要镜像执行 `docker pull` 返回 up to date，以及运行中容器恢复；原厂 CA 文件保持原内容。尚未验收空缓存完整拉取和整机重启恢复。备份和设备配置不进入源码或分发包。

[返回 1.0.168](../README.md)
