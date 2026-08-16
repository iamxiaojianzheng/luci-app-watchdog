#!/bin/bash
#
# Watchdog IP Geo / Attribution Service with In-Memory Caching
#

declare -A IP_CACHE

is_private_ip() {
	local ip="$1"
	if echo "$ip" | grep -Eq '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|fc00:|fe80:|::1)'; then
		return 0
	fi
	return 1
}

get_ip_attribution() {
	local ip="$1"
	[ -z "$ip" ] && echo "未知" && return

	if is_private_ip "$ip"; then
		echo "局域网/本地"
		return
	fi

	if [ -n "${IP_CACHE["$ip"]}" ]; then
		echo "${IP_CACHE["$ip"]}"
		return
	fi

	local attr_list_file="$API_DIR/ip_attribution.list"
	if [ ! -f "$attr_list_file" ]; then
		IP_CACHE["$ip"]="公网IP"
		echo "公网IP"
		return
	fi

	local urls
	urls=$(cat "$attr_list_file" 2>/dev/null | awk 'BEGIN {srand()} {print rand() "\t" $0}' | sort -k1,1n | cut -f2-)
	if [ -z "$urls" ]; then
		IP_CACHE["$ip"]="公网IP"
		echo "公网IP"
		return
	fi

	local res=""
	local line
	while IFS= read -r line; do
		[ -z "$line" ] && continue
		# 替换配置文件中的 ${ip} 占位符
		local cmd
		cmd=$(echo "$line" | sed "s/\${ip}/$ip/g")
		res=$(eval curl --connect-timeout 2 -m 2 -k -s $cmd 2>/dev/null)
		res=$(echo "$res" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		[ -n "$res" ] && break
	done <<< "$urls"

	if [ -n "$res" ]; then
		IP_CACHE["$ip"]="$res"
		echo "$res"
	else
		IP_CACHE["$ip"]="公网IP"
		echo "公网IP"
	fi
}
