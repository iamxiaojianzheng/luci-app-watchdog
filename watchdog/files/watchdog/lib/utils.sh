#!/bin/bash
#
# Watchdog Utility & Helper Library
#

# 文件互斥锁（使用 flock -n 非阻塞检测单例）
LockFile() {
	local action="$1"
	local lock_file="${2:-$LOCK_FILE}"
	local fd=200

	[ -z "$lock_file" ] && return 1

	if [ "$action" = "lock" ]; then
		eval "exec $fd>$lock_file"
		if ! flock -n $fd 2>/dev/null; then
			return 1
		fi
	elif [ "$action" = "unlock" ]; then
		flock -u $fd 2>/dev/null
		eval "exec $fd>&-" 2>/dev/null
	fi
}

# 格式化日志输出
log() {
	local level="INFO"
	local msg="$1"
	if [ $# -ge 2 ]; then
		level="$1"
		msg="$2"
	fi
	echo "$(date "+%Y-%m-%d %H:%M:%S") - [$level] $msg" >> "$LOGFILE"
}

# 静默执行命令
silent_run() {
	"$@" >/dev/null 2>&1
}

# 轮转与控制日志行数大小
deltemp() {
	[ -f "$LOGFILE" ] || return 0
	local logrow
	logrow=$(grep -c "" "$LOGFILE" 2>/dev/null || echo "0")
	if [ "$logrow" -gt 500 ]; then
		tail -n 300 "$LOGFILE" > "${LOGFILE}.tmp"
		mv "${LOGFILE}.tmp" "$LOGFILE"
		log "DEBUG" "Log exceeded limit, kept last 300 entries"
	fi
}
