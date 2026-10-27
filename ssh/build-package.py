#!/usr/bin/env python3
"""Build one SSH toolkit, excluding local tests, state and private material."""
import gzip
import hashlib
import io
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parent
VERSION = "2.0.0"
FILES = [
    "ssh.sh", "modern.sh", "persist.sh", "README.md", "build-package.py",
    "build-modern.sh", "build-module.py", "SOURCES.txt",
    "lib/open_ssh.py", "lib/reopen_ssh.py", "lib/router-open-ssh.sh",
    "lib/router-enable-ssh.sh", "lib/persist-boot.sh", "lib/remote.sh", "lib/verify_bdata.py",
    "bin/dropbear", "licenses/LICENSE.dropbear", "licenses/LICENSE.musl", "licenses/LICENSE.zig",
    "licenses/LICENSE.xmir-patcher", "licenses/localoptions.h",
    "modules/provenance.json", "modules/xmir_patcher-4.4.60-arm64-preempt.ko",
    "docs/ssh-common-compatibility.md",
    "vendor/kmod-xmir-patcher/src/xmir_patcher.c", "vendor/kmod-xmir-patcher/src/xmir_patcher.h",
    "vendor/kmod-xmir-patcher/src/Makefile", "vendor/kmod-xmir-patcher/src/Kconfig",
    "vendor/kmod-xmir-patcher/.github/workflows/build.yml",
    "vendor/kmod-xmir-patcher/kernel-4.4-arm64.config",
    "vendor/kmod-xmir-patcher/dependencies-ubuntu.txt",
]


def sums(content):
    return "".join(hashlib.sha256(data).hexdigest() + "  " + name + "\n" for name, data in sorted(content.items())).encode("ascii")


def build():
    content = {name: (ROOT / name).read_bytes() for name in FILES}
    assert hashlib.sha256(content["bin/dropbear"]).hexdigest() == "0707f2dc873a7a432eaa51b08b8e32e3109964b41dce82ce4657fb0d48ab0400"
    assert hashlib.md5(content["bin/dropbear"]).hexdigest().encode() in content["modern.sh"]
    assert hashlib.sha256(content["modules/xmir_patcher-4.4.60-arm64-preempt.ko"]).hexdigest().encode() in content["persist.sh"]
    assert re.findall(rb"^## (.+)$", content["README.md"], re.M) == [x.encode() for x in ("仓库说明", "使用教程", "注意事项")]
    for name, data in content.items():
        if name.endswith((".py", ".sh", ".md", ".txt")):
            assert b"\r" not in data, name
    (ROOT / "SHA256SUMS").write_bytes(sums(content))
    for name, data in list(content.items()):
        if name.endswith(".md"):
            depth = len(Path(name).parts) - 1
            prefix = b"](" + b"../" * (depth + 1)
            content[name] = data.replace(prefix, b"](https://github.com/daixu0502/xiaomi-router-AX9000-fix/blob/main/")
    content["SHA256SUMS"] = sums(content)
    target = ROOT.parent / "dist/common/router-ssh-v2.0.0.tar.gz"
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as output, gzip.GzipFile(filename="", fileobj=output, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            for name, data in sorted(content.items()):
                info = tarfile.TarInfo("router-ssh/" + name)
                info.size = len(data)
                info.mode = 0o755 if name.endswith((".py", ".sh")) or name == "bin/dropbear" else 0o644
                archive.addfile(info, io.BytesIO(data))
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_name(target.name + ".sha256").write_text(digest + "  " + target.name + "\n", encoding="ascii")
    print(target.name, target.stat().st_size, digest)


if __name__ == "__main__":
    build()
