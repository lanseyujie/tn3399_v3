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

custom_rootfs() {
    # 安装构建工具
    apt install -y qemu-user-static debootstrap
    # 构建 rootfs
    debootstrap --arch=arm64 --include=language-pack-en,language-pack-zh-hans,bash-completion,htop,nano,vim,curl,wget,axel,unar,network-manager,wireless-tools,iw,bluez,bluez-tools,rfkill,pciutils,usbutils,alsa-utils,lshw,ssh --components=main,restricted,multiverse,universe --foreign focal "$ROOTFS_PATH" http://repo.huaweicloud.com/ubuntu-ports/

    cp /usr/bin/qemu-aarch64-static "$ROOTFS_PATH"/usr/bin/
    cp -rf "$OVERLAY_PATH"/* "$ROOTFS_PATH"/

    # 挂载路径
    mount_rootfs

    # 执行出错时自动卸载路径
    trap umount_rootfs ERR
    # trap umount_rootfs EXIT

    # 执行自定义修改
    chroot <"$SCRIPTS_PATH"/custom_rootfs.sh "$ROOTFS_PATH"

    # 安装内核模块
    # cd $(dirname "$PROJECT_PATH")/linux && make modules_install INSTALL_MOD_PATH="$ROOTFS_PATH"
    # cd $(dirname "$PROJECT_PATH")/linux && make modules_install ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) INSTALL_MOD_PATH="$ROOTFS_PATH"

    # 卸载路径
    umount_rootfs

    # 清理工作
    rm -f "$ROOTFS_PATH"/usr/bin/qemu-aarch64-static

    echo "ROOTFS: BUILD SUCCEED"
}

if [ "$(id -u)" -ne 0 ]; then
    echo "THIS SCRIPT MUST BE RUN AS ROOT"
    exit 1
fi

if [ "$TARGET" == "custom" ] || [ "$TARGET" == "c" ]; then
    custom_rootfs
elif [ "$TARGET" == "mount" ] || [ "$TARGET" == "m" ]; then
    mount_rootfs
elif [ "$TARGET" == "umount" ] || [ "$TARGET" == "u" ]; then
    umount_rootfs
else
    echo
    echo "usage:"
    echo "build_rootfs.sh <custom | c>"
    echo "build_rootfs.sh <mount | m>"
    echo "build_rootfs.sh <umount | u>"
    echo
fi
