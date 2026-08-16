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

get_device_mac() {
	local ip="$1"
	[ -z "$ip" ] && return
	local mac=""
	if [ -f /proc/net/arp ]; then
		mac=$(awk -v target="$ip" '$1 == target && $1 !~ "^0" {print $4}' /proc/net/arp | head -n 1)
	fi
	if [ -z "$mac" ] || [ "$mac" = "00:00:00:00:00:00" ]; then
		mac=$(ip neigh show "$ip" 2>/dev/null | awk '{print $5}' | head -n 1)
	fi
	[ "$mac" = "00:00:00:00:00:00" ] && mac=""
	echo "$mac"
}

get_device_hostname() {
	local ip="$1"
	local mac="$2"
	local host=""
	if [ -n "$mac" ] && [ -f /var/dhcp.leases ]; then
		host=$(grep -i "$mac" /var/dhcp.leases 2>/dev/null | awk '{print $4}' | head -n 1)
	fi
	if [ -z "$host" ] || [ "$host" = "*" ]; then
		if [ -f /var/dhcp.leases ]; then
			host=$(grep -w "$ip" /var/dhcp.leases 2>/dev/null | awk '{print $4}' | head -n 1)
		fi
	fi
	[ "$host" = "*" ] && host=""
	echo "$host"
}

get_device_vendor() {
	local mac="$1"
	local hostname="$2"
	local oui=""

	[ -n "$mac" ] && oui=$(echo "$mac" | sed 's/[:.-]//g' | cut -c1-6 | tr 'a-z' 'A-Z')

	# 1. 精简提取的常用 OUI 厂商数据库 (覆盖主流消费级/IoT设备)
	case "$oui" in
		# Apple (苹果)
		F01898|3C0630|A45E60|ACBC32|B038E0|0017F2|001CB3|18E7F4|00CDFE|000393|000505|000A27|000D93|0010FA|001124|0014A6|0016CB|0019E3|001B63|001C10|001D4F|001E52|001F5B|001FF3|0021E9|002241|002312|002331|00236C|0023DF|002436|002500|00254B|0025BC|002608|00264A|0026B0|0026BB|34159E|38C986|7C6D62|A860B6)
			echo "Apple (苹果)" && return ;;
		# Midea (美的)
		B096EA|9CC12D|242730|D48457|AC233F|B8D812|7C49EB)
			echo "Midea (美的)" && return ;;
		# Xiaomi (米家/云米/石头)
		844693|84D47E|D4619D|74A7EA|584498|640980|186590|28D244|A44519|0C9D92|14F65A|68DFDD|704760|9C99A0)
			echo "Xiaomi (米家/云米)" && return ;;
		# Huawei / Honor (华为/荣耀)
		BCD074|2C265F|4801C5|7054B4|00E0FC|04F938|0C96BF|10327E|000B45|000F43|001882|001E10|00259E|04257B|0819A6)
			echo "Huawei (华为/荣耀)" && return ;;
		# HP (惠普)
		282E89|1866DA|3C5282|A0B3CC|0001E6|0002A5|000802|000BCD|000E7F)
			echo "HP (惠普)" && return ;;
		# Dell (戴尔)
		98E743|00065B|000874|000F1F|001143|00123F|001372|001422)
			echo "Dell (戴尔)" && return ;;
		# Lenovo (联想)
		0012FE|0050BF|083E8E|1078D2|149FE8|1C3947|2016B9|283926)
			echo "Lenovo (联想)" && return ;;
		# Samsung (三星)
		0000F0|000278|0007AB|0009B8|001247|001377|001599|00166B)
			echo "Samsung (三星)" && return ;;
		# OPPO / vivo / BBK (步步高/OPPO/vivo)
		2C598A|30F772|7886D7|E4A7A0|FC6B94|CC7B35)
			echo "OPPO/vivo" && return ;;
		# Sony (索尼)
		00014A|000413|000889|000E07|0013A9|0015C1|0019C5)
			echo "Sony (索尼)" && return ;;
		# Intel (英特尔网卡)
		0002B3|000347|000423|000C78|000E0C|001320|0013E8|001500|00166F|0016EA|0018DE|001B21|001CBF|001D09|001E64)
			echo "Intel 网卡" && return ;;
		# Realtek (瑞昱)
		00004C|000729|000EE8|000F54|001060|001859|0010A4|0021F6)
			echo "Realtek 网卡" && return ;;
		# MediaTek (联发科)
		000C43|000E8E|001060|080028|1C4BD6|246968|282C02)
			echo "MediaTek" && return ;;
		# TP-Link / Mercury / Fast (普联/水星/迅捷)
		5405DB|F4F5DB|D85D4C|001966|002127|000AEB|001478|001D0F|0023CD|002586|002719|107B44|14CF92|18A6F7)
			echo "TP-Link / 水星" && return ;;
		# Tenda (腾达)
		00B00C|00E04C|C83A35|CC3429|D46E0E)
			echo "Tenda (腾达)" && return ;;
		# Raspberry Pi (树莓派)
		B827EB|DCA632|E45F01|28CDC1)
			echo "Raspberry Pi (树莓派)" && return ;;
		# Hisense / TCL / Skyworth (家电品牌)
		001C62|002522|18C58A|A41B5C|001A9A|00262F|3897D6)
			echo "Smart TV (电视/家电)" && return ;;
	esac

	# 2. Hostname 智能关键字降维匹配 (解决随机 MAC 问题)
	if [ -n "$hostname" ]; then
		local lower_host
		lower_host=$(echo "$hostname" | tr 'A-Z' 'a-z')
		case "$lower_host" in
			*iphone*|*ipad*|*macbook*|*apple*) echo "Apple (苹果)" && return ;;
			*midea*) echo "Midea (美的)" && return ;;
			*yunmi*|*mibt*|*chunmi*|*xiaomi*|*mi-*) echo "Xiaomi (米家/云米)" && return ;;
			*-hp*|*hp-*|*hewlett*) echo "HP (惠普)" && return ;;
			*pc*|*desktop*|*laptop*|*workstation*) echo "PC (电脑终端)" && return ;;
		esac
	fi

	# 3. 判断是否为私有/随机 MAC (第 2 字符为 2,6,A,E)
	local c2
	c2=$(echo "$oui" | cut -c2)
	case "$c2" in
		2|6|A|E) echo "移动设备 (随机MAC)" && return ;;
	esac

	echo "通用设备"
}

