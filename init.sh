#!/bin/bash

# ================= 配置区域 =================
GITHUB_USER="Naigai666" # 您的 GitHub 用户名
SSH_PORT="24356"                   # SSH 端口
TIMEZONE="Asia/Shanghai"           # 时区设置
SWAP_SIZE="2048"                   # Swap 大小 (MB), 设为 0 不创建
# ===========================================

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
PLAIN="\033[0m"

info() { echo -e "${GREEN}[INFO] $1${PLAIN}"; }
error() { echo -e "${RED}[ERROR] $1${PLAIN}"; }

# 检查 root
if [[ $EUID -ne 0 ]]; then
   error "必须以 root 权限运行此脚本" 
   exit 1
fi

info "🚀 [1/8] 系统更新与基础软件安装..."
apt update && apt upgrade -y
# 增加安装 ca-certificates 和 gnupg 用于 Docker
apt install -y curl sudo vim ufw fail2ban wget net-tools git ca-certificates gnupg lsb-release

info "🕒 [2/8] 设置时区为 ${TIMEZONE}..."
timedatectl set-timezone ${TIMEZONE}
info "当前时间: $(date)"

info "🚀 [3/8] 开启 BBR 网络加速..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    info "BBR 已启用"
else
    info "BBR 配置已存在，跳过"
fi

info "🐳 [4/8] 安装 Docker & Docker Compose..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
    info "Docker 安装完成"
else
    info "Docker 已安装，跳过"
fi

info "💾 [5/8] 配置 Swap (虚拟内存)..."
if [ $(free -m | grep Swap | awk '{print $2}') -eq 0 ] && [ "${SWAP_SIZE}" -ne "0" ]; then
    info "检测到未配置 Swap，正在创建 ${SWAP_SIZE}MB Swap文件..."
    fallocate -l ${SWAP_SIZE}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE}
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    info "Swap 创建成功"
else
    info "Swap 已存在或已禁用，跳过"
fi

info "🔑 [6/8] 配置 SSH 公钥..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
curl -sL "https://github.com/${GITHUB_USER}.keys" >> /root/.ssh/authorized_keys
if [ ! -s /root/.ssh/authorized_keys ]; then
    error "无法从 GitHub 获取公钥，请检查网络或用户名"
    exit 1
fi
chmod 600 /root/.ssh/authorized_keys

info "⚙️  [7/8] 修改 SSH 端口与安全设置..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

# 暴力清理旧配置并写入新配置 (更稳健的写法)
sed -i '/^#Port/d' $SSHD_CONFIG
sed -i '/^Port/d' $SSHD_CONFIG
sed -i '/^PasswordAuthentication/d' $SSHD_CONFIG
sed -i '/^PermitRootLogin/d' $SSHD_CONFIG
sed -i '/^PubkeyAuthentication/d' $SSHD_CONFIG

echo "Port ${SSH_PORT}" >> $SSHD_CONFIG
echo "PasswordAuthentication no" >> $SSHD_CONFIG
echo "PermitRootLogin yes" >> $SSHD_CONFIG
echo "PubkeyAuthentication yes" >> $SSHD_CONFIG

info "🛡️  [8/8] 配置防火墙 (UFW) 与 Fail2ban..."
echo "y" | ufw reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ${SSH_PORT}/tcp comment 'SSH Port'
ufw allow 80/tcp comment 'Web HTTP'
ufw allow 443/tcp comment 'Web HTTPS'
echo "y" | ufw enable

# Fail2ban 配置
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
backend = systemd
EOF
systemctl restart fail2ban
systemctl enable fail2ban

info "🔄 重启 SSH 服务..."
systemctl restart ssh

echo "============================================================"
echo -e "${GREEN}🎉 系统初始化完成！${PLAIN}"
echo -e "Hostname : $(hostname)"
echo -e "Public IP: $(curl -s ifconfig.me)"
echo -e "SSH Port : ${SSH_PORT}"
echo -e "Docker   : $(docker -v)"
echo "============================================================"
echo "👉 请务必新开终端测试： ssh -p ${SSH_PORT} root@IP"
