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
OVERLAY_PATH=$PROJECT_PATH/overlay
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

    echo "ROOTFS: INITED"
}

mount_rootfs() {
    mount -t proc /proc "$ROOTFS_PATH"/proc
    mount -t sysfs /sys "$ROOTFS_PATH"/sys
    mount -o bind /dev "$ROOTFS_PATH"/dev
    mount -o bind /dev/pts "$ROOTFS_PATH"/dev/pts

    echo "ROOTFS: MOUNTED"
}

umount_rootfs() {
    umount "$ROOTFS_PATH"/proc
    umount "$ROOTFS_PATH"/sys
    umount "$ROOTFS_PATH"/dev/pts
    umount "$ROOTFS_PATH"/dev

    echo "ROOTFS: UNMOUNTED"
}

custom_before() {
    # 内核模块
    # cd $(dirname "$PROJECT_PATH")/linux && make modules_install INSTALL_MOD_PATH="$ROOTFS_PATH"
    # cd $(dirname "$PROJECT_PATH")/linux && make modules_install ARCG=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) INSTALL_MOD_PATH="$ROOTFS_PATH"

    # 模拟 aarch64 环境
    apt install -y qemu-user-static
    cp /usr/bin/qemu-aarch64-static "$ROOTFS_PATH"/usr/bin/

    # 配置同本机一样的 DNS 用于之后的联网更新
    cp -b /etc/resolv.conf "$ROOTFS_PATH"/etc/resolv.conf

    cp -rf "$OVERLAY_PATH"/* "$ROOTFS_PATH"/
}

custom_rootfs() {
    # 准备工作
    custom_before

    # 挂载路径
    mount_rootfs

    # 执行出错时自动卸载路径
    trap umount_rootfs ERR
    # trap umount_rootfs EXIT

    # 执行自定义修改
    chroot <"$SCRIPTS_PATH"/custom_rootfs.sh "$ROOTFS_PATH"

    # 卸载路径
    umount_rootfs

    # 清理工作
    custom_after
}

custom_after() {
    rm -f "$ROOTFS_PATH"/usr/bin/qemu-aarch64-static
}

if [ "$(id -u)" -ne 0 ]; then
    echo "THIS SCRIPT MUST BE RUN AS ROOT"
    exit 1
fi

if [ "$TARGET" == "init" ] || [ "$TARGET" == "i" ]; then
    init_rootfs
elif [ "$TARGET" == "custom" ] || [ "$TARGET" == "c" ]; then
    custom_rootfs
elif [ "$TARGET" == "mount" ] || [ "$TARGET" == "m" ]; then
    mount_rootfs
elif [ "$TARGET" == "umount" ] || [ "$TARGET" == "u" ]; then
    umount_rootfs
else
    echo
    echo "usage:"
    echo "build_rootfs.sh <init | i>"
    echo "build_rootfs.sh <custom | c>"
    echo "build_rootfs.sh <mount | m>"
    echo "build_rootfs.sh <umount | u>"
    echo
fi
