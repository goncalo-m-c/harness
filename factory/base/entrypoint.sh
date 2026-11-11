#!/bin/bash
# Entrypoint of every factory box. Runs as root, once, when the box starts.
# 1. Sets a firewall for outgoing traffic: the Mac and every private network are blocked, the internet is open.
# 2. Runs the command as the box user, with no capabilities and no way to gain them back.
# If any rule cannot be added (for example the box was started without NET_ADMIN), it exits
# and the command never runs: a box without its firewall must not start.
set -euo pipefail

BOX_USER=agent
# OrbStack's DNS resolver for containers. It sits in 0.0.0.0/8, which is blocked below, so it is allowed first.
DNS=0.250.250.200

# Blocked IPv4 ranges. 0.0.0.0/8 holds OrbStack's address for the Mac (0.250.250.254).
BLOCK_V4=(0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12
          192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4)
# Blocked IPv6 ranges: private, link-local, and IPv4 addresses written as IPv6.
BLOCK_V6=(fc00::/7 fe80::/10 ::ffff:0:0/96)

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d "$DNS" -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -d "$DNS" -p tcp --dport 53 -j ACCEPT
for net in "${BLOCK_V4[@]}"; do iptables -A OUTPUT -d "$net" -j REJECT; done

ip6tables -A OUTPUT -o lo -j ACCEPT
for net in "${BLOCK_V6[@]}"; do ip6tables -A OUTPUT -d "$net" -j REJECT; done

# --inh-caps and --bounding-set remove every capability, also the ones a process could inherit or regain.
# --no-new-privs stops setuid binaries from giving rights back.
exec setpriv --reuid="$BOX_USER" --regid="$BOX_USER" --init-groups \
  --inh-caps=-all --bounding-set=-all --no-new-privs -- "$@"
