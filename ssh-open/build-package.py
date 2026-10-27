"""Build the WSL SSH opener from this workspace; tests and device data excluded."""
import gzip
import hashlib
import io
from pathlib import Path
import tarfile

ROOT = Path(__file__).resolve().parent
VERSION = "1.0.0"
FILES = ("open-ssh-wsl.sh", "open_ssh.py", "router-open-ssh.sh", "README.md", "SOURCES.md")


def build():
    target = ROOT.parent / "dist/common" / ("router-ssh-open-wsl-v" + VERSION + ".tar.gz")
    target.parent.mkdir(parents=True, exist_ok=True)
    contents = {name: (ROOT / name).read_bytes().replace(b"\r\n", b"\n") for name in FILES}
    # Repository-relative documentation links also work in the standalone archive.
    contents["README.md"] = contents["README.md"].replace(
        b"](../", b"](https://github.com/daixu0502/xiaomi-router-AX9000-fix/blob/main/")
    contents["SHA256SUMS"] = "".join(
        hashlib.sha256(data).hexdigest() + "  " + name + "\n"
        for name, data in contents.items()).encode("ascii")
    with target.open("wb") as output, gzip.GzipFile(filename="", fileobj=output, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w") as archive:
            for name, data in contents.items():
                info = tarfile.TarInfo("router-ssh-open-wsl/" + name)
                info.size = len(data)
                info.mode = 0o755 if name.endswith((".py", ".sh")) else 0o644
                info.mtime = 0
                archive.addfile(info, io.BytesIO(data))
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    target.with_name(target.name + ".sha256").write_text(digest + "  " + target.name + "\n", encoding="ascii")
    print(target.name, target.stat().st_size, digest)


if __name__ == "__main__":
    build()
