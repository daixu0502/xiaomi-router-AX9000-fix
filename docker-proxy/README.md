# Docker 镜像拉取代理

`docker-mihomo-proxy.sh` 开启、关闭或查询 Docker 服务的 HTTP 代理，适用于 AX9000 原厂 `mi_docker`。常见用途是让路由器通过 NAS 上的 Mihomo 下载镜像。

只控制 `dockerd` 自身的代理，不自动配置容器内应用的代理；不修改全局代理、路由或 NAS 配置。

## 使用

将脚本上传到路由器，使用 root 执行：

```sh
sh docker-mihomo-proxy.sh status
sh docker-mihomo-proxy.sh on http://10.31.0.66:7890
sh docker-mihomo-proxy.sh off

# 只保存配置，下次 Docker 启动后生效
sh docker-mihomo-proxy.sh on --no-restart http://10.31.0.66:7890
sh docker-mihomo-proxy.sh off --no-restart
```

默认代理为 `http://10.31.0.66:7890`，可替换为实际的 `http://IPv4:端口`。Mihomo 须允许路由器访问该局域网代理端口。未安装托管自启修复时，不带参数运行会显示交互菜单。

`on`、`off` 默认重启 Docker，会短暂中断容器，并尝试恢复原先运行的容器。`status` 同时显示下次启动配置与当前运行配置，便于判断 `--no-restart` 是否尚未生效。

## 两种运行方式

- 已安装 [Docker 自启修复](../docker-autostart/README.md)：自动执行 `/data/router-docker-autostart/proxy.sh`，配置位于该目录的 `proxy.env`，通过 procd 重启。
- 未安装自启修复：核对原厂两处已知 `dockerd` 启动命令，开启前测试代理访问 Docker Hub，备份并修改启动脚本；切换失败时尝试恢复旧配置和 Docker。

非托管方式的上一版启动脚本保存在 `/data/docker-mihomo-proxy-toggle/mi_docker.previous`，运行记录也在该受保护目录中，日志为 `/tmp/docker-mihomo-proxy-toggle.log`。未知启动结构或额外 Docker 参数会被拒绝，不能将脚本用于任意发行版。

普通关闭代理使用 `off`，不需要手动覆盖启动文件。若出现无法自动恢复的错误，请根据输出及对应目录中的备份人工核对。

[返回仓库说明](../README.md)
