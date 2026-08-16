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

return view.extend({
    render: function() {
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
        `;

        var m, s, o;
        m = new form.Map('watchdog', _('Watch Dog'), 
            _('Security watchdog plugin for OpenWrt, monitoring Web & SSH access with real-time firewall defense.'));

        // 顶栏状态面板 Section（使用虚拟 type _status，anonymous 渲染覆写）
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

            var _prevBlacklistCount = -1;

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

                    // 黑名单计数发生变化时，自动刷新文本框内容
                    var curCount = res.blacklist_count || 0;
                    if (curCount !== _prevBlacklistCount) {
                        _prevBlacklistCount = curCount;
                        return fs.exec_direct('/usr/libexec/watchdog-call', ['get_blacklist'])
                            .then(function(content) {
                                // 查找黑名单文本框（LuCI 生成的 id 包含 ip_black_list）
                                var textarea = document.querySelector('textarea[id$=".ip_black_list"]');
                                if (textarea && document.activeElement !== textarea) {
                                    textarea.value = content || '';
                                }
                            });
                    }
                });
            });

            return cardContainer;
        };

        // 基本设置配置 Tab
        s = m.section(form.NamedSection, 'config', 'watchdog');
        s.tab('basic', _('Basic Settings'));
        s.tab('blacklist', _('Blacklist Management'));
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

        // Blacklist Tab (使用精美表格与一键解封代替传统 Textarea 文本框)
        o = s.taboption('blacklist', form.Flag, 'login_web_black', _('Auto-Ban Failed Login Devices'));
        o.default = '1';
        
        o = s.taboption('blacklist', form.Value, 'login_ip_black_timeout', _('Ban Duration (Seconds)'));
        o.default = '86400';
        o.rmempty = false;
        o.datatype = 'and(uinteger,min(0))';
        o.depends('login_web_black', '1');
        o.description = _('Default ban timeout in seconds (86400s = 24h). Set 0 for permanent ban.');

        o = s.taboption('blacklist', form.DummyValue, '_blacklist_section', _('Active Blacklist Manager'));
        o.rawhtml = true;
        o.default = function() {
            var tableBox = E('div', { class: 'watchdog-table-box' }, [
                // 手动快捷拉黑工具栏
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

                // 黑名单数据表格
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

        return m.render();
    }
});