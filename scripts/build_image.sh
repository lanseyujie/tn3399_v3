#!/bin/bash
set -e

# build_image.sh is only for tn3399_v3 dev board
# see https://github.com/lanseyujie/tn3399_v3.git
# Wildlife <admin@lanseyujie.com>
# 2020.06.20

# http://opensource.rock-chips.com/wiki_Partitions#Default_storage_map
LOADER1_SIZE=8000
RESERVED1_SIZE=128
RESERVED2_SIZE=8192
LOADER2_SIZE=8192
TRUST_SIZE=8192
BOOT_SIZE=229376

LOADER1_START=64                                      # 64 preloader (miniloader or U-Boot SPL)
RESERVED1_START=$((LOADER1_START + LOADER1_SIZE))     # 8064 legacy DRM key
RESERVED2_START=$((RESERVED1_START + RESERVED1_SIZE)) # 8192 legacy parameter
LOADER2_START=$((RESERVED2_START + RESERVED2_SIZE))   # 16384 U-Boot or UEFI
TRUST_START=$((LOADER2_START + LOADER2_SIZE))         # 24576 trusted-os like ATF, OP-TEE
BOOT_START=$((TRUST_START + TRUST_SIZE))              # 32768 kernel, dtb, extlinux.conf, ramdisk
ROOTFS_START=$((BOOT_START + BOOT_SIZE))              # 262144 linux system

SCRIPTS_PATH=$(
    cd "$(dirname "$0")"
    pwd
)
PROJECT_PATH=$(dirname "$SCRIPTS_PATH")
OUTPUT_PATH=$PROJECT_PATH/out
ROOTFS_PATH=$OUTPUT_PATH/rootfs

PWD_PATH=$(pwd)

TARGET=$1

# 构建完整镜像所必须的文件
# $OUTPUT_PATH
# ├── kernel
# │   ├── Image
# │   └── tn3399-linux.dtb
# ├── rootfs
# │   └── ...
# └── u-boot
#     ├── idbloader.img
#     ├── trust.img (仅使用 uboot.img 时使用，详见启动流程一节)
#     └── uboot.img / u-boot.itb

# u-boot
IDBLOADER_IMGAGE=$OUTPUT_PATH/u-boot/idbloader.img
UBOOT_IMGAGE=$OUTPUT_PATH/u-boot/uboot.img
UBOOT_ITB=$OUTPUT_PATH/u-boot/u-boot.itb
TRUSRT_IMGAGE=$OUTPUT_PATH/u-boot/trust.img
# boot
DTB_FILE=$OUTPUT_PATH/kernel/tn3399-linux.dtb
KERNEL_IMAGE=$OUTPUT_PATH/kernel/Image
BOOT_IMAGE=$OUTPUT_PATH/boot.img
# rootfs
ROOTFS_IMAGE=$OUTPUT_PATH/rootfs.img
# system
SYSTEM_IMAGE=$OUTPUT_PATH/system.img

build_boot() {
    rm -f "$BOOT_IMAGE"

    if [ ! -s "$KERNEL_IMAGE" ]; then
        echo "BUILD FAILED: MISSING $KERNEL_IMAGE"
        exit 1
    fi

    cat >"$OUTPUT_PATH"/tn3399.conf <<EOF
label kernel-5.4
    kernel /Image
    fdt /tn3399-linux.dtb
    append earlycon=uart8250,mmio32,0xff1a0000 swiotlb=1 coherent_pool=1m earlyprintk console=ttyS2,1500000n8 rw root=PARTUUID=b921b045-1d rootfstype=ext4 init=/sbin/init rootwait
EOF

    # 生成 MS-DOS 分区格式启动镜像 boot.img
    # -n 卷标名
    # -S 逻辑扇区大小
    # -C 文件名
    mkfs.vfat -n "boot" -S 512 -C "$BOOT_IMAGE" $((100 * 1024))

    # 在 MS-DOS 分区中创建文件夹
    mmd -i "$BOOT_IMAGE" ::/extlinux

    # 复制 extlinux.conf 到分区
    mcopy -i "$BOOT_IMAGE" -s "$OUTPUT_PATH"/tn3399.conf ::/extlinux/extlinux.conf

    # 将 kernel 编译出的 Image 和 dtb 文件复制到分区
    mcopy -i "$BOOT_IMAGE" -s "$DTB_FILE" ::tn3399-linux.dtb
    mcopy -i "$BOOT_IMAGE" -s "$KERNEL_IMAGE" ::Image

    echo "BUILD SUCCEED: $BOOT_IMAGE"
}

