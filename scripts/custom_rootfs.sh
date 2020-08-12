#!/bin/bash
set -eu

# custom_rootfs.sh is only for tn3399_v3 dev board
# see https://github.com/lanseyujie/tn3399_v3.git
# Wildlife <admin@lanseyujie.com>
# 2020.07.10

if [ "$(id -u)" -ne 0 ]; then
    echo "THIS SCRIPT MUST BE RUN AS ROOT"
    exit 1
fi

# 继续构建第二阶段
/debootstrap/debootstrap --second-stage

# 修改主机名
echo ubuntu >/etc/hostname

# 修改 hosts
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

# 修改时区
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 更新软件包
apt update && apt dist-upgrade -y

# 允许 root 远程登录
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config

# 修改默认密码
echo 'root:1234' | chpasswd
# 设置密码过期
chage -d 0 root

# ttyS2
ln -s /lib/systemd/system/serial-getty\@.service /etc/systemd/system/getty.target.wants/serial-getty@ttyS2.service

# 问题报告
cat >/etc/update-motd.d/60-issue-report<<EOF
#!/bin/sh
#
# 60-issue-report is only for tn3399_v3 dev board
# see https://github.com/lanseyujie/tn3399_v3.git
# Wildlife <admin@lanseyujie.com>
# 2020.08.12

printf "\n"
printf " * Issue: https://github.com/lanseyujie/tn3399_v3/issues"
EOF
chmod +x /etc/update-motd.d/60-issue-report

# 清理
apt clean
rm -rf /var/lib/apt/lists/*
rm -f ~/.bash_history
rm -f /usr/bin/qemu-aarch64-static
