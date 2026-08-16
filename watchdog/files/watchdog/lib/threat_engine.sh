#!/bin/bash
#
# Watchdog Threat Intelligence Analytics Engine
#

THREAT_DB="${API_DIR}/ip_threat_records.json"

init_threat_db() {
	mkdir -p "$API_DIR"
	if [ ! -f "$THREAT_DB" ] || [ ! -s "$THREAT_DB" ]; then
		echo "{}" > "$THREAT_DB"
	fi
}

update_threat_record() {
	local ip="$1"
	local event_type="$2"
	local req_path="${3:-/}"
	local ua="${4:-Unknown}"
	local now_str
	now_str=$(date '+%Y-%m-%d %H:%M:%S')

	[ -z "$ip" ] && return 1
	init_threat_db

	local location
	location=$(get_ip_attribution "$ip")

	local net_type="Public IPv4"
	if echo "$ip" | grep -Eq '^(127\.|192\.168\.|10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|fc00:|fe80:|::1)'; then
		net_type="Private/LAN"
	elif echo "$ip" | grep -Eq '^[0-9a-fA-F:]{2,39}$'; then
		net_type="Public IPv6"
	fi

	local is_banned="false"
	if [ -f "${API_DIR}/ip_blacklist" ] && grep -qF "$ip" "${API_DIR}/ip_blacklist" 2>/dev/null; then
		is_banned="true"
	fi

	local mac="" hostname="" vendor="" dev_summary=""
	if command -v get_device_mac >/dev/null 2>&1; then
		mac=$(get_device_mac "$ip")
		hostname=$(get_device_hostname "$ip" "$mac")
		vendor=$(get_device_vendor "$mac" "$hostname")
		dev_summary=$(get_device_fingerprint "$ip" "$ua")
	else
		dev_summary="$location"
	fi

	# 使用 jq 安全更新 JSON 结构
	if command -v jq >/dev/null 2>&1; then
		local tmpdb="${THREAT_DB}.tmp"
		jq --arg ip "$ip" \
		   --arg loc "$location" \
		   --arg net "$net_type" \
		   --arg path "$req_path" \
		   --arg ua "$ua" \
		   --arg event "$event_type" \
		   --arg time "$now_str" \
		   --arg banned "$is_banned" \
		   --arg mac "$mac" \
		   --arg host "$hostname" \
		   --arg vendor "$vendor" \
		   --arg dev_summary "$dev_summary" \
		   '.[$ip] = {
		       ip: $ip,
		       location: $loc,
		       net_type: $net,
		       last_path: $path,
		       user_agent: $ua,
		       last_event: $event,
		       last_seen: $time,
		       first_seen: (.[$ip].first_seen // $time),
		       attempts: ((.[$ip].attempts // 0) + (if ($event | contains("failed")) then 1 else 0 end)),
		       banned: ($banned == "true"),
		       mac: $mac,
		       hostname: $host,
		       vendor: $vendor,
		       device_summary: $dev_summary
		   }' "$THREAT_DB" > "$tmpdb" 2>/dev/null && mv "$tmpdb" "$THREAT_DB"
	fi
}

get_threat_records_json() {
	init_threat_db
	cat "$THREAT_DB" 2>/dev/null || echo "{}"
}

clear_threat_records() {
	mkdir -p "$API_DIR"
	echo "{}" > "$THREAT_DB"
}
