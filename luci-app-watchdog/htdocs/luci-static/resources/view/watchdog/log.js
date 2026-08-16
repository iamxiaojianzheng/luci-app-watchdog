'use strict';
'require dom';
'require fs';
'require poll';
'require uci';
'require view';
'require form';
'require ui';

return view.extend({
	render: function () {
		var css = `
			.watchdog-log-toolbar {
				display: flex;
				align-items: center;
				justify-content: space-between;
				margin-bottom: 12px;
				gap: 12px;
				flex-wrap: wrap;
			}
			.watchdog-log-controls {
				display: flex;
				align-items: center;
				gap: 12px;
			}
			.watchdog-log-container {
				background: #1e1e1e;
				color: #d4d4d4;
				border-radius: 6px;
				padding: 14px;
				font-family: monospace;
				font-size: 13px;
				line-height: 1.5;
				max-height: 550px;
				overflow-y: auto;
				border: 1px solid #333;
			}
			.log-line {
				margin: 0;
				white-space: pre-wrap;
				word-break: break-all;
			}
			.log-info { color: #38bdf8; }
			.log-warn { color: #fbbf24; }
			.log-error { color: #f87171; }
			.log-block { color: #c084fc; font-weight: bold; }
			.log-time { color: #9ca3af; margin-right: 6px; }
		`;

		var autoScroll = true;
		var filterKeyword = '';
		var rawLogText = '';

		var searchInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'placeholder': _('Search / Filter Logs...'),
			'style': 'width: 220px;',
			'input': function(ev) {
				filterKeyword = ev.target.value.toLowerCase();
				renderLogLines();
			}
		});

		var autoScrollCheckbox = E('label', { class: 'cbi-checkbox', style: 'display:inline-flex; align-items:center; gap:4px;' }, [
			E('input', {
				'type': 'checkbox',
				'checked': true,
				'change': function(ev) {
					autoScroll = ev.target.checked;
				}
			}),
			_('Auto Scroll')
		]);

		var clearBtn = E('button', {
			'class': 'cbi-button cbi-button-remove',
			'click': function (ev) {
				ev.preventDefault();
				fs.exec_direct('/usr/libexec/watchdog-call', ['clear_log']).then(function () {
					rawLogText = '';
					renderLogLines();
					ui.addNotification(null, E('p', _('Log cleared successfully.')), 'info');
				});
			}
		}, _('Clear Logs'));

		var downloadBtn = E('button', {
			'class': 'cbi-button cbi-button-action',
			'click': function (ev) {
				ev.preventDefault();
				var blob = new Blob([rawLogText], { type: 'text/plain;charset=utf-8' });
				var a = document.createElement('a');
				a.href = URL.createObjectURL(blob);
				a.download = 'watchdog-' + new Date().toISOString().slice(0,10) + '.log';
				a.click();
			}
		}, _('Download Log'));

		var logContainer = E('div', { class: 'watchdog-log-container' }, [
			E('div', { class: 'log-line' }, _('Loading logs...'))
		]);

		function renderLogLines() {
			if (!rawLogText.trim()) {
				dom.content(logContainer, E('div', { class: 'log-line', style: 'color:#6b7280' }, _('Log is currently empty.')));
				return;
			}

			var lines = rawLogText.split('\n');
			var fragment = document.createDocumentFragment();

			lines.forEach(function(line) {
				if (!line.trim()) return;
				if (filterKeyword && line.toLowerCase().indexOf(filterKeyword) === -1) {
					return;
				}

				var lineClass = 'log-line';
				if (line.includes('[ERROR]')) lineClass += ' log-error';
				else if (line.includes('[WARN]')) lineClass += ' log-warn';
				else if (line.includes('[INFO]')) lineClass += ' log-info';
				if (line.includes('Block') || line.includes('blocked')) lineClass += ' log-block';

				var el = E('div', { class: lineClass }, line);
				fragment.appendChild(el);
			});

			dom.content(logContainer, fragment);

			if (autoScroll) {
				logContainer.scrollTop = logContainer.scrollHeight;
			}
		}

		poll.add(function () {
			return fs.read_direct('/tmp/watchdog/watchdog.log', 'text')
				.then(function (res) {
					var text = res || '';
					if (text !== rawLogText) {
						rawLogText = text;
						renderLogLines();
					}
				})
				.catch(function () {
					dom.content(logContainer, E('div', { class: 'log-line log-error' }, _('Failed to load log file.')));
				});
		});

		return E('div', { class: 'cbi-map' }, [
			E('style', [css]),
			E('div', { class: 'cbi-section' }, [
				E('div', { class: 'watchdog-log-toolbar' }, [
					E('div', { class: 'watchdog-log-controls' }, [
						searchInput,
						autoScrollCheckbox
					]),
					E('div', { class: 'watchdog-log-controls' }, [
						downloadBtn,
						clearBtn
					])
				]),
				logContainer,
				E('small', { style: 'display:block; margin-top:8px; color:#6b7280;' }, _('Live log viewer updating every 5 seconds.'))
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
