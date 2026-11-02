"""Offline integration tests. All privileged paths and commands use a temp sandbox."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import shutil
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'Scripts/refind/root/usr/libexec'


class RefindTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'mock-bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', TEST_ROOT=str(self.root))
        self.write('mock-bin/curl', '''#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in https://*) url=$1;; -o) shift; out=$1;; esac
 shift
done
case "$url" in
 https://api.github.com/repos/reF1nd/sing-box-releases/releases/*) cp "$TEST_ROOT/release.json" "$out";;
 https://github.com/reF1nd/sing-box-releases/releases/download/*) [ ! -f "$TEST_ROOT/download-fail" ] && cp "$TEST_ROOT/asset.tar.gz" "$out";;
 *) exit 99;;
esac
''')
        self.fixture()
        self.write('usr/libexec/momo-refind-download', (LIB / 'momo-refind-download').read_text())
        manager = (LIB / 'momo-refind').read_text()
        # Rewrite absolute target paths in the test copy, never in production.
        for directory in ['/usr/bin/', '/usr/libexec/', '/etc/', '/var/', '/lib/']:
            manager = manager.replace(directory, str(self.root) + directory)
        self.manager = self.write('usr/libexec/momo-refind', manager)
        for directory in ['var/lock', 'var/run', 'var/log', 'etc/momo/refind-core', 'etc/momo/run']:
            (self.root / directory).mkdir(parents=True, exist_ok=True)
        self.write('usr/bin/sing-box', self.binary('1.0-reF1nd'))
        self.write('lib/ld-musl-aarch64.so.1', '')
        self.write('etc/momo/run/config.json', '{}')
        self.write('etc/momo/refind-core/current.json', '{"version":"v1.0-reF1nd"}')
        self.write('mock-bin/uname', '#!/bin/sh\necho aarch64\n')
        self.write('mock-bin/sleep', '#!/bin/sh\nexit 0\n')
        self.write('mock-bin/pidof', '#!/bin/sh\n[ -f "$TEST_ROOT/running" ] && echo 321\n')
        self.write('mock-bin/ubus', '''#!/bin/sh
if [ -f "$TEST_ROOT/running" ]; then
 echo '{"momo":{"instances":{"momo":{"running":true,"pid":321}}}}'
else
 echo '{"momo":{"instances":{"momo":{"running":false}}}}'
fi
''')
        self.write('etc/init.d/momo', '''#!/bin/sh
case "$1" in
 stop) rm -f "$TEST_ROOT/running";;
 start) if ! grep -q broken-start "$TEST_ROOT/usr/bin/sing-box"; then touch "$TEST_ROOT/running"; fi;;
esac
''')
        (self.root / 'running').touch()

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)
        return path

    def binary(self, version, bad_config=False, broken_start=False):
        return f'''#!/bin/sh
# {'broken-start' if broken_start else 'healthy-start'}
if [ "$1" = version ]; then echo 'sing-box version {version}'; exit 0; fi
exit {1 if bad_config else 0}
'''

    def fixture(self, version='1.1-reF1nd', bad_config=False, broken_start=False, traversal=False, payload=None):
        tag = 'v' + version
        name = f'sing-box-{version}-linux-arm64-musl.tar.gz'
        binary = payload if payload is not None else self.binary(version, bad_config, broken_start).encode()
        with tarfile.open(self.root / 'asset.tar.gz', 'w:gz') as archive:
            member = tarfile.TarInfo('../sing-box' if traversal else f'sing-box-{version}-linux-arm64/sing-box')
            member.size = len(binary)
            archive.addfile(member, io.BytesIO(binary))
        digest = hashlib.sha256((self.root / 'asset.tar.gz').read_bytes()).hexdigest()
        self.release = {'tag_name': tag, 'draft': False, 'prerelease': False, 'assets': [{
            'name': name,
            'browser_download_url': f'https://github.com/reF1nd/sing-box-releases/releases/download/{tag}/{name}',
            'digest': 'sha256:' + digest}]}
        self.save_release()

    def save_release(self):
        (self.root / 'release.json').write_text(json.dumps(self.release))

    def download(self, tag='latest', arch='arm64'):
        return subprocess.run(['sh', str(LIB / 'momo-refind-download'), tag, arch, str(self.root / 'out')],
                              env=self.env, capture_output=True, text=True)

    def worker(self, action='update'):
        (self.root / 'var/lock/momo-refind').mkdir(exist_ok=True)
        return subprocess.run(['sh', str(self.manager), 'worker', action, 'latest'],
                              env=self.env, capture_output=True, text=True)

    def status(self):
        return json.loads((self.root / 'var/run/momo-refind.json').read_text())

    def test_verified_download(self):
        result = self.download()
        self.assertEqual(result.returncode, 0, result.stderr)
        meta = json.loads((self.root / 'out/release-meta.json').read_text())
        self.assertEqual(meta['version'], 'v1.1-reF1nd')
        self.assertEqual(meta['binary_sha256'], hashlib.sha256((self.root / 'out/sing-box').read_bytes()).hexdigest())

    def test_corrupt_download_rejected(self):
        (self.root / 'asset.tar.gz').write_bytes(b'corrupt')
        self.assertNotEqual(self.download().returncode, 0)
        self.assertFalse((self.root / 'out/sing-box').exists())

    def test_missing_digest_rejected(self):
        self.release['assets'][0]['digest'] = None
        self.save_release()
        self.assertNotEqual(self.download().returncode, 0)

    def test_no_glibc_fallback(self):
        self.release['assets'][0]['name'] = self.release['assets'][0]['name'].replace('musl', 'glibc')
        self.save_release()
        self.assertNotEqual(self.download().returncode, 0)

    def test_invalid_tag_and_arch_rejected(self):
        self.assertNotEqual(self.download(tag='v1;touch /tmp/pwn').returncode, 0)
        self.assertNotEqual(self.download(tag='v1-reF1nd\ninvalid').returncode, 0)
        self.assertNotEqual(self.download(arch='mips').returncode, 0)

    def test_traversal_member_rejected(self):
        self.fixture(traversal=True)
        self.assertNotEqual(self.download().returncode, 0)
        self.assertFalse((self.root / 'out/sing-box').exists())

    def test_update_and_rollback(self):
        result = self.worker()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.status()['state'], 'success')
        self.assertIn('1.1-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertIn('1.0-reF1nd', (self.root / 'etc/momo/refind-core/previous').read_text())
        result = self.worker('rollback')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('1.0-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertIn('1.1-reF1nd', (self.root / 'etc/momo/refind-core/previous').read_text())

    def test_download_failure_keeps_current_service(self):
        (self.root / 'download-fail').touch()
        self.assertNotEqual(self.worker().returncode, 0)
        self.assertIn('1.0-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertTrue((self.root / 'running').exists())
        self.assertEqual(self.status()['state'], 'error')

    def test_invalid_config_keeps_current_service(self):
        self.fixture(bad_config=True)
        self.assertNotEqual(self.worker().returncode, 0)
        self.assertIn('1.0-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertTrue((self.root / 'running').exists())

    def test_start_failure_automatically_recovers(self):
        self.fixture(broken_start=True)
        result = self.worker()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('1.0-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertTrue((self.root / 'running').exists())
        self.assertIn('已恢复', self.status()['message'])
        self.assertFalse((self.root / 'var/lock/momo-refind').exists())

    def test_lock_prevents_concurrent_updates(self):
        (self.root / 'var/lock/momo-refind').mkdir()
        result = subprocess.run(['sh', str(self.manager), 'start', 'update', 'latest'],
                                env=self.env, capture_output=True, text=True)
        self.assertFalse(json.loads(result.stdout)['accepted'])

    def test_no_backup_rollback_is_safe(self):
        self.assertNotEqual(self.worker('rollback').returncode, 0)
        self.assertIn('1.0-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertTrue((self.root / 'running').exists())

    @unittest.skipUnless(shutil.which('cc') and shutil.which('readelf'), 'ELF build tools required')
    def test_ci_installs_verified_core_and_updater(self):
        executable = self.root / 'elf'
        subprocess.run(['cc', '-static', '-x', 'c', '-', '-o', str(executable)],
                       input='int main(void) { return 0; }', text=True, check=True, capture_output=True)
        binary = bytearray(executable.read_bytes())
        binary[18:20] = (183).to_bytes(2, 'little')  # AArch64 header fixture, not executed.
        self.fixture(payload=bytes(binary))
        wrt = self.root / 'wrt'
        wrt.mkdir()
        (wrt / '.config').write_text('CONFIG_aarch64=y\n')
        env = dict(self.env, WRT_CONFIG='IPQ60XX-WIFI-NO')
        result = subprocess.run(['bash', str(ROOT / 'Scripts/Refind-Install.sh'), str(wrt)],
                                env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((wrt / 'files/usr/bin/sing-box').read_bytes(), bytes(binary))
        for name in ['momo-refind', 'momo-refind-download', 'rpcd/momo.refind']:
            self.assertTrue(os.access(wrt / 'files/usr/libexec' / name, os.X_OK))
        self.assertTrue((wrt / 'files/www/luci-static/resources/view/momo/refind.js').is_file())

    def test_ci_rejects_non_elf_payload(self):
        wrt = self.root / 'wrt'
        wrt.mkdir()
        (wrt / '.config').write_text('CONFIG_aarch64=y\n')
        result = subprocess.run(['bash', str(ROOT / 'Scripts/Refind-Install.sh'), str(wrt)],
                                env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((wrt / 'files/usr/bin/sing-box').exists())

    def test_binary_version_mismatch_keeps_current(self):
        self.fixture(payload=self.binary('9.9-reF1nd').encode())
        self.assertNotEqual(self.worker().returncode, 0)
        self.assertIn('1.0-reF1nd', (self.root / 'usr/bin/sing-box').read_text())
        self.assertTrue((self.root / 'running').exists())

    def test_rpc_protocol_and_async_start(self):
        import time
        import signal
        # OpenWrt need not ship nohup. Fail loudly if the launcher still calls it.
        self.write('mock-bin/nohup', '#!/bin/sh\ntouch "$TEST_ROOT/nohup-used"\nexit 127\n')
        # Keep the worker alive long enough to test rpcd/session hangup handling.
        downloader = self.root / 'usr/libexec/momo-refind-download'
        downloader.rename(downloader.with_name('download-real'))
        self.write('usr/libexec/momo-refind-download', '''#!/bin/sh
touch "$TEST_ROOT/download-ready"
/bin/sleep 0.5
exec "$TEST_ROOT/usr/libexec/download-real" "$@"
''')
        plugin = (LIB / 'rpcd/momo.refind').read_text().replace('/usr/libexec/', str(self.root) + '/usr/libexec/')
        rpc = self.write('rpc-plugin', plugin)
        result = subprocess.run(['sh', str(rpc), 'list'], env=self.env, capture_output=True, text=True, check=True)
        self.assertEqual(set(json.loads(result.stdout)), {'status', 'start'})
        result = subprocess.run(['sh', str(rpc), 'call', 'start'], input='{"action":"update","version":"latest"}',
                                env=self.env, capture_output=True, text=True, check=True)
        self.assertTrue(json.loads(result.stdout)['accepted'])
        for _ in range(100):
            if (self.root / 'download-ready').exists():
                break
            time.sleep(0.01)
        self.assertTrue((self.root / 'download-ready').exists())
        pid = int((self.root / 'var/lock/momo-refind/pid').read_text())
        os.kill(pid, signal.SIGHUP)
        for _ in range(200):
            if not (self.root / 'var/lock/momo-refind').exists():
                break
            time.sleep(0.02)
        self.assertFalse((self.root / 'var/lock/momo-refind').exists())
        result = subprocess.run(['sh', str(rpc), 'call', 'status'], env=self.env, capture_output=True, text=True, check=True)
        state = json.loads(result.stdout)
        self.assertEqual(state['state'], 'success', state)
        self.assertFalse(state['busy'])
        self.assertFalse((self.root / 'nohup-used').exists())


if __name__ == '__main__':
    unittest.main()
