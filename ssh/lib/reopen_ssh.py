#!/usr/bin/env python3
"""AX9000 hard-persisted SSH: Telnet recovery using Python's standard library."""

import argparse
import getpass
from pathlib import Path
import re
import secrets
import shlex
import shutil
import socket
import subprocess
import sys
import time


class RecoveryError(Exception):
    pass


class Telnet:
    """Small NVT client; supports split IAC/options/subnegotiation, no telnetlib."""

    def __init__(self, host, port, timeout):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        self.timeout = timeout
        self.buffer = b""
        self.state = "data"
        self.option_command = None

    def close(self):
        self.sock.close()

    def send(self, value):
        self.sock.sendall(value.replace(b"\xff", b"\xff\xff"))

    def line(self, value):
        self.send(value.encode("utf-8") + b"\r\n")

    def decode(self, chunk):
        result = bytearray()
        for value in chunk:
            if self.state == "data":
                if value == 255:
                    self.state = "iac"
                elif value != 0:  # CR NUL is the NVT encoding of a bare CR.
                    result.append(value)
            elif self.state == "iac":
                if value == 255:
                    result.append(value)
                    self.state = "data"
                elif value in (251, 252, 253, 254):
                    self.option_command = value
                    self.state = "option"
                elif value == 250:
                    self.state = "sub"
                else:
                    self.state = "data"
            elif self.state == "option":
                if self.option_command == 251:  # WILL: accept echo / suppress GA.
                    answer = 253 if value in (1, 3) else 254
                    self.sock.sendall(bytes((255, answer, value)))
                elif self.option_command == 253:  # DO: no local options.
                    self.sock.sendall(bytes((255, 252, value)))
                self.state = "data"
            elif self.state == "sub":
                if value == 255:
                    self.state = "sub_iac"
            elif self.state == "sub_iac":
                self.state = "data" if value == 240 else "sub"
        return bytes(result)

    def expect(self, patterns, timeout=None):
        deadline = time.monotonic() + (self.timeout if timeout is None else timeout)
        while True:
            for index, pattern in enumerate(patterns):
                match = re.search(pattern, self.buffer)
                if match:
                    output = self.buffer[:match.end()]
                    self.buffer = self.buffer[match.end():]
                    return index, match, output
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RecoveryError("等待 Telnet 响应超时；请检查登录提示或通过 Telnet 手动核对状态。")
            self.sock.settimeout(remaining)
            try:
                chunk = self.sock.recv(4096)
            except socket.timeout as exc:
                raise RecoveryError("等待 Telnet 响应超时。") from exc
            if not chunk:
                raise RecoveryError("Telnet 连接已关闭；路由器上的操作可能已执行，请先核对状态。")
            self.buffer += self.decode(chunk)
            if len(self.buffer) > 1024 * 1024:
                raise RecoveryError("Telnet 响应过长，停止处理。")

    def run(self, script, timeout=None):
        token = "SSH_REOPEN_" + secrets.token_hex(12)
        # Splitting the marker prevents echoed commands from matching completion.
        command = "sh -c " + shlex.quote(script)
        command += "; _reopen_rc=$?; printf '\\n%s%s:%s\\n' 'SSH_REOPEN_' "
        command += shlex.quote(token[len("SSH_REOPEN_"):]) + ' "$_reopen_rc"'
        self.line(command)
        _, match, output = self.expect(
            [rb"(?m)^" + token.encode() + rb":([0-9]+)\r?$"], timeout
        )
        text = output[:match.start()].decode("utf-8", "replace").strip()
        if int(match.group(1)) != 0:
            raise RecoveryError("路由器命令失败：\n" + text)
        return text


SHELL = rb"(?m)^[^\r\n]*[#$][ \t]*\r?$"
PASSWORD = "(?i)(?:password|密码)[^\\r\\n:：]*[:：][ \\t]*$".encode("utf-8")


def login(client):
    index, _, _ = client.expect([
        rb"(?im)(?:^|\n)[^\r\n]*(?:login|username):[ \t]*$",
        PASSWORD,
        SHELL,
    ])
    if index == 0:
        client.line("root")
        index, _, _ = client.expect([PASSWORD, SHELL])
        needs_password = index == 0
    else:
        needs_password = index == 1
    if needs_password:
        print("初始密码：用路由器 SN 在 https://miwifi.dev/ssh 计算；改过密码则用当前密码。")
        password = getpass.getpass("Telnet root 密码：")
        if any(ord(c) < 32 or ord(c) == 127 for c in password):
            raise RecoveryError("密码含控制字符，无法通过 Telnet 终端安全输入。")
        client.line(password)
        del password
        index, _, _ = client.expect([
            rb"(?i)(?:login incorrect|login failed|incorrect password)",
            rb"(?im)(?:^|\n)[^\r\n]*login:[ \t]*$",
            PASSWORD,
            SHELL,
        ])
        if index != 3:
            raise RecoveryError("Telnet 登录失败。未尝试改密或启动 SSH。")
    # Turn off terminal echo before transmitting scripts; do not store new history.
    client.run("stty -echo; [ \"$(id -u)\" = 0 ]", timeout=10)
    client.line("HISTFILE=/dev/null; HISTSIZE=0; export HISTFILE HISTSIZE")


