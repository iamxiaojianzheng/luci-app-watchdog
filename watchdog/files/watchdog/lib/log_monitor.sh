#!/bin/bash
#
# Watchdog Log Monitor & Event Dispatcher Engine
#

declare -A WEB_FAILED_COUNTS
declare -A SSH_FAILED_COUNTS

# 当前 logread 与消费者子进程 PID（用于 cleanup 时精准清理）
_LOGREAD_PID=""
_CONSUMER_PID=""

process_login_event() {
	local ip="$1"
	local log_time="$2"
	local event_type="$3"
	local req_path="${4:-/}"

	[ -z "$ip" ] && return

	case "$event_type" in
		"web_failed"|"ssh_failed")
			local count=0
			if [ "$event_type" = "web_failed" ]; then
				WEB_FAILED_COUNTS["$ip"]=$(( ${WEB_FAILED_COUNTS["$ip"]:-0} + 1 ))
				count=${WEB_FAILED_COUNTS["$ip"]}
			else
				SSH_FAILED_COUNTS["$ip"]=$(( ${SSH_FAILED_COUNTS["$ip"]:-0} + 1 ))
				count=${SSH_FAILED_COUNTS["$ip"]}
			fi

			if [ "$count" -ge "$LOGIN_MAX_NUM" ]; then
				add_to_blacklist "$ip" "$LOGIN_IP_BLACK_TIMEOUT"
				log "WARN" "IP $ip exceeded max failures ($count attempts). Added to blacklist."
				login_send_notify "$ip" "$log_time" "${event_type}_blocked" "$req_path"
				unset WEB_FAILED_COUNTS["$ip"]
				unset SSH_FAILED_COUNTS["$ip"]
			else
				login_send_notify "$ip" "$log_time" "$event_type" "$req_path"
			fi
			;;
		"web_success"|"ssh_success")
			del_from_blacklist "$ip"
			unset WEB_FAILED_COUNTS["$ip"]
			unset SSH_FAILED_COUNTS["$ip"]
			login_send_notify "$ip" "$log_time" "$event_type" "$req_path"
			;;
	esac
}

login_send_notify() {
	local ip="$1"
	local log_time="$2"
	local event_type="$3"
	local req_path="${4:-/}"

	local attr
	attr=$(get_ip_attribution "$ip")

	case "$event_type" in
		"web_failed_blocked"|"ssh_failed_blocked")
			log "WARN" "Block Notice: Device $ip ($attr) blocked due to frequent ${event_type} attempts on $req_path at $log_time."
			;;
		"web_failed"|"ssh_failed")
			log "WARN" "Login Warning: Device $ip ($attr) failed ${event_type} attempt on $req_path at $log_time."
			;;
		"web_success"|"ssh_success")
			log "INFO" "Login Success: Device $ip ($attr) logged in via ${event_type} on $req_path at $log_time."
			;;
	esac
}

# 停止当前 logread 及消费者子进程（由 watchdog 主进程 cleanup 调用）
stop_log_monitor() {
	if [ -n "$_LOGREAD_PID" ] && kill -0 "$_LOGREAD_PID" 2>/dev/null; then
		kill -9 "$_LOGREAD_PID" 2>/dev/null
		_LOGREAD_PID=""
	fi
	if [ -n "$_CONSUMER_PID" ] && kill -0 "$_CONSUMER_PID" 2>/dev/null; then
		kill -9 "$_CONSUMER_PID" 2>/dev/null
		_CONSUMER_PID=""
	fi
	rm -f "${TMP_DIR}/logread.fifo"
}

run_log_monitor() {
	if [ "$WEB_LOGGED" != "true" ] && [ "$SSH_LOGGED" != "true" ] && \
	   [ "$WEB_LOGIN_FAILED" != "true" ] && [ "$SSH_LOGIN_FAILED" != "true" ]; then
		return 0
	fi

	local fifo="${TMP_DIR}/logread.fifo"
	rm -f "$fifo"
	mkfifo "$fifo"

	# 移除 -p notice 过滤：SSH 登录成功事件是 authpriv.info 级别（优先级=6），
	# -p notice 只保留优先级<=5，会导致 SSH 成功/info 级事件完全捕获不到
	logread -f 200>&- > "$fifo" &
	_LOGREAD_PID=$!

	# 消费者 while 作为独立后台子 shell 读取 fifo
	(
	while IFS= read -r line; do
		[ -z "$line" ] && continue

		local req_path
		req_path=$(echo "$line" | sed -n 's/.*on \(\/[^ ]*\).*/\1/p')
		[ -z "$req_path" ] && req_path="/"

		# Web 登录成功
		if [ "$WEB_LOGGED" = "true" ]; then
			if echo "$line" | grep -iqE "accepted login|login succeeded|luci: accepted|cgi: accepted"; then
				web_ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n 1)
				[ -z "$web_ip" ] && web_ip=$(echo "$line" | grep -oE '([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}' | tail -n 1)
				[ -n "$web_ip" ] && process_login_event "$web_ip" "$(echo "$line" | awk '{print $1,$2,$3}')" "web_success" "$req_path"
			fi
		fi

		# SSH 登录成功
		if [ "$SSH_LOGGED" = "true" ]; then
			if echo "$line" | grep -iqE "Password auth succeeded|Pubkey auth succeeded|Accepted password|Accepted publickey"; then
				ssh_ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n 1)
				[ -z "$ssh_ip" ] && ssh_ip=$(echo "$line" | grep -oE '([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}' | tail -n 1)
				[ -n "$ssh_ip" ] && process_login_event "$ssh_ip" "$(echo "$line" | awk '{print $1,$2,$3}')" "ssh_success" "SSH"
			fi
		fi

		# Web 登录失败
		if [ "$WEB_LOGIN_FAILED" = "true" ]; then
			if echo "$line" | grep -iqE "failed login|authentication failure|luci: failed|login failed|cgi: failed"; then
				web_f_ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n 1)
				[ -z "$web_f_ip" ] && web_f_ip=$(echo "$line" | grep -oE '([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}' | tail -n 1)
				[ -n "$web_f_ip" ] && process_login_event "$web_f_ip" "$(echo "$line" | awk '{print $1,$2,$3}')" "web_failed" "$req_path"
			fi
		fi

		# SSH 登录失败
		if [ "$SSH_LOGIN_FAILED" = "true" ]; then
			if echo "$line" | grep -iqE "Bad password attempt|Login attempt for nonexistent user|Max auth tries reached|Failed password|Failed publickey"; then
				ssh_f_ip=$(echo "$line" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n 1)
				[ -z "$ssh_f_ip" ] && ssh_f_ip=$(echo "$line" | grep -oE '([0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{1,4}' | tail -n 1)
				if [ -z "$ssh_f_ip" ]; then
					# 对于 nonexistent user 情况：通过 PID 关联 Child connection 获取 IP
					ssh_f_num=$(echo "$line" | sed -n 's/.*dropbear\[\([0-9]\+\)\]: Login attempt for nonexistent user/\1/p')
					[ -n "$ssh_f_num" ] && ssh_f_ip=$(logread | grep "dropbear\[${ssh_f_num}\].*Child connection from" | \
						grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n 1)
				fi
				[ -n "$ssh_f_ip" ] && process_login_event "$ssh_f_ip" "$(echo "$line" | awk '{print $1,$2,$3}')" "ssh_failed" "SSH"
			fi
		fi
	done < "$fifo"
	) 200>&- &
	_CONSUMER_PID=$!
}
