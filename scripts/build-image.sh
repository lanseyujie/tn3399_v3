#!/bin/bash
set -e

# build-image.sh is only for tn3399_v3 dev board
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
#BOOT_SIZE=1048576

#SYSTEM_START=0
LOADER1_START=64                                      # 64 preloader (miniloader or U-Boot SPL)
RESERVED1_START=$((LOADER1_START + LOADER1_SIZE))     # 8064 legacy DRM key
RESERVED2_START=$((RESERVED1_START + RESERVED1_SIZE)) # 8192 legacy parameter
LOADER2_START=$((RESERVED2_START + RESERVED2_SIZE))   # 16384 U-Boot or UEFI
TRUST_START=$((LOADER2_START + LOADER2_SIZE))         # 24576 trusted-os like ATF, OP-TEE
BOOT_START=$((TRUST_START + TRUST_SIZE))              # 32768 kernel, dtb, extlinux.conf, ramdisk
ROOTFS_START=$((BOOT_START + BOOT_SIZE))              # 262144 linux system
#ROOTFS_START=$((BOOT_START + BOOT_SIZE))              # 1081344 linux system

SCRIPTS_PATH=$(
    cd "$(dirname "$0")"
    pwd
)
PROJECT_PATH=$(dirname "$SCRIPTS_PATH")
OUTPUT_PATH=$PROJECT_PATH/out

TARGET=$1

# 构建完整镜像所必须的文件
#$OUTPUT_PATH
#├── kernel
#│   ├── Image
#│   └── tn3399-linux.dtb
#├── rootfs.img
#└── u-boot
#    ├── idbloader.img
#    ├── trust.img
#    └── u-boot.img

# u-boot
IDBLOADER_IMGAGE=$OUTPUT_PATH/u-boot/idbloader.img
UBOOT_IMGAGE=$OUTPUT_PATH/u-boot/u-boot.img
TRUSRT_IMGAGE=$OUTPUT_PATH/u-boot/trust.img
# boot
DTB_FILE=$OUTPUT_PATH/kernel/tn3399-linux.dtb
KERNEL_IMAGE=$OUTPUT_PATH/kernel/Image
BOOT_IMAGE=$OUTPUT_PATH/boot.img
# rootfs
ROOTFS_IMAGE=$OUTPUT_PATH/rootfs.img
# system
SYSTEM_IMAGE=$OUTPUT_PATH/system.img

build_trust() {
    echo "todo://"
}

build_boot() {
    rm -f "$BOOT_IMAGE"
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
}

build_system() {
    rm -f "$SYSTEM_IMAGE"
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
    dd if="$UBOOT_IMGAGE" of="$SYSTEM_IMAGE" seek=$LOADER2_START conv=notrunc
    dd if="$TRUSRT_IMGAGE" of="$SYSTEM_IMAGE" seek=$TRUST_START conv=notrunc

    # 烧写 boot
    dd if="$BOOT_IMAGE" of="$SYSTEM_IMAGE" seek=$BOOT_START conv=notrunc

    # 烧写 rootfs
    dd if="$ROOTFS_IMAGE" of="$SYSTEM_IMAGE" seek=$ROOTFS_START conv=notrunc,fsync
}

if [ "$TARGET" == "trust" ]; then
    build_trust
elif [ "$TARGET" == "boot" ]; then
    build_boot
elif [ "$TARGET" == "system" ]; then
    build_system
fi
