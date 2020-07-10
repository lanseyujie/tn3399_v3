#!/bin/bash
set -e

# factory_image.sh is only for tn3399_v3 dev board
# see https://github.com/lanseyujie/tn3399_v3.git
# Wildlife <admin@lanseyujie.com>
# 2020.07.09

SCRIPTS_PATH=$(
    cd "$(dirname "$0")"
    pwd
)
PROJECT_PATH=$(dirname "$SCRIPTS_PATH")
BIN_PATH=$PROJECT_PATH/bin
CONFIG_PATH=$PROJECT_PATH/config
OUTPUT_PATH=$PROJECT_PATH/out
BACKUP_PATH=$OUTPUT_PATH/backup
PWD_PATH=$(pwd)

TARGET=$1
LOADER=$PWD_PATH/$2

check() {
    mkdir -p "$BIN_PATH" "$BACKUP_PATH"

    # 下载 upgrade_tool 工具
    if [ ! -x "$BIN_PATH/upgrade_tool" ] || [ ! -f "$BIN_PATH/config.ini" ]; then
        wget -c -O "$BIN_PATH/upgrade_tool" https://raw.githubusercontent.com/rockchip-linux/rkbin/master/tools/upgrade_tool
        wget -c -O "$BIN_PATH/config.ini" https://raw.githubusercontent.com/rockchip-linux/rkbin/master/tools/config.ini
        chmod +x "$BIN_PATH/upgrade_tool"
    fi

    # 检查是否处于 Loader 模式
    if [ "$("$BIN_PATH/upgrade_tool" ld | tail -n 1 | tr -d '\r' | cut -d '=' -f 6)" = "Loader" ]; then
        if [ "$TARGET" == "restore" ] || [ "$TARGET" == "r" ]; then
            # 切换到 Maskrom 模式
            "$BIN_PATH/upgrade_tool" rd 3
        fi
    else
        echo "DEVICE NOT FOUND OR NOT LOADER MODE"
        exit 1
    fi
}

backup() {
    check

    tool=$BIN_PATH/upgrade_tool

    # 输出分区信息
    $tool pl

    # 备份分区
    $tool rl 0x00002000 0x00002000 "$BACKUP_PATH"/uboot.img
    $tool rl 0x00004000 0x00002000 "$BACKUP_PATH"/trust.img
    $tool rl 0x00006000 0x00002000 "$BACKUP_PATH"/misc.img
    $tool rl 0x00008000 0x00008000 "$BACKUP_PATH"/resource.img
    $tool rl 0x00010000 0x0000c000 "$BACKUP_PATH"/kernel.img
    $tool rl 0x0001c000 0x00010000 "$BACKUP_PATH"/boot.img
    $tool rl 0x0002c000 0x00010000 "$BACKUP_PATH"/recovery.img
    $tool rl 0x0003c000 0x00038000 "$BACKUP_PATH"/backup.img
    $tool rl 0x00074000 0x00040000 "$BACKUP_PATH"/cache.img
    $tool rl 0x000b4000 0x00300000 "$BACKUP_PATH"/system.img
    $tool rl 0x003b4000 0x00008000 "$BACKUP_PATH"/metadata.img
    $tool rl 0x003bc000 0x00000040 "$BACKUP_PATH"/verity_mode.img
    $tool rl 0x003bc040 0x00002000 "$BACKUP_PATH"/baseparamer.img
    $tool rl 0x003be040 0x00000400 "$BACKUP_PATH"/frp.img
    $tool rl 0x003be440 0x00300000 "$BACKUP_PATH"/userdata.img
}

restore() {
    check

    if [ ! -f "$LOADER" ]; then
        echo "LOADER NOT FOUND"
        exit 1
    fi

    tool=$BIN_PATH/upgrade_tool

    # 擦除 FLash
    $tool ef "$LOADER"
    # 下载 Loader
    $tool ul "$LOADER"
    # 下载分区表
    $tool di -p "$CONFIG_PATH"/parameter_gpt.txt
    # 下载镜像
    $tool di -uboot "$BACKUP_PATH"/uboot.img
    $tool di -trust "$BACKUP_PATH"/trust.img
    $tool di -misc "$BACKUP_PATH"/misc.img
    $tool di -resource "$BACKUP_PATH"/resource.img
    $tool di -k "$BACKUP_PATH"/kernel.img
    $tool di -b "$BACKUP_PATH"/boot.img
    $tool di -recovery "$BACKUP_PATH"/recovery.img
    $tool di -backup "$BACKUP_PATH"/backup.img
    $tool di -cache "$BACKUP_PATH"/cache.img
    $tool di -s "$BACKUP_PATH"/system.img
    $tool di -metadata "$BACKUP_PATH"/metadata.img
    $tool di -verity_mode "$BACKUP_PATH"/verity_mode.img
    $tool di -baseparamer "$BACKUP_PATH"/baseparamer.img
    $tool di -frp "$BACKUP_PATH"/frp.img
    $tool di -userdata "$BACKUP_PATH"/userdata.img

    # 启动系统
    $tool rd
}

if [ "$TARGET" == "backup" ] || [ "$TARGET" == "b" ]; then
    backup
elif [ "$TARGET" == "restore" ] || [ "$TARGET" == "r" ]; then
    restore
else
    echo
    echo "usage:"
    echo "factory_image.sh <backup | b>"
    echo "factory_image.sh <restore | r> <loader>"
    echo
fi
