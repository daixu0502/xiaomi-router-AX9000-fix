#!/usr/bin/env python3
"""Reproduce the only binary change to the pinned official XMiR module."""
import argparse
import hashlib
from pathlib import Path
import urllib.request

COMMIT = "16a46e350e3de2cb3415ab2cb652df53783998dc"
ORIGINAL_SHA = "a68353e1fa978c76f199b1f75f3be7fce63c7bac49ad4e82554a67f8687cd755"
PATCHED_SHA = "ac6f89aa6839b46b746320eaff54c0b11581f467e9cfdac9e4cb4fd195788de1"
ROOT = Path(__file__).resolve().parent


def patch_module(original):
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA:
        raise ValueError("Official input module checksum mismatch")
    start = original.index(b"\0vermagic=") + len(b"\0vermagic=")
    end = original.index(b"\0", start)
    magic = original[start:end]
    replacement = b"4.4.60" + magic[magic.index(b" "):]
    if b"-XMiR-Patcher" not in magic or len(replacement) > len(magic):
        raise ValueError("Unexpected vermagic")
    result = original[:start] + replacement.ljust(len(magic), b"\0") + original[end:]
    if hashlib.sha256(result).hexdigest() != PATCHED_SHA:
        raise ValueError("Patched module checksum mismatch")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="固定官方模块的 vermagic 适配；不代表内核 ABI 已经实机验证")
    parser.add_argument("--input", type=Path, help="已下载的官方原模块；省略则下载固定提交文件")
    args = parser.parse_args()
    if args.input:
        original = args.input.read_bytes()
    else:
        url = "https://raw.githubusercontent.com/openwrt-xiaomi/xmir-patcher/" + COMMIT + "/kmod/xmir_patcher-4.4-arm64-preempt.ko"
        with urllib.request.urlopen(url, timeout=30) as response:
            original = response.read(1048576)
    target = ROOT / "modules/xmir_patcher-4.4.60-arm64-preempt.ko"
    target.write_bytes(patch_module(original))
    print(target.name, PATCHED_SHA)
