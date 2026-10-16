"""Exercise host-helper migration and route ownership without privileged commands."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).with_name('host_direct_routes.sh').read_text()
MOCKS = r'''
id() { echo 0; }
ifconfig() { printf 'bridge101: flags=UP\n\tinet 192.168.64.1 netmask 0xffffff00\n'; }
ping() { test -f "$MOCK_ROOT/link"; }
pfctl() { echo "pfctl $*" >> "$MOCK_ROOT/calls"; }
route() {
  echo "route $*" >> "$MOCK_ROOT/calls"
  case "$*" in
    '-n get 192.168.64.2')
      echo 'interface: bridge101'
      if [[ -f "$MOCK_ROOT/link" ]]; then echo 'gateway: link#30'; else echo 'gateway: 192.168.64.2'; fi ;;
    '-n get 203.0.113.0')
      if [[ -f "$MOCK_ROOT/net" ]]; then echo 'gateway: 192.168.64.2'; else echo 'gateway: other'; fi ;;
    '-n add -host 192.168.64.2 -interface bridge101') touch "$MOCK_ROOT/link" ;;
    '-n add -net 203.0.113.0/24 192.168.64.2')
      [[ "${MOCK_CONFLICT:-}" != 1 ]] || return 1
      touch "$MOCK_ROOT/net" ;;
    '-n delete -net -ifscope bridge101 0.0.0.0/1 192.168.64.2') ;;
    '-n delete -net -ifscope bridge101 128.0.0.0/1 192.168.64.2') ;;
    *) echo "Unexpected route command: $*" >&2; return 99 ;;
  esac
}
'''


class HostRouteTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)
        (self.root / 'state').mkdir()
        (self.root / 'data').write_text('203.0.113.0/24\n')
        (self.root / 'mocks').write_text(MOCKS)
        self.helper = self.root / 'helper'
        self.helper.write_text(SOURCE.replace('/private/var/run/lazylead-direct-routes', str(self.root / 'state'))
                              .replace('/opt/lazylead-direct/yandex-cloud-ipv4.txt', str(self.root / 'data')))

    def run_helper(self, conflict=False):
        result = subprocess.run(['bash', str(self.helper), 'install'], capture_output=True, text=True,
                                env={**os.environ, 'BASH_ENV': str(self.root / 'mocks'),
                                     'MOCK_ROOT': str(self.root), 'MOCK_CONFLICT': '1' if conflict else '0'})
        self.assertNotIn('Unexpected route command', result.stderr)
        return result

    def test_fresh_install_is_idempotent_and_uses_no_pf(self):
        (self.root / 'link').touch()
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(self.run_helper().returncode, 0)
        calls = (self.root / 'calls').read_text()
        self.assertEqual(calls.count('route -n add -net'), 1)
        self.assertNotIn('pfctl', calls)
        self.assertEqual((self.root / 'state/installed-prefixes').read_text(), '203.0.113.0/24\n')

    def test_legacy_binding_removed_before_restoring_vm_link(self):
        (self.root / 'state/scoped-bridge').write_text('bridge101\n')
        (self.root / 'state/applied.pf').write_text('old private anchor\n')
        (self.root / 'state/pf-token').write_text('123\n')
        self.assertEqual(self.run_helper().returncode, 0)
        calls = (self.root / 'calls').read_text()
        self.assertIn('pfctl -a com.apple/lazylead-direct -F rules', calls)
        self.assertIn('pfctl -X 123', calls)
        self.assertLess(calls.index('delete -net -ifscope'), calls.index('add -host'))
        self.assertLess(calls.index('add -host'), calls.index('add -net'))
        self.assertTrue((self.root / 'link').exists())
        self.assertFalse((self.root / 'state/scoped-bridge').exists())

    def test_conflict_is_not_claimed_or_overwritten(self):
        (self.root / 'link').touch()
        self.assertNotEqual(self.run_helper(conflict=True).returncode, 0)
        self.assertEqual((self.root / 'state/installed-prefixes').read_text(), '')
        self.assertNotIn('delete -net', (self.root / 'calls').read_text())
        self.assertFalse((self.root / 'state/lock').exists())


if __name__ == '__main__':
    unittest.main()
