#!/bin/bash
#
# Watchdog Blacklist Store & Synchronization Manager
#

# IP 格式校验白名单（仅允许合法的 IPv4/IPv6 字符）
_validate_ip() {
	local ip="$1"
	[ -z "$ip" ] && return 1
	# IPv4
	echo "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && return 0
	# IPv6（简写/全写均允许）
	echo "$ip" | grep -Eq '^[0-9a-fA-F:]{2,39}$' && return 0
	return 1
}

sync_blacklist_to_firewall() {
	[ -f "$IP_BLACKLIST_PATH" ] || touch "$IP_BLACKLIST_PATH"

	# 确保末尾有换行
	[ "$(tail -c 1 "$IP_BLACKLIST_PATH" 2>/dev/null | wc -l)" -eq 0 ] && echo "" >> "$IP_BLACKLIST_PATH"

	# 1. 正向同步：将文件中的 IP 刷入防火墙
	local line ip timeout
	while read -r line; do
		[ -z "$line" ] && continue
		ip=$(echo "$line" | awk '{print $1}')
		timeout=$(echo "$line" | awk '{print $3}')
		[ -z "$timeout" ] && timeout="$LOGIN_IP_BLACK_TIMEOUT"

		if _validate_ip "$ip"; then
			fw_add_black_ip "$ip" "$timeout"
		fi
	done < "$IP_BLACKLIST_PATH"

	# 2. 反向同步与自动解封：获取防火墙中未过期的集合
	local active_info ip_black
	active_info=$(fw_get_active_blacklist)
	[ -z "$active_info" ] && return 0

	while IFS= read -r line; do
		[ -z "$line" ] && continue
		ip_black=$(echo "$line" | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}")
		[ -z "$ip_black" ] && ip_black=$(echo "$line" | grep -Eo "([0-9a-fA-F]{1,4}(:{1,2})){1,15}[0-9a-fA-F]{1,4}")
		[ -z "$ip_black" ] && continue

		if grep -qF "$ip_black" "$IP_BLACKLIST_PATH" 2>/dev/null; then
			# 若仍有效，更新剩余超时记录
			local tmpfile="${IP_BLACKLIST_PATH}.tmp"
			grep -vF "$ip_black" "$IP_BLACKLIST_PATH" > "$tmpfile" 2>/dev/null || true
			mv "$tmpfile" "$IP_BLACKLIST_PATH"
			echo "$line" >> "$IP_BLACKLIST_PATH"
		else
			# 已从防火墙过期解封，物理移除并记录
			fw_del_black_ip "$ip_black"
			log "INFO" "Ban expired/canceled for IP: $ip_black"
		fi
	done <<< "$active_info"
}

add_to_blacklist() {
	local ip="$1"
	local timeout="${2:-$LOGIN_IP_BLACK_TIMEOUT}"
	_validate_ip "$ip" || { log "WARN" "add_to_blacklist: invalid IP format '$ip', skipped."; return 1; }

	if ! grep -qF "$ip" "$IP_BLACKLIST_PATH" 2>/dev/null; then
		echo "$ip timeout $timeout" >> "$IP_BLACKLIST_PATH"
	fi

	fw_add_black_ip "$ip" "$timeout"
}

del_from_blacklist() {
	local ip="$1"
	_validate_ip "$ip" || { log "WARN" "del_from_blacklist: invalid IP format '$ip', skipped."; return 1; }

	# 使用 grep -F 固定字符串模式，避免 sed 正则展开注入
	local tmpfile="${IP_BLACKLIST_PATH}.tmp"
	grep -vF "$ip" "$IP_BLACKLIST_PATH" > "$tmpfile" 2>/dev/null && mv "$tmpfile" "$IP_BLACKLIST_PATH"
	fw_del_black_ip "$ip"
}
