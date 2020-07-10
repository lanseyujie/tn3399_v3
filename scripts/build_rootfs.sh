#!/bin/bash
set -e

# build_rootfs.sh is only for tn3399_v3 dev board
# see https://github.com/lanseyujie/tn3399_v3.git
# Wildlife <admin@lanseyujie.com>
# 2020.06.24

SCRIPTS_PATH=$(
    cd "$(dirname "$0")"
    pwd
)
PROJECT_PATH=$(dirname "$SCRIPTS_PATH")
PWD_PATH=$(pwd)
OUTPUT_PATH=$PROJECT_PATH/out
ROOTFS_PATH=$OUTPUT_PATH/rootfs

UBUNTU_VERSION=20.04
TARGET=$1

init_rootfs() {
    rm -rf "$ROOTFS_PATH" && mkdir -p "$ROOTFS_PATH" && cd "$OUTPUT_PATH"

    if [ ! -f "$OUTPUT_PATH/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz" ]; then
        # 下载 ubuntu-base
        wget -c "http://cdimage.ubuntu.com/ubuntu-base/releases/$UBUNTU_VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz"
    fi

    # 解压并保留原始文件权限
    echo "ROOTFS: DECOMPRESSING..."
    tar -xpf ubuntu-base-20.04-base-arm64.tar.gz -C "$ROOTFS_PATH"

    # 模拟 aarch64 环境
    apt install -y qemu-user-static
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_PATH"/usr/bin/

    # 配置同本机一样的 DNS 用于之后的联网更新
    cp -b /etc/resolv.conf "$ROOTFS_PATH"/etc/resolv.conf

    echo "ROOTFS: INITED"
}

chroot_rootfs() {
    custom_before

    # 挂载路径
    mount -t proc /proc "$ROOTFS_PATH"/proc
    mount -t sysfs /sys "$ROOTFS_PATH"/sys
    mount -o bind /dev "$ROOTFS_PATH"/dev
    mount -o bind /dev/pts "$ROOTFS_PATH"/dev/pts

    chroot "$ROOTFS_PATH"

    # 卸载路径
    umount "$ROOTFS_PATH"/proc
    umount "$ROOTFS_PATH"/sys
    umount "$ROOTFS_PATH"/dev/pts
    umount "$ROOTFS_PATH"/dev

    echo "ROOTFS: UNMOUNTED"

    custom_after
}

custom_before() {
    echo "todo://"
}

custom_after() {
    echo "todo://"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "THIS SCRIPT MUST BE RUN AS ROOT"
    exit 1
fi

if [ "$TARGET" == "init" ] || [ "$TARGET" == "i" ]; then
    init_rootfs
elif [ "$TARGET" == "chroot" ] || [ "$TARGET" == "c" ]; then
    chroot_rootfs
else
    echo
    echo "usage:"
    echo "build_rootfs.sh <init | i>"
    echo "build_rootfs.sh <chroot | c>"
    echo
fi
