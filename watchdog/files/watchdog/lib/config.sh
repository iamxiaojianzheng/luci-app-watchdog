#!/bin/bash
#
# Watchdog Configuration Loader
#

# 读取 UCI 单值配置
get_uci_option() {
	local option="$1"
	local default_val="$2"
	local val
	val=$(uci -q get "${APP}.config.${option}" 2>/dev/null)
	echo "${val:-$default_val}"
}

read_config() {
	ENABLE=$(get_uci_option "enable" "0")
	SLEEPTIME=$(get_uci_option "sleeptime" "60")
	LOGIN_MAX_NUM=$(get_uci_option "login_max_num" "3")
	LOGIN_WEB_BLACK=$(get_uci_option "login_web_black" "1")
	LOGIN_IP_BLACK_TIMEOUT=$(get_uci_option "login_ip_black_timeout" "86400")
	THREAD_NUM=$(get_uci_option "thread_num" "3")

	# 修复：UCI list 类型须使用 uci show 全量解析，
	# uci get 只返回第一条，会导致多选项只生效第一项
	WEB_LOGGED="false"
	SSH_LOGGED="false"
	WEB_LOGIN_FAILED="false"
	SSH_LOGIN_FAILED="false"

	local ctrl_str
	ctrl_str=$(uci -q get "${APP}.config.login_control" 2>/dev/null; uci -q show "${APP}.config.login_control" 2>/dev/null)

	case "$ctrl_str" in *web_logged*) WEB_LOGGED="true" ;; esac
	case "$ctrl_str" in *ssh_logged*) SSH_LOGGED="true" ;; esac
	case "$ctrl_str" in *web_login_failed*) WEB_LOGIN_FAILED="true" ;; esac
	case "$ctrl_str" in *ssh_login_failed*) SSH_LOGIN_FAILED="true" ;; esac

	IP_BLACKLIST_PATH="$API_DIR/ip_blacklist"
	mkdir -p "$API_DIR"
	touch "$IP_BLACKLIST_PATH"
}