build_rootfs() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "THIS OPERATION MUST BE RUN AS ROOT"
        exit 1
    fi

    rm -f "$ROOTFS_IMAGE"

    if [ ! -d "$ROOTFS_PATH" ]; then
        echo "BUILD FAILED: ROOTFS PATH NOT EXIST"
        exit 1
    fi

    # 创建 2G 空白文件，具体所需大小根据 sudo du -h --max-depth=0 "$ROOTFS_PATH" 调整
    dd if=/dev/zero of="$ROOTFS_IMAGE" bs=1M count=2048 oflag=sync status=progress
    # 格式化为 ext4 分区
    mkfs.ext4 "$ROOTFS_IMAGE"

    # 复制 rootfs 文件到镜像
    mount "$ROOTFS_IMAGE" /mnt
    cp -rfp "$ROOTFS_PATH"/* /mnt
    umount /mnt

    # 检查并修复文件系统
    e2fsck -p -f "$ROOTFS_IMAGE"
    # 压缩镜像
    resize2fs -M "$ROOTFS_IMAGE"

    echo "BUILD SUCCEED: $ROOTFS_IMAGE"
}

build_system() {
    rm -f "$SYSTEM_IMAGE"

    if [ ! -s "$IDBLOADER_IMGAGE" ]; then
        echo "BUILD FAILED: MISSING $IDBLOADER_IMGAGE"
        exit 1
    fi

    if [ -s "$UBOOT_IMGAGE" ] && [ ! -s "$TRUSRT_IMGAGE" ]; then
        echo "BUILD FAILED: MISSING $TRUSRT_IMGAGE"
        exit 1
    elif [ ! -s "$UBOOT_ITB" ]; then
        echo "BUILD FAILED: MISSING $UBOOT_ITB"
        exit 1
    fi

    if [ ! -s "$BOOT_IMAGE" ]; then
        echo "BUILD FAILED: MISSING $BOOT_IMAGE"
        exit 1
    fi

    if [ ! -s "$ROOTFS_IMAGE" ]; then
        echo "BUILD FAILED: MISSING $ROOTFS_IMAGE"
        exit 1
    fi

    # 计算镜像大小
    ROOTFS_SIZE=$(stat -L --format="%s" "$ROOTFS_IMAGE")
    GPT_IMAGE_SIZE_MIN=$(((LOADER1_SIZE + RESERVED1_SIZE + RESERVED2_SIZE + LOADER2_SIZE + TRUST_SIZE + BOOT_SIZE + 35) * 512 + ROOTFS_SIZE))
    GPT_IMAGE_SIZE=$((GPT_IMAGE_SIZE_MIN / 1024 / 1024 + 2))

    # 快速创建空白文件
    dd if=/dev/zero of="$SYSTEM_IMAGE" bs=1M count=0 seek=$GPT_IMAGE_SIZE

    # 创建磁盘卷标
    parted -s "$SYSTEM_IMAGE" mklabel gpt
    # 创建各个分区，单位：扇区
    parted -s "$SYSTEM_IMAGE" unit s mkpart loader1 $LOADER1_START $((RESERVED1_START - 1))
    parted -s "$SYSTEM_IMAGE" unit s mkpart loader2 $LOADER2_START $((TRUST_START - 1))
    parted -s "$SYSTEM_IMAGE" unit s mkpart trust $TRUST_START $((BOOT_START - 1))
    parted -s "$SYSTEM_IMAGE" unit s mkpart boot $BOOT_START $((ROOTFS_START - 1))
    parted -s "$SYSTEM_IMAGE" -- unit s mkpart rootfs $ROOTFS_START -34s
    # 设置分区 flag 状态
    parted -s "$SYSTEM_IMAGE" set 4 boot on

    # 调整 guid
    ROOT_UUID="B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
    gdisk "$SYSTEM_IMAGE" <<EOF
x
c
5
$ROOT_UUID
w
y
EOF

    # 烧写 u-boot
    dd if="$IDBLOADER_IMGAGE" of="$SYSTEM_IMAGE" seek=$LOADER1_START conv=notrunc
    if [ -s "$UBOOT_IMGAGE" ] && [ -s "$TRUSRT_IMGAGE" ]; then
        dd if="$UBOOT_IMGAGE" of="$SYSTEM_IMAGE" seek=$LOADER2_START conv=notrunc
        dd if="$TRUSRT_IMGAGE" of="$SYSTEM_IMAGE" seek=$TRUST_START conv=notrunc
    elif [ -s "$UBOOT_ITB" ]; then
        dd if="$UBOOT_ITB" of="$SYSTEM_IMAGE" seek=$LOADER2_START conv=notrunc
    else
        echo "BUILD FAILED: MISSING UBOOT IMAGE/ITB"
        exit 1
    fi

    # 烧写 boot
    dd if="$BOOT_IMAGE" of="$SYSTEM_IMAGE" seek=$BOOT_START conv=notrunc

    # 烧写 rootfs
    dd if="$ROOTFS_IMAGE" of="$SYSTEM_IMAGE" seek=$ROOTFS_START conv=notrunc,fsync

    echo "BUILD SUCCEED: $SYSTEM_IMAGE"
}

if [ "$TARGET" == "boot" ]; then
    build_boot
elif [ "$TARGET" == "rootfs" ]; then
    build_rootfs
elif [ "$TARGET" == "system" ]; then
    build_system
else
    echo
    echo "usage:"
    echo "build_image.sh <boot | rootfs | system>"
    echo
fi
