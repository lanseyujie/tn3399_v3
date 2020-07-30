#!/bin/bash
set -e

# custom_rootfs.sh is only for tn3399_v3 dev board
# see https://github.com/lanseyujie/tn3399_v3.git
# Wildlife <admin@lanseyujie.com>
# 2020.07.10

if [ "$(id -u)" -ne 0 ]; then
    echo "THIS SCRIPT MUST BE RUN AS ROOT"
    exit 1
fi

echo ubuntu >/etc/hostname

cat >/etc/hosts <<EOF
127.0.0.1       localhost
127.0.1.1       ubuntu
127.0.1.2       localhost.localdomain

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 无交互式执行命令
export DEBIAN_FRONTEND=noninteractive

# 修改镜像源并更新软件包
cp -a /etc/apt/sources.list /etc/apt/sources.list.bak
sed -i "s@http://ports.ubuntu.com@http://mirrors.huaweicloud.com@g" /etc/apt/sources.list

# 基础软件包
apt update && apt dist-upgrade -y && apt install -y \
    apt-utils dialog \
    language-pack-en language-pack-zh-hans \
    tzdata bash-completion

# 安装缺失的文档及翻译
unminimize <<EOF
Y

EOF

# 必要的软件包
apt install -y \
    init sudo ssh udev kmod pciutils usbutils alsa-utils lshw \
    iproute2 iputils-ping network-manager iw wireless-tools \
    htop nano vim unar wget curl axel \
    linux-firmware

# 修改默认密码
echo "root:1234" | chpasswd
# 设置密码过期
chage -d 0 root

# ttyS2
ln -s /lib/systemd/system/serial-getty\@.service /etc/systemd/system/getty.target.wants/serial-getty@ttyS2.service

# 清理缓存
apt clean
rm -rf /var/lib/apt/lists/*
rm -f ~/.bash_history
