// Exercise the LuCI view with a minimal DOM/RPC adapter, without a router.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../Scripts/refind/root/www/luci-static/resources/view/momo/refind.js'), 'utf8');
const state = { current: 'sing-box version 1.1-reF1nd', previous: '', busy: false, log: '<script>untrusted</script>' };
let allowed = true, modal, requests = [], poll;
function E(tag, attrs, children) {
    if (Array.isArray(attrs) || typeof attrs === 'string' || attrs == null) {
        children = attrs;
        attrs = {};
    }
    return { tag, attrs, children: Array.isArray(children) ? children : [children], value: attrs.value || '', textContent: '' };
}
const ui = { showModal: (title, nodes) => { modal = nodes; }, hideModal() {}, addNotification() {} };
const rpc = { declare: spec => spec.method === 'status'
    ? () => Promise.resolve(state)
    : (action, version) => { requests.push([action, version]); return Promise.resolve({accepted: true}); } };
const view = new Function('view', 'rpc', 'ui', 'poll', 'E', 'L', source)(
    {extend: x => x}, rpc, ui, {add: fn => {poll = fn;}}, E, {hasViewPermission: () => allowed});
function all(node) {
    return node && typeof node === 'object' ? [node, ...(node.children || []).flatMap(all)] : [];
}
async function main() {
    let dom = view.render(await view.load());
    let nodes = all(dom), buttons = nodes.filter(x => x.tag === 'button');
    assert.equal(buttons[0].disabled, false);
    assert.equal(buttons[1].disabled, true);
    assert.equal(nodes.find(x => x.tag === 'pre').textContent, '<script>untrusted</script>');
    buttons[0].attrs.click();
    all({children: modal}).filter(x => x.tag === 'button')[1].attrs.click();
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(requests, [['update', 'latest']]);
    state.busy = true;
    await poll();
    assert.equal(buttons[0].disabled, true);
    state.busy = false; state.previous = 'sing-box version 1.0-reF1nd';
    await poll();
    assert.equal(buttons[1].disabled, false);
    buttons[1].attrs.click();
    all({children: modal}).filter(x => x.tag === 'button')[1].attrs.click();
    await new Promise(resolve => setImmediate(resolve));
    assert.deepEqual(requests[1], ['rollback', 'latest']);
    allowed = false;
    dom = view.render(state);
    assert.ok(all(dom).filter(x => x.tag === 'button').every(x => x.disabled));
    console.log('LuCI view: update, rollback, polling, text escaping and read-only controls passed.');
}
main().catch(err => { console.error(err); process.exitCode = 1; });
