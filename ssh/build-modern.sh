#!/bin/sh
# Run under Linux/WSL. Downloads only pinned official source/toolchain archives.
set -eu
FEATURE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$FEATURE_DIR/.." && pwd)
CACHE=$ROOT/.tools/ssh-modern
DIST=$ROOT/dist/common
VERSION=2026.94
SOURCE_SHA=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
ZIG_SHA=24aeeec8af16c381934a6cd7d95c807a8cb2cf7df9fa40d359aa884195c4716c
mkdir -p "$CACHE/downloads" "$CACHE/out" "$DIST"
fetch() {
    file=$1; url=$2; expected=$3
    [ -f "$file" ] || curl -fL --retry 2 -o "$file" "$url"
    printf '%s  %s\n' "$expected" "$file" | sha256sum -c -
}
if [ "${1:-build}" = build ]; then
    fetch "$CACHE/downloads/dropbear-$VERSION.tar.bz2" "https://matt.ucc.asn.au/dropbear/releases/dropbear-$VERSION.tar.bz2" "$SOURCE_SHA"
    fetch "$CACHE/downloads/zig-x86_64-linux-0.14.1.tar.xz" 'https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz' "$ZIG_SHA"
    BUILD=$(mktemp -d /tmp/ax9000-ssh-build-XXXXXX)
    printf '%s\n' "$BUILD" > "$CACHE/latest-build-dir.txt"
    tar -xjf "$CACHE/downloads/dropbear-$VERSION.tar.bz2" -C "$BUILD"
    tar -xJf "$CACHE/downloads/zig-x86_64-linux-0.14.1.tar.xz" -C "$BUILD"
    cat > "$BUILD/cc" <<EOF
#!/bin/sh
exec "$BUILD/zig-x86_64-linux-0.14.1/zig" cc -target aarch64-linux-musl "\$@"
EOF
    chmod 0755 "$BUILD/cc"
    export ZIG_GLOBAL_CACHE_DIR=$BUILD/zig-cache
    cd "$BUILD/dropbear-$VERSION"
    cat > localoptions.h <<'OPTIONS'
#define DROPBEAR_RSA_SHA1 0
#define DROPBEAR_DSS 0
#define DROPBEAR_ED25519 1
#define DROPBEAR_ECDSA 1
#define DROPBEAR_DH_GROUP1 0
#define DROPBEAR_DH_GROUP14_SHA1 0
#define DROPBEAR_SHA1_HMAC 0
#define DROPBEAR_SHA1_96_HMAC 0
#define DROPBEAR_X11FWD 0
#define DROPBEAR_SVR_LOCALSTREAMFWD 0
#define DEFAULT_PATH "/usr/sbin:/usr/bin:/sbin:/bin"
OPTIONS
    CC="$BUILD/cc" CFLAGS='-Os' LDFLAGS='-static' ./configure \
        --host=aarch64-linux-musl --enable-static --disable-zlib \
        --disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx
    make -j4 PROGRAMS='dropbear dbclient dropbearkey dropbearconvert' MULTI=1 STATIC=1
    cp dropbearmulti "$CACHE/out/dropbear"
    cp LICENSE "$CACHE/out/LICENSE.dropbear"
    cp "$BUILD/zig-x86_64-linux-0.14.1/lib/libc/musl/COPYRIGHT" "$CACHE/out/LICENSE.musl"
    cp "$BUILD/zig-x86_64-linux-0.14.1/LICENSE" "$CACHE/out/LICENSE.zig"
    cp localoptions.h "$CACHE/out/localoptions.h"
    file "$CACHE/out/dropbear"
    sha256sum "$CACHE/out/dropbear" > "$CACHE/out/dropbear.sha256"
elif [ "${1:-}" != package ]; then
    echo "Usage: sh $0 [build|package]" >&2; exit 2
fi
expected=0707f2dc873a7a432eaa51b08b8e32e3109964b41dce82ce4657fb0d48ab0400
actual=$(sha256sum "$CACHE/out/dropbear" | awk '{print $1}')
[ "$actual" = "$expected" ] || {
    echo '重建程序与已验收摘要不同；保留在本地缓存，须重新核对后更新版本与来源信息。' >&2
    exit 1
}
cp "$CACHE/out/dropbear" "$FEATURE_DIR/bin/dropbear"
for name in LICENSE.dropbear LICENSE.musl LICENSE.zig localoptions.h; do
    cp "$CACHE/out/$name" "$FEATURE_DIR/licenses/$name"
done
exec python3 "$FEATURE_DIR/build-package.py"
