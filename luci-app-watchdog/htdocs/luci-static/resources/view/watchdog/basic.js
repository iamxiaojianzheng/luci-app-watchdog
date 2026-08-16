'use strict';
'require view';
'require fs';
'require ui';
'require uci';
'require form';
'require poll';
'require dom';

function fetchStatus() {
    return fs.exec_direct('/usr/libexec/watchdog-call', ['status']).then(function(res) {
        try {
            return JSON.parse(res);
        } catch(e) {
            return { running: false, pid: null, blacklist_count: 0 };
        }
    }).catch(function() {
        return { running: false, pid: null, blacklist_count: 0 };
    });
}

function parseUserAgent(ua, item) {
    if (item && item.device_summary && item.device_summary !== '公网IP' && item.device_summary !== '未知') {
        return item.device_summary;
    }

    if (!ua || ua === 'Unknown') return '未知终端/设备';
    
    var os = '';
    if (ua.indexOf('Windows NT 10.0') !== -1 || ua.indexOf('Windows NT 11.0') !== -1) os = 'Windows 10/11';
    else if (ua.indexOf('Windows') !== -1) os = 'Windows';
    else if (ua.indexOf('Macintosh') !== -1 || ua.indexOf('Mac OS X') !== -1) os = 'macOS';
    else if (ua.indexOf('iPhone') !== -1) os = 'iPhone (iOS)';
    else if (ua.indexOf('iPad') !== -1) os = 'iPad (iPadOS)';
    else if (ua.indexOf('Android') !== -1) os = 'Android';
    else if (ua.indexOf('Linux') !== -1) os = 'Linux';

    var browser = '';
    if (ua.indexOf('Edg/') !== -1 || ua.indexOf('Edge') !== -1) browser = 'Microsoft Edge';
    else if (ua.indexOf('Chrome/') !== -1 && ua.indexOf('Chromium') === -1) browser = 'Google Chrome';
    else if (ua.indexOf('Safari/') !== -1 && ua.indexOf('Chrome') === -1) browser = 'Apple Safari';
    else if (ua.indexOf('Firefox/') !== -1) browser = 'Mozilla Firefox';
    else if (ua.indexOf('curl/') !== -1) browser = 'cURL CLI (命令行工具)';
    else if (ua.indexOf('python') !== -1 || ua.indexOf('Python') !== -1) browser = 'Python 自动化/爆破脚本';
    else if (ua.indexOf('SSH') !== -1) browser = 'SSH 终端客户端';
    else if (ua.indexOf('LuCI') !== -1 || ua.indexOf('Browser') !== -1) browser = 'Web 浏览器客户端';

    if (browser && os) {
        return browser + ' (' + os + ')';
    } else if (browser) {
        return browser;
    } else if (os) {
        return 'Web 客户端 (' + os + ')';
    }

    return ua.length > 40 ? ua.substring(0, 37) + '...' : ua;
}

