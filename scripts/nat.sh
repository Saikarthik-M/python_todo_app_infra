#!/bin/bash
set -e

apt-get update -y

# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# Install iptables persistence
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

# Detect correct interface
IFACE=$(ip route | grep default | awk '{print $5}')

# Apply NAT rule (idempotent)
iptables -t nat -C POSTROUTING -o $IFACE -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

iptables -P FORWARD ACCEPT

# Allow forwarding
iptables -C FORWARD -j ACCEPT 2>/dev/null || iptables -A FORWARD -j ACCEPT

# Save rules
netfilter-persistent save