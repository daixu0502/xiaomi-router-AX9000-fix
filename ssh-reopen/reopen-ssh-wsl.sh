#!/usr/bin/env bash
# Run on the WSL/Linux computer, not on the router.
set -euo pipefail
script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
command -v python3 >/dev/null 2>&1 || { echo '缺少 python3，请安装：sudo apt install python3' >&2; exit 1; }
exec python3 "$script_dir/reopen_ssh.py" "$@"