return view.extend({
    render: function() {
        if (window.navigator && window.navigator.userAgent) {
            fs.exec('/usr/libexec/watchdog-call', ['report_ua', window.location.hostname, window.navigator.userAgent]);
        }

        var css = `
            .watchdog-status-card {
                display: flex;
                align-items: center;
                justify-content: space-between;
                background: var(--card-bg, #ffffff);
                border: 1px solid var(--border-color, #e5e7eb);
                border-radius: 8px;
                padding: 16px 20px;
                margin-bottom: 20px;
                box-shadow: 0 2px 6px rgba(0,0,0,0.04);
            }
            .watchdog-status-info {
                display: flex;
                align-items: center;
                gap: 16px;
            }
            .status-badge {
                display: inline-flex;
                align-items: center;
                gap: 8px;
                font-weight: 600;
                font-size: 1.1em;
            }
            .status-dot {
                width: 10px;
                height: 10px;
                border-radius: 50%;
                display: inline-block;
            }
            .status-dot.running {
                background-color: #10b981;
                box-shadow: 0 0 0 3px rgba(16, 185, 129, 0.2);
            }
            .status-dot.stopped {
                background-color: #ef4444;
                box-shadow: 0 0 0 3px rgba(239, 68, 68, 0.2);
            }
            .status-meta {
                color: #6b7280;
                font-size: 0.9em;
            }
            .watchdog-btn-group {
                display: flex;
                gap: 10px;
            }
            .watchdog-table-box {
                margin-top: 10px;
                border: 1px solid var(--border-color, #e5e7eb);
                border-radius: 8px;
                overflow: hidden;
                background: var(--card-bg, #ffffff);
            }
            .watchdog-add-bar {
                display: flex;
                gap: 10px;
                padding: 12px 16px;
                background: var(--background-color, #f9fafb);
                border-bottom: 1px solid var(--border-color, #e5e7eb);
                align-items: center;
            }
            .watchdog-add-bar input {
                flex: 1;
            }
            .watchdog-add-bar input.timeout-input {
                flex: 0 0 160px;
            }
            .badge-timeout {
                display: inline-block;
                padding: 3px 10px;
                background: #e0f2fe;
                color: #0369a1;
                border-radius: 12px;
                font-size: 0.85em;
                font-weight: 500;
            }
            .badge-ip {
                font-family: monospace;
                font-weight: 600;
                color: #111827;
                font-size: 1.05em;
            }
            .badge-net {
                display: inline-block;
                padding: 2px 8px;
                border-radius: 4px;
                font-size: 0.8em;
                font-weight: 500;
                margin-left: 6px;
            }
            .badge-net.lan { background: #f3f4f6; color: #4b5563; }
            .badge-net.public { background: #dbeafe; color: #1e40af; }
            .badge-status-banned {
                display: inline-block;
                padding: 2px 8px;
                background: #fee2e2;
                color: #991b1b;
                border-radius: 4px;
                font-size: 0.82em;
                font-weight: 600;
            }
            .badge-status-active {
                display: inline-block;
                padding: 2px 8px;
                background: #dcfce7;
                color: #166534;
                border-radius: 4px;
                font-size: 0.82em;
                font-weight: 600;
            }
            .ua-text {
                font-size: 0.88em;
                color: #4b5563;
                word-break: break-all;
            }
            .geo-text {
                font-weight: 500;
                color: #1f2937;
            }
            /* 强制消除 LuCI 默认 DummyValue 左侧标题栏挤压 */
            .cbi-value[id$="._analytics_section"],
            .cbi-value[id$="._blacklist_section"] {
                display: block !important;
                width: 100% !important;
                padding-left: 0 !important;
                margin-left: 0 !important;
            }
            .cbi-value[id$="._analytics_section"] > .cbi-value-title,
            .cbi-value[id$="._blacklist_section"] > .cbi-value-title {
                display: none !important;
            }
            .cbi-value[id$="._analytics_section"] > .cbi-value-field,
            .cbi-value[id$="._blacklist_section"] > .cbi-value-field {
                width: 100% !important;
                padding-left: 0 !important;
                margin-left: 0 !important;
            }
        `;

        var m, s, o;
        m = new form.Map('watchdog', _('Watch Dog'), 
            _('Security watchdog plugin for OpenWrt, monitoring Web & SSH access with real-time firewall defense.'));

        // 顶栏状态面板 Section
        s = m.section(form.TypedSection, '_status');
        s.anonymous = true;
        s.render = function() {
            var cardContainer = E('div', { class: 'watchdog-status-card' }, [
                E('style', [css]),
                E('div', { class: 'watchdog-status-info' }, [
                    E('div', { class: 'status-badge', id: 'status_badge' }, [
                        E('span', { class: 'status-dot stopped' }),
                        E('span', {}, _('Checking status...'))
                    ]),
                    E('div', { class: 'status-meta', id: 'status_meta' }, '')
                ]),
                E('div', { class: 'watchdog-btn-group' }, [
                    E('button', {
                        class: 'cbi-button cbi-button-action',
                        click: function(ev) {
                            ev.preventDefault();
                            return fs.exec('/etc/init.d/watchdog', ['restart']).then(function() {
                                ui.addNotification(null, E('p', _('Watchdog service restarted.')), 'info');
                            });
                        }
                    }, _('Restart Service')),
                    E('button', {
                        class: 'cbi-button cbi-button-reset',
                        click: function(ev) {
                            ev.preventDefault();
                            return fs.exec('/etc/init.d/watchdog', ['stop']).then(function() {
                                ui.addNotification(null, E('p', _('Watchdog service stopped.')), 'info');
                            });
                        }
                    }, _('Stop Service'))
                ])
            ]);

            poll.add(function() {
                return fetchStatus().then(function(res) {
                    var badgeEl = cardContainer.querySelector('#status_badge');
                    var metaEl = cardContainer.querySelector('#status_meta');

                    if (res.running) {
                        dom.content(badgeEl, [
                            E('span', { class: 'status-dot running' }),
                            E('span', { style: 'color:#10b981' }, _('RUNNING'))
                        ]);
                        dom.content(metaEl, _('PID: %s | Blacklisted IPs: %s').format(res.pid || 'N/A', res.blacklist_count || 0));
                    } else {
                        dom.content(badgeEl, [
                            E('span', { class: 'status-dot stopped' }),
                            E('span', { style: 'color:#ef4444' }, _('STOPPED'))
                        ]);
                        dom.content(metaEl, _('Service is currently inactive.'));
                    }
                });
            });

            return cardContainer;
        };

        // 基本设置与选项卡定义
        s = m.section(form.NamedSection, 'config', 'watchdog');
        s.tab('basic', _('Basic Settings'));
        s.tab('blacklist', _('Blacklist Management'));
        s.tab('analytics', _('Threat Analytics'));
        s.addremove = false;

        // Basic Tab
        o = s.taboption('basic', form.Flag, 'enable', _('Enable Watchdog'));
        o.default = '0';

        o = s.taboption('basic', form.Value, 'sleeptime', _('Check Interval (Seconds)'));
        o.rmempty = false;
        o.placeholder = '60';
        o.datatype = 'and(uinteger,min(10))';
        o.description = _('Interval for periodic safety checks. Shorter intervals increase responsiveness.');

        o = s.taboption('basic', form.MultiValue, 'login_control', _('Monitored Login Events'));
        o.value('web_logged', _('Web Login Success'));
        o.value('ssh_logged', _('SSH Login Success'));
        o.value('web_login_failed', _('Web Login Failures'));
        o.value('ssh_login_failed', _('SSH Login Failures'));

        o = s.taboption('basic', form.Value, 'login_max_num', _('Failure Threshold'));
        o.default = '3';
        o.rmempty = false;
        o.datatype = 'and(uinteger,min(1))';
        o.description = _('Number of failed login attempts allowed before triggering IP ban.');

        // Blacklist Tab
        o = s.taboption('blacklist', form.Flag, 'login_web_black', _('Auto-Ban Failed Login Devices'));
        o.default = '1';
        
        o = s.taboption('blacklist', form.Value, 'login_ip_black_timeout', _('Ban Duration (Seconds)'));
        o.default = '86400';
        o.rmempty = false;
        o.datatype = 'and(uinteger,min(0))';
        o.depends('login_web_black', '1');
        o.description = _('Default ban timeout in seconds (86400s = 24h). Set 0 for permanent ban.');

        o = s.taboption('blacklist', form.DummyValue, '_blacklist_section', '');
        o.rawhtml = true;
        o.default = function() {
            var tableBox = E('div', { class: 'watchdog-table-box' }, [
                E('div', { class: 'watchdog-add-bar' }, [
                    E('input', {
                        type: 'text',
                        id: 'wb_new_ip',
                        class: 'cbi-input-text',
                        placeholder: _('Enter IP address to ban (e.g. 192.168.1.50)')
                    }),
                    E('input', {
                        type: 'number',
                        id: 'wb_new_timeout',
                        class: 'cbi-input-text timeout-input',
                        placeholder: _('Timeout (sec)'),
                        value: '86400'
                    }),
                    E('button', {
                        class: 'cbi-button cbi-button-action',
                        click: function(ev) {
                            ev.preventDefault();
                            var ipInput = document.getElementById('wb_new_ip');
                            var timeoutInput = document.getElementById('wb_new_timeout');
                            var ip = (ipInput.value || '').trim();
                            var timeout = (timeoutInput.value || '').trim() || '86400';

                            if (!ip) {
                                ui.addNotification(null, E('p', _('Please enter a valid IP address.')), 'error');
                                return;
                            }

                            return fs.exec('/usr/libexec/watchdog-call', ['add_black', ip, timeout]).then(function() {
                                ipInput.value = '';
                                ui.addNotification(null, E('p', _('IP %s blacklisted successfully.').format(ip)), 'info');
                                refreshTable();
                            });
                        }
                    }, _('Ban IP Manually'))
                ]),

                E('table', { class: 'table watchdog-table' }, [
                    E('thead', {}, [
                        E('tr', { class: 'tr' }, [
                            E('th', { class: 'th' }, _('Blacklisted IP')),
                            E('th', { class: 'th' }, _('Ban Duration / Expiry')),
                            E('th', { class: 'th center', style: 'width:120px;' }, _('Action'))
                        ])
                    ]),
                    E('tbody', { id: 'watchdog_bl_tbody' }, [
                        E('tr', { class: 'tr' }, [
                            E('td', { class: 'td center', colspan: 3 }, _('Loading blacklist items...'))
                        ])
                    ])
                ])
            ]);

            function refreshTable() {
                return fs.exec_direct('/usr/libexec/watchdog-call', ['get_blacklist']).then(function(res) {
                    var tbody = tableBox.querySelector('#watchdog_bl_tbody');
                    var lines = (res || '').trim().split('\n').filter(Boolean);

                    if (lines.length === 0) {
                        dom.content(tbody, [
                            E('tr', { class: 'tr' }, [
                                E('td', { class: 'td center', colspan: 3, style: 'color:#9ca3af;padding:24px;' }, _('No active blacklisted IP addresses.'))
                            ])
                        ]);
                        return;
                    }

                    var rows = lines.map(function(line) {
                        var parts = line.split(/\s+/);
                        var ip = parts[0];
                        var timeoutStr = _('Permanent / Default');
                        if (parts.length >= 3 && parts[1] === 'timeout') {
                            var secs = parseInt(parts[2], 10);
                            if (!isNaN(secs)) {
                                var h = Math.floor(secs / 3600);
                                var m = Math.floor((secs % 3600) / 60);
                                timeoutStr = _('%dh %dm (%ds)').format(h, m, secs);
                            }
                        }

                        return E('tr', { class: 'tr' }, [
                            E('td', { class: 'td' }, [
                                E('span', { class: 'badge-ip' }, ip)
                            ]),
                            E('td', { class: 'td' }, [
                                E('span', { class: 'badge-timeout' }, timeoutStr)
                            ]),
                            E('td', { class: 'td center' }, [
                                E('button', {
                                    class: 'cbi-button cbi-button-remove',
                                    click: function(ev) {
                                        ev.preventDefault();
                                        return fs.exec('/usr/libexec/watchdog-call', ['del_black', ip]).then(function() {
                                            ui.addNotification(null, E('p', _('IP %s unbanned successfully.').format(ip)), 'info');
                                            refreshTable();
                                        });
                                    }
                                }, _('Unban'))
                            ])
                        ]);
                    });

                    dom.content(tbody, rows);
                });
            }

            poll.add(function() {
                return refreshTable();
            });

            refreshTable();
            return tableBox;
        };

        // Threat Analytics Tab (可视化威胁分析表格)
        o = s.taboption('analytics', form.DummyValue, '_analytics_section', '');
        o.rawhtml = true;
        o.default = function() {
            var filterKeyword = '';

            var analyticsBox = E('div', { class: 'watchdog-table-box' }, [
                // 筛选与搜索工具栏
                E('div', { class: 'watchdog-add-bar' }, [
                    E('input', {
                        type: 'text',
                        id: 'analytics_search',
                        class: 'cbi-input-text',
                        placeholder: _('Filter by IP, Geo Location, Device, URI or Status...'),
                        input: function(ev) {
                            filterKeyword = (ev.target.value || '').toLowerCase().trim();
                            renderAnalyticsTable();
                        }
                    }),
                    E('button', {
                        class: 'cbi-button cbi-button-reset',
                        click: function(ev) {
                            ev.preventDefault();
                            return fs.exec('/usr/libexec/watchdog-call', ['clear_threat_records']).then(function() {
                                ui.addNotification(null, E('p', _('Threat analytics records cleared.')), 'info');
                                renderAnalyticsTable();
                            });
                        }
                    }, _('Clear History'))
                ]),

                // 数据大盘表格
                E('table', { class: 'table watchdog-table' }, [
                    E('thead', {}, [
                        E('tr', { class: 'tr' }, [
                            E('th', { class: 'th' }, _('Source IP & Net')),
                            E('th', { class: 'th' }, _('Location & ISP')),
                            E('th', { class: 'th' }, _('Device / User-Agent')),
                            E('th', { class: 'th' }, _('Target & Event')),
                            E('th', { class: 'th' }, _('Attempts & Time')),
                            E('th', { class: 'th center', style: 'width:120px;' }, _('Status / Action'))
                        ])
                    ]),
                    E('tbody', { id: 'watchdog_analytics_tbody' }, [
                        E('tr', { class: 'tr' }, [
                            E('td', { class: 'td center', colspan: 6 }, _('Loading threat intelligence...'))
                        ])
                    ])
                ])
            ]);

            function renderAnalyticsTable() {
                return fs.exec_direct('/usr/libexec/watchdog-call', ['get_threat_analytics']).then(function(res) {
                    var tbody = analyticsBox.querySelector('#watchdog_analytics_tbody');
                    var data = {};
                    try {
                        data = JSON.parse(res || '{}');
                    } catch(e) {
                        data = {};
                    }

                    var keys = Object.keys(data);
                    if (keys.length === 0) {
                        dom.content(tbody, [
                            E('tr', { class: 'tr' }, [
                                E('td', { class: 'td center', colspan: 6, style: 'color:#9ca3af;padding:24px;' }, _('No access or threat records captured yet.'))
                            ])
                        ]);
                        return;
                    }

                    // 检索关键词过滤
                    var filteredKeys = keys.filter(function(ip) {
                        if (!filterKeyword) return true;
                        var item = data[ip];
                        var searchStr = [
                            item.ip, item.location, item.net_type, 
                            item.user_agent, item.last_path, item.last_event
                        ].join(' ').toLowerCase();
                        return searchStr.indexOf(filterKeyword) !== -1;
                    });

                    if (filteredKeys.length === 0) {
                        dom.content(tbody, [
                            E('tr', { class: 'tr' }, [
                                E('td', { class: 'td center', colspan: 6, style: 'color:#9ca3af;padding:24px;' }, _('No matching records found for filter.'))
                            ])
                        ]);
                        return;
                    }

                    var rows = filteredKeys.map(function(ip) {
                        var item = data[ip];
                        var isLan = (item.net_type || '').indexOf('Private') !== -1;
                        var netBadgeClass = isLan ? 'badge-net lan' : 'badge-net public';
                        var parsedUA = parseUserAgent(item.user_agent, item);
                        var subInfo = item.mac ? ('MAC: ' + item.mac) : (item.user_agent || 'N/A');

                        return E('tr', { class: 'tr' }, [
                            E('td', { class: 'td' }, [
                                E('span', { class: 'badge-ip' }, item.ip),
                                E('span', { class: netBadgeClass }, item.net_type || 'IPv4')
                            ]),
                            E('td', { class: 'td' }, [
                                E('span', { class: 'geo-text' }, item.location || _('Unknown'))
                            ]),
                            E('td', { class: 'td' }, [
                                E('div', { style: 'font-weight:600;color:#111827;' }, parsedUA),
                                E('div', { class: 'ua-text', title: item.user_agent || subInfo }, subInfo)
                            ]),
                            E('td', { class: 'td' }, [
                                E('div', { style: 'font-weight:600;color:#3b82f6;' }, item.last_path || '/'),
                                E('div', { style: 'font-size:0.85em;color:#6b7280;' }, item.last_event || 'n/a')
                            ]),
                            E('td', { class: 'td' }, [
                                E('div', { style: 'font-weight:600;color:#dc2626;' }, _('%d failed attempts').format(item.attempts || 0)),
                                E('div', { style: 'font-size:0.85em;color:#6b7280;' }, item.last_seen || '')
                            ]),
                            E('td', { class: 'td center' }, [
                                item.banned ? 
                                    E('div', {}, [
                                        E('span', { class: 'badge-status-banned', style: 'margin-bottom:4px;' }, _('BANNED')),
                                        E('button', {
                                            class: 'cbi-button cbi-button-remove',
                                            style: 'margin-top:4px;padding:2px 8px;font-size:0.8em;',
                                            click: function(ev) {
                                                ev.preventDefault();
                                                return fs.exec('/usr/libexec/watchdog-call', ['del_black', item.ip]).then(function() {
                                                    ui.addNotification(null, E('p', _('IP %s unbanned successfully.').format(item.ip)), 'info');
                                                    renderAnalyticsTable();
                                                });
                                            }
                                        }, _('Unban'))
                                    ]) :
                                    E('div', {}, [
                                        E('span', { class: 'badge-status-active', style: 'margin-bottom:4px;' }, _('ACTIVE')),
                                        E('button', {
                                            class: 'cbi-button cbi-button-action',
                                            style: 'margin-top:4px;padding:2px 8px;font-size:0.8em;',
                                            click: function(ev) {
                                                ev.preventDefault();
                                                return fs.exec('/usr/libexec/watchdog-call', ['add_black', item.ip, '86400']).then(function() {
                                                    ui.addNotification(null, E('p', _('IP %s blacklisted successfully.').format(item.ip)), 'info');
                                                    renderAnalyticsTable();
                                                });
                                            }
                                        }, _('Ban IP'))
                                    ])
                            ])
                        ]);
                    });

                    dom.content(tbody, rows);
                });
            }

            poll.add(function() {
                return renderAnalyticsTable();
            });

            renderAnalyticsTable();
            return analyticsBox;
        };

        return m.render();
    }
});