'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var getStatus = rpc.declare({ object: 'momo.refind', method: 'status', expect: {} });
var start = rpc.declare({ object: 'momo.refind', method: 'start', params: ['action', 'version'], expect: {} });

return view.extend({
    load: function() { return getStatus(); },
    render: function(data) {
        var current = E('span'), previous = E('span'), message = E('p');
        var log = E('pre', { style: 'white-space:pre-wrap;max-height:28em;overflow:auto' });
        var tag = E('input', { 'class': 'cbi-input-text', placeholder: 'latest', value: 'latest' });
        var update, rollback, pending = false;
        function refresh(state) {
            current.textContent = state.current || '无法读取';
            previous.textContent = state.previous || '暂无';
            message.textContent = state.message || '';
            log.textContent = state.log || '暂无操作日志。';
            update.disabled = rollback.disabled = pending || !!state.busy || !L.hasViewPermission();
            if (!state.previous) rollback.disabled = true;
            tag.disabled = pending || !!state.busy;
        }
        function perform(action) {
            var version = tag.value.trim() || 'latest';
            if (action === 'update' && version !== 'latest' && !/^v[0-9][A-Za-z0-9.+_-]*-reF1nd$/.test(version)) {
                ui.addNotification(null, E('p', '请输入 latest 或完整发布标签，例如 v1.14.4-reF1nd。'), 'error');
                return;
            }
            ui.showModal(action === 'rollback' ? '回退内核' : '更新 reF1nd 内核', [
                E('p', '操作会短暂中断代理连接。新内核将先检查当前 momo 配置，启动检查失败时会尝试恢复原内核。'),
                E('div', { 'class': 'right' }, [
                    E('button', { 'class': 'btn', click: ui.hideModal }, '取消'),
                    ' ',
                    E('button', { 'class': 'btn cbi-button-action', click: function() {
                        ui.hideModal();
                        pending = true;
                        update.disabled = rollback.disabled = true;
                        start(action, action === 'rollback' ? 'latest' : version).then(function(result) {
                            if (!result.accepted) throw new Error(result.message || '操作未接受');
                            message.textContent = '操作已开始，正在获取进度……';
                        }).catch(function(err) {
                            ui.addNotification(null, E('p', String(err)), 'error');
                        }).finally(function() {
                            pending = false;
                            getStatus().then(refresh).catch(function() {});
                        });
                    } }, '确认')
                ])
            ]);
        }
        update = E('button', { 'class': 'btn cbi-button-action', click: function() { perform('update'); } }, '更新 reF1nd 内核');
        rollback = E('button', { 'class': 'btn', click: function() { perform('rollback'); } }, '回退上一版');
        refresh(data);
        poll.add(function() { return getStatus().then(refresh); }, 3);
        return E('div', {}, [
            E('h2', 'momo · reF1nd 内核管理'),
            E('p', '仅使用 reF1nd/sing-box-releases 的 ARM64 musl 正式发布，校验 SHA-256 后安装。请先确保 momo 正常运行。'),
            E('p', {}, ['当前内核：', current]),
            E('p', {}, ['可回退内核：', previous]),
            E('p', {}, ['目标版本：', tag]),
            E('p', 'latest 表示最新正式发布；也可填写完整版本标签。更新重启后保留，重刷固件后以新固件预装版本为准。'),
            E('div', {}, [update, ' ', rollback]),
            message,
            E('h3', '操作日志'), log
        ]);
    },
    handleSave: null,
    handleSaveApply: null,
    handleReset: null
});