parse_user_agent() {
	local ua="$1"
	[ -z "$ua" ] || [ "$ua" = "Unknown" ] && echo "未知终端" && return

	local lower_ua
	lower_ua=$(echo "$ua" | tr 'A-Z' 'a-z')

	# 1. 识别自动化工具与黑客爆破工具
	case "$lower_ua" in
		*python*|*curl*|*wget*|*go-http*|*java*|*nmap*|*zgrab*|*sqlmap*|*masscan*|*libwww*)
			echo "自动化/爆破工具 (高风险)"
			return
			;;
		*dropbear*|*openssh*|*ssh*)
			echo "SSH 终端客户端"
			return
			;;
	esac

	# 2. 识别系统与浏览器类型
	case "$lower_ua" in
		*iphone*) echo "Apple iPhone (iOS)" ;;
		*ipad*) echo "Apple iPad (iPadOS)" ;;
		*macintosh*|*mac*) echo "Apple Mac (macOS)" ;;
		*android*) echo "Android 移动设备" ;;
		*windows*|*win64*|*win32*) echo "Windows PC" ;;
		*linux*|*ubuntu*|*debian*) echo "Linux 终端" ;;
		*chrome*) echo "Chrome 浏览器" ;;
		*safari*) echo "Safari 浏览器" ;;
		*) echo "Web 客户端" ;;
	esac
}

get_device_fingerprint() {
	local ip="$1"
	local ua="${2:-Unknown}"

	local mac="" hostname="" vendor="" summary=""
	if is_private_ip "$ip"; then
		mac=$(get_device_mac "$ip")
		hostname=$(get_device_hostname "$ip" "$mac")
		vendor=$(get_device_vendor "$mac" "$hostname")

		if [ -n "$hostname" ]; then
			summary="${vendor} (${hostname})"
		elif [ -n "$mac" ]; then
			summary="${vendor} (${mac})"
		else
			summary="${vendor} (局域网)"
		fi
	else
		local parsed_ua
		parsed_ua=$(parse_user_agent "$ua")
		local geo
		geo=$(get_ip_attribution "$ip")

		if [ "$parsed_ua" != "未知终端" ] && [ -n "$parsed_ua" ]; then
			summary="${parsed_ua} [${geo}]"
		else
			summary="公网终端 [${geo}]"
		fi
	fi

	echo "$summary"
}