def change_password(client):
    first = getpass.getpass("新的 root 密码（同时影响 SSH/Telnet）：")
    second = getpass.getpass("再次输入新密码：")
    if first != second or not first or any(ord(c) < 32 or ord(c) == 127 for c in first):
        raise RecoveryError("新密码为空、包含控制字符或两次不一致；未修改密码。")
    token = "PASSWD_DONE_" + secrets.token_hex(12)
    client.line("passwd root; _reopen_rc=$?; printf '\\n%s%s:%s\\n' 'PASSWD_DONE_' "
                + shlex.quote(token[len("PASSWD_DONE_"):]) + ' "$_reopen_rc"')
    done = rb"(?m)^" + token.encode() + rb":([0-9]+)\r?$"
    for password in (first, second):
        index, _, _ = client.expect([PASSWORD, done])
        if index != 0:
            raise RecoveryError("passwd 提前退出；密码状态需通过 Telnet 核对。")
        client.line(password)
    _, match, _ = client.expect([done])
    if int(match.group(1)) != 0:
        raise RecoveryError("passwd 返回失败；请通过 Telnet 核对密码状态。")
    print("root 密码已更新。")


def ssh_banner(host, port, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=2) as connection:
                connection.settimeout(2)
                received = b""
                while len(received) < 8192:
                    chunk = connection.recv(512)
                    if not chunk:
                        break
                    received += chunk
                    if re.search(rb"(?m)^SSH-2\.0-[^\r\n]+\r?\n", received):
                        return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def port_number(value):
    number = int(value)
    if not 1 <= number <= 65535:
        raise argparse.ArgumentTypeError("端口范围必须是 1–65535")
    return number


def main():
    parser = argparse.ArgumentParser(description="AX9000 已硬固化 SSH：通过 Telnet 执行教程第八步。")
    parser.add_argument("host", nargs="?", default="192.168.31.1", help="路由器 LAN 地址（默认 192.168.31.1）")
    parser.add_argument("--telnet-port", type=port_number, default=23)
    parser.add_argument("--ssh-port", type=port_number, help="指定探测/验证端口；不修改路由器端口配置")
    parser.add_argument("--set-password", action="store_true", help="交互修改 root 密码，默认保留")
    parser.add_argument("--skip-ssh-login", action="store_true", help="仅验证 SSH 协议响应，不做 root 登录验证")
    args = parser.parse_args()
    if args.host.startswith("-") or any(c.isspace() for c in args.host) or any(c in args.host for c in "@/\\"):
        parser.error("请输入主机名或 IP 地址，不含用户名、端口或 URL。")
    if not sys.stdin.isatty():
        raise RecoveryError("请从交互终端运行，以便安全输入密码。")
    if not args.skip_ssh_login and shutil.which("ssh") is None:
        raise RecoveryError("缺少 ssh；请先运行 sudo apt install openssh-client。")
    print(f"连接 {args.host}:{args.telnet_port}（Telnet 明文传输，请使用可信 LAN）。")
    client = Telnet(args.host, args.telnet_port, 20)
    changed = False
    try:
        login(client)
        print("Telnet root 登录成功，开始检查并开启 SSH。")
        payload = Path(__file__).with_name("router-enable-ssh.sh").read_text(encoding="utf-8")
        output = client.run(payload, timeout=60)
        changed = True
        print(output)
        if "ENABLE_DONE=1" not in output:
            raise RecoveryError("缺少完成标记，请通过 Telnet 核对状态。")
        if args.set_password:
            change_password(client)
        else:
            print("保留现有 root 密码。")
        ports = [args.ssh_port] if args.ssh_port else list(dict.fromkeys(
            int(value) for value in re.findall(r"(?m)^PORT=([0-9]+)\r?$", output)
            if 1 <= int(value) <= 65535
        ))
        port = next((p for p in ports if ssh_banner(args.host, p, 8)), None)
        if port is None:
            raise RecoveryError(f"未从端口 {ports} 收到 SSH 响应。请通过 Telnet 检查 Dropbear/防火墙；修改不会自动撤销。")
        print(f"已收到 {args.host}:{port} 的 SSH-2.0 响应。")
        command = ["ssh", "-p", str(port), "-o", "ConnectTimeout=10",
                   "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa",
                   f"root@{args.host}", "test \"$(id -u)\" = 0 && printf 'SSH_ROOT_OK\\n'"]
        if args.skip_ssh_login:
            print("已跳过 root 登录验证；端口响应不能证明密码登录成功。")
            print("手动验证：" + shlex.join(command))
        else:
            print("现在验证 SSH root 登录；请核对主机指纹，并按需再次输入 root 密码。", flush=True)
            if subprocess.call(command) != 0:
                raise RecoveryError("SSH root 登录验证失败。启动脚本/已成功的改密仍保留，请用 Telnet 排查。")
            print("完成：SSH root 登录验证成功。")
    except (RecoveryError, OSError, KeyboardInterrupt):
        if changed:
            print("SSH 开启命令已完成；后续失败不会自动恢复启动脚本或密码。", file=sys.stderr)
        raise
    finally:
        try:
            client.line("exit")
        except OSError:
            pass
        client.close()


if __name__ == "__main__":
    try:
        main()
    except (RecoveryError, OSError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\n已中止；若已开始修改，请通过 Telnet 核对状态。", file=sys.stderr)
        sys.exit(130)
