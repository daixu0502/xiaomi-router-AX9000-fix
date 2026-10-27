#!/usr/bin/env python3
"""Offline U-Boot Bdata CRC and field comparison. Never print device secrets."""
import argparse
import binascii
from pathlib import Path
import sys


def read_env(path):
    data = Path(path).read_bytes()
    if not 1024 < len(data) <= 16777216 or len(data) % 1024:
        raise ValueError("Bdata 大小不符合预期。")
    stored = int.from_bytes(data[:4], "little")
    crc = 0
    previous = 4
    valid = None
    for end in range(1024, len(data) + 1, 1024):
        crc = binascii.crc32(data[previous:end], crc)
        previous = end
        if crc == stored:
            valid = end
            break
    if valid is None:
        raise ValueError("Bdata CRC32 不匹配；拒绝继续固化。")
    end = data.find(b"\0\0", 4, valid)
    if end <= 4:
        raise ValueError("无法识别 Bdata 环境记录。")
    fields = {}
    for record in data[4:end].split(b"\0"):
        key, separator, value = record.partition(b"=")
        if not key or key in fields:
            raise ValueError("Bdata 有空字段或重复字段。")
        fields[key] = value if separator else None
    return fields, valid, data


def compare(before, after):
    old, old_size, old_data = read_env(before)
    new, new_size, new_data = read_env(after)
    if len(old_data) != len(new_data) or old_size != new_size:
        raise ValueError("写后 Bdata 长度或 CRC 范围改变。")
    expected = dict(old)
    expected[b"ssh_en"] = b"1"
    expected[b"telnet_en"] = b"1"
    if new != expected:
        raise ValueError("写后 Bdata 存在非预期字段变化；保留备份，勿自动刷回分区。")
    if old_data[old_size:] != new_data[new_size:]:
        raise ValueError("环境记录之外的分区数据改变。")
    return old_size


def main():
    parser = argparse.ArgumentParser(description="离线核对 Bdata CRC，只允许 SSH/Telnet 两个开关变化")
    parser.add_argument("before")
    parser.add_argument("after", nargs="?")
    args = parser.parse_args()
    if args.after:
        compare(args.before, args.after)
        print("BDATA_CRC_AND_FIELDS_OK=1")
    else:
        read_env(args.before)
        print("BDATA_BACKUP_CRC_OK=1")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as exc:
        print("错误：{}".format(exc), file=sys.stderr)
        sys.exit(1)
