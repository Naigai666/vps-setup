#!/bin/bash

# ================= 配置区域 (请修改这里) =================
# 您的 GitHub 用户名 (用于拉取公钥)
GITHUB_USER="Naigai666"

# 自定义 SSH 端口 (建议 10000-65535 之间)
SSH_PORT="24356"
# =======================================================

# 检查是否为 root 用户
if [[ $EUID -ne 0 ]]; then
   echo "❌ 错误：必须以 root 权限运行此脚本" 
   exit 1
fi

echo "🚀 [1/6] 系统更新与基础软件安装..."
# 更新源并升级系统
apt update && apt upgrade -y
# 安装基础工具、防火墙、Fail2ban
apt install -y curl sudo vim ufw fail2ban wget net-tools git

echo "🔑 [2/6] 配置 SSH 公钥..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
# 从 GitHub 获取公钥
curl -sL "https://github.com/${GITHUB_USER}.keys" >> /root/.ssh/authorized_keys

if [ ! -s /root/.ssh/authorized_keys ]; then
    echo "❌ 错误：无法从 GitHub 获取公钥，请检查用户名或网络。"
    exit 1
fi
chmod 600 /root/.ssh/authorized_keys
echo "✅ 公钥配置成功。"

echo "⚙️  [3/6] 修改 SSH 端口与安全设置..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp $SSHD_CONFIG "${SSHD_CONFIG}.bak"

# 1. 修改端口 (处理可能存在的 Port 配置)
sed -i '/^#Port/d' $SSHD_CONFIG
sed -i '/^Port/d' $SSHD_CONFIG
echo "Port ${SSH_PORT}" >> $SSHD_CONFIG

# 2. 禁止密码登录，仅允许密钥
sed -i '/^PasswordAuthentication/d' $SSHD_CONFIG
echo "PasswordAuthentication no" >> $SSHD_CONFIG

# 3. 允许 Root 登录 (仅限密钥)
sed -i '/^PermitRootLogin/d' $SSHD_CONFIG
echo "PermitRootLogin yes" >> $SSHD_CONFIG

# 4. 确保公钥验证开启
sed -i '/^PubkeyAuthentication/d' $SSHD_CONFIG
echo "PubkeyAuthentication yes" >> $SSHD_CONFIG

echo "✅ SSH 配置已更新：端口 ${SSH_PORT}，禁用密码登录。"

echo "🛡️  [4/6] 配置防火墙 (UFW)..."
# 重置 UFW 规则
echo "y" | ufw reset
# 默认策略：拒绝进，允许出
ufw default deny incoming
ufw default allow outgoing
# 放行 SSH 新端口
ufw allow ${SSH_PORT}/tcp comment 'SSH Port'
# 放行 Web 端口 (Caddy/Docker 需要)
ufw allow 80/tcp comment 'Web HTTP'
ufw allow 443/tcp comment 'Web HTTPS'
# 启用防火墙
echo "y" | ufw enable
echo "✅ 防火墙已启用，放行端口：${SSH_PORT}, 80, 443。"

echo "👮 [5/6] 配置 Fail2ban 保护 SSH..."
# 写入自定义配置 jail.local
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
action = iptables-allports
EOF

systemctl restart fail2ban
systemctl enable fail2ban
echo "✅ Fail2ban 已启动并监控端口 ${SSH_PORT}。"

echo "🔄 [6/6] 重启 SSH 服务..."
systemctl restart ssh

echo "============================================================"
echo "🎉 初始化脚本执行完毕！"
echo "👉 请立即新开一个终端窗口进行连接测试 (不要关闭当前窗口)："
echo "   ssh -p ${SSH_PORT} root@服务器IP"
echo "============================================================"
