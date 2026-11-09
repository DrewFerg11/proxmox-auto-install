// Run with: node --test tests/first-boot.test.mjs (requires Node 18+ and Bash).
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

const repo = new URL('../', import.meta.url);
const source = (name) => readFileSync(new URL(name, repo), 'utf8').replaceAll('\r\n', '\n');
const desktop = "if (data.status !== 'active') { showNag(); }\n";
const mobile = '<html>\n<head>\n</head>\n<body></body>\n</html>\n';

test('all installation scripts have valid Bash syntax', () => {
  for (const file of ['create-iso.sh', 'first-boot-pve.sh', 'first-boot-pbs.sh']) {
    execFileSync('bash', ['-n'], { input: source(file) });
  }
});

// Redirect every host filesystem path into a temporary fixture. Package
// installation and reboot are functions, so no host changes are performed.
for (const type of ['pve', 'pbs']) {
  for (const template of [undefined, '', mobile]) {
    test(`${type} first boot with mobile UI ${template === undefined ? 'absent' : template === '' ? 'empty' : 'present'}`, (t) => {
      const dir = mkdtempSync(join(tmpdir(), 'proxmox-first-boot-'));
      t.after(() => {
        assert.equal(dirname(resolve(dir)), resolve(tmpdir()));
        rmSync(dir, { recursive: true, force: true });
      });
      const put = (path, value) => {
        const target = join(dir, 'root', path);
        mkdirSync(dirname(target), { recursive: true });
        writeFileSync(target, value);
      };
      const get = (path) => readFileSync(join(dir, 'root', path), 'utf8');
      const jsPath = 'usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js';
      const tplPath = 'usr/share/pve-yew-mobile-gui/index.html.tpl';
      const enterprise = `etc/apt/sources.list.d/${type}-enterprise.sources`;
      mkdirSync(join(dir, 'root/etc/apt/apt.conf.d'), { recursive: true });
      put(enterprise, `Types: deb\nComponents: ${type}-enterprise\n`);
      put(jsPath, desktop);
      if (template !== undefined) put(tplPath, template);
      const script = source(`first-boot-${type}.sh`)
        .replaceAll('/etc/', './root/etc/')
        .replaceAll('/usr/', './root/usr/');
      const mocks = `
apt-get() {
    printf '%s\\n' "$*" >> calls.log
    # Simulate DPkg::Post-Invoke on install and upgrade.
    case "$*" in
        *install*|*dist-upgrade*) sh -eu ./root/usr/local/bin/pve-remove-nag.sh ;;
    esac
}
reboot() { echo reboot >> calls.log; }
`;
      writeFileSync(join(dir, 'first-boot.sh'), mocks + script);
      const run = () => execFileSync('bash', ['-eu', 'first-boot.sh'], { cwd: dir });
      run();
      assert.match(get(enterprise), /Enabled: false/);
      assert.match(get('etc/apt/sources.list.d/proxmox.sources'), new RegExp(`Components: ${type}-no-subscription`));
      assert.match(get(jsPath), /data\.status == 'NoMoreNagging'/);
      assert.match(get('etc/apt/apt.conf.d/no-nag-script'), /DPkg::Post-Invoke/);
      assert.deepEqual(readFileSync(join(dir, 'calls.log'), 'utf8').trim().split('\n'), [
        '--reinstall install -y proxmox-widget-toolkit',
        'update', '-y -o Dpkg::Options::=--force-confold dist-upgrade', 'reboot',
      ]);
      if (template !== undefined) {
        if (type === 'pve' && template) {
          assert.match(get(tplPath), /<head>\n  <script>/);
          assert.equal((get(tplPath).match(/\/\/ NoMoreNagging/g) || []).length, 1);
        } else {
          assert.equal(get(tplPath), template);
        }
      }
      const patched = template === undefined ? undefined : get(tplPath);
      run();
      if (template !== undefined) assert.equal(get(tplPath), patched, 'reruns must not duplicate patches');

      // Simulate a package overwriting both UI assets, then execute the hook.
      put(jsPath, desktop);
      if (template) put(tplPath, mobile);
      execFileSync('sh', ['-eu', './root/usr/local/bin/pve-remove-nag.sh'], { cwd: dir });
      assert.match(get(jsPath), /NoMoreNagging/);
      if (template !== undefined) assert.equal(get(tplPath), patched);
    });
  }
}

const injected = source('first-boot-pve.sh').match(/  <script>\n([\s\S]*?)  <\/script>/)[1];
function wrapper(response) {
  const calls = [];
  const window = { fetch: async (...args) => {
    calls.push(args);
    if (response instanceof Error) throw response;
    return response;
  } };
  vm.runInNewContext(injected, { window, URL, Response, location: { href: 'https://pve.example/' } });
  return { fetch: window.fetch, calls };
}

test('mobile wrapper patches both nodes APIs and preserves subscribed nodes and request arguments', async () => {
  for (const path of ['/api2/json/nodes', '/api2/extjs/nodes']) {
    for (const input of [path, new URL(path, 'https://pve.example/'), new Request(`https://pve.example${path}`)]) {
      const response = Response.json({ data: [{ node: 'free', level: '' }, { node: 'paid', level: 's' }] });
      const { fetch, calls } = wrapper(response);
      const options = { credentials: 'include' };
      const result = await fetch(input, options);
      assert.deepEqual(calls, [[input, options]]);
      assert.equal(result.status, response.status);
      assert.equal(result.headers.get('content-type'), response.headers.get('content-type'));
      assert.deepEqual((await result.json()).data, [{ node: 'free', level: 'NoMoreNagging' }, { node: 'paid', level: 's' }]);
      assert.equal((await response.json()).data[0].level, '', 'original response is unchanged');
    }
  }
});

test('mobile wrapper passes through unrelated, malformed and unexpected responses', async () => {
  for (const [path, response] of [
    ['/api2/json/nodes/pve/status', Response.json({ data: {} })],
    ['/api2/json/access/ticket', Response.json({ data: { ticket: 'unchanged' } })],
    ['/api2/json/nodes', new Response('not JSON', { status: 500 })],
    ['/api2/json/nodes', Response.json({ data: {} })],
    ['/api2/json/nodes', Response.json(null)],
  ]) {
    assert.equal(await wrapper(response).fetch(path), response);
    assert.equal(response.bodyUsed, false);
  }
  const error = new Error('network failure');
  await assert.rejects(wrapper(error).fetch('/api2/json/nodes'), (actual) => actual === error);
});
