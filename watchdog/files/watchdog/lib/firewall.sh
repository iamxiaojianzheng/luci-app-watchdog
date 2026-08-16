#!/bin/bash
#
# Watchdog Firewall Abstraction Driver (Strategy Pattern for nftables / iptables)
#

# 初始化时检测一次并缓存，避免每次操作重复 command -v 检查
FW_TYPE="unknown"

fw_detect() {
	if [ "$FW_TYPE" != "unknown" ]; then
		return 0  # 已缓存，直接返回
	fi
	if command -v nft >/dev/null && [ -x /sbin/fw4 ]; then
		FW_TYPE="nft"
	elif command -v iptables >/dev/null; then
		FW_TYPE="iptables"
	else
		FW_TYPE="unknown"
	fi
}

fw_init_sets() {
	fw_detect
	local timeout="${LOGIN_IP_BLACK_TIMEOUT:-86400}"

	if [ "$FW_TYPE" = "nft" ]; then
		! nft list set inet fw4 watchdog_blacklist >/dev/null 2>&1 && \
			nft add set inet fw4 watchdog_blacklist { type ipv4_addr\; flags timeout\; timeout ${timeout}s\; } >/dev/null 2>&1
		
		! nft list set inet fw4 watchdog_blacklistv6 >/dev/null 2>&1 && \
			nft add set inet fw4 watchdog_blacklistv6 { type ipv6_addr\; flags timeout\; timeout ${timeout}s\; } >/dev/null 2>&1

		! nft list ruleset 2>/dev/null | grep -q "watchdog Drop rule" && {
			nft insert rule inet fw4 input ip saddr @watchdog_blacklist counter drop comment \"\\!watchdog Drop rule\" >/dev/null 2>&1
			nft insert rule inet fw4 input ip6 saddr @watchdog_blacklistv6 counter drop comment \"\\!watchdog Drop rule\" >/dev/null 2>&1
		}
	elif [ "$FW_TYPE" = "iptables" ]; then
		ipset list watchdog_blacklist >/dev/null 2>&1 || \
			ipset create watchdog_blacklist hash:ip timeout ${timeout} >/dev/null 2>&1
		ipset list watchdog_blacklistv6 >/dev/null 2>&1 || \
			ipset create watchdog_blacklistv6 hash:ip timeout ${timeout} family inet6 >/dev/null 2>&1

		iptables -C INPUT -m set --match-set watchdog_blacklist src -j DROP >/dev/null 2>&1 || \
			iptables -I INPUT -m set --match-set watchdog_blacklist src -j DROP >/dev/null 2>&1
		ip6tables -C INPUT -m set --match-set watchdog_blacklistv6 src -j DROP >/dev/null 2>&1 || \
			ip6tables -I INPUT -m set --match-set watchdog_blacklistv6 src -j DROP >/dev/null 2>&1
	fi
}

# 获取防火墙中当前激活且未过期的 IP 列表
fw_get_active_blacklist() {
	fw_detect
	local fw_info_v4="" fw_info_v6=""

	if [ "$FW_TYPE" = "nft" ]; then
		fw_info_v4=$(nft list set inet fw4 watchdog_blacklist 2>/dev/null | tr -d '\n' | grep -oE 'elements = \{[^}]*\}' | grep -oE '[^{}]+ expires [^,}]+[,\}]' | tr ',}' '\n' | tr -s ' ' | sed -e 's/^[[:space:]]*//')
		fw_info_v6=$(nft list set inet fw4 watchdog_blacklistv6 2>/dev/null | tr -d '\n' | grep -oE 'elements = \{[^}]*\}' | grep -oE '[^{}]+ expires [^,}]+[,\}]' | tr ',}' '\n' | tr -s ' ' | sed -e 's/^[[:space:]]*//')
	elif [ "$FW_TYPE" = "iptables" ]; then
		fw_info_v4=$(ipset list watchdog_blacklist 2>/dev/null | grep "timeout")
		fw_info_v6=$(ipset list watchdog_blacklistv6 2>/dev/null | grep "timeout")
	fi

	if [ -n "$fw_info_v4" ] && [ -n "$fw_info_v6" ]; then
		echo -e "${fw_info_v4}\n${fw_info_v6}"
	elif [ -n "$fw_info_v6" ]; then
		echo "$fw_info_v6"
	else
		echo "$fw_info_v4"
	fi
}

fw_get_ip_version() {
	local ip="$1"
	if echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
		echo "v4"
	elif echo "$ip" | grep -Eq '^[0-9a-fA-F:]{2,39}$'; then
		echo "v6"
	else
		echo "invalid"
	fi
}

fw_add_black_ip() {
	local ip="$1"
	local timeout="${2:-$LOGIN_IP_BLACK_TIMEOUT}"
	[ -z "$ip" ] && return 1

	local version
	version=$(fw_get_ip_version "$ip")
	if [ "$version" = "invalid" ]; then
		log "WARN" "Invalid IP format: $ip"
		return 1
	fi

	local set_name="watchdog_blacklist"
	[ "$version" = "v6" ] && set_name="watchdog_blacklistv6"

	if [ "$FW_TYPE" = "nft" ]; then
		nft add element inet fw4 "$set_name" { "$ip" expires ${timeout}s } >/dev/null 2>&1
	elif [ "$FW_TYPE" = "iptables" ]; then
		ipset -exist add "$set_name" "$ip" timeout ${timeout} >/dev/null 2>&1
	fi
	return 0
}

fw_del_black_ip() {
	local ip="$1"
	[ -z "$ip" ] && return 1

	local version
	version=$(fw_get_ip_version "$ip")
	[ "$version" = "invalid" ] && return 1

	local set_name="watchdog_blacklist"
	[ "$version" = "v6" ] && set_name="watchdog_blacklistv6"

	if [ "$FW_TYPE" = "nft" ]; then
		nft delete element inet fw4 "$set_name" { "$ip" } >/dev/null 2>&1
	elif [ "$FW_TYPE" = "iptables" ]; then
		ipset list "$set_name" >/dev/null 2>&1 && ipset -! del "$set_name" "$ip" >/dev/null 2>&1
	fi
	return 0
}

fw_clear_all() {
	if [ "$FW_TYPE" = "nft" ]; then
		local handles
		handles=$(nft -a list ruleset 2>/dev/null | grep -E "watchdog Drop rule" | awk '{print $NF}')
		for handle in $handles; do
			nft delete rule inet fw4 input handle $handle 2>/dev/null
		done
		nft delete set inet fw4 watchdog_blacklist 2>/dev/null
		nft delete set inet fw4 watchdog_blacklistv6 2>/dev/null
	elif [ "$FW_TYPE" = "iptables" ]; then
		iptables -D INPUT -m set --match-set watchdog_blacklist src -j DROP 2>/dev/null
		ip6tables -D INPUT -m set --match-set watchdog_blacklistv6 src -j DROP 2>/dev/null
		ipset destroy watchdog_blacklist 2>/dev/null
		ipset destroy watchdog_blacklistv6 2>/dev/null
	fi
	# 重置缓存，允许下次重新检测
	FW_TYPE="unknown"
}
