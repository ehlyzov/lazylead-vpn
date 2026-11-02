import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

import routing_rules as rules
import routing_control as control
from domain_dns import Routes, PrefixRoutes, DomainResolver, GATEWAY
from dnslib import DNSRecord, RCODE


class RulesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'rules.json'
        p = patch.object(rules, 'CONFIG', self.config)
        p.start(); self.addCleanup(p.stop)

    def save(self, domains=(), networks=()):
        self.config.write_text(json.dumps({'version': 1, 'domains': list(domains), 'networks': list(networks)}))

    def test_validation_and_idna(self):
        self.assertEqual(rules.domain('*.Пример.РФ.'), 'xn--e1afmkfd.xn--p1ai')
        self.assertEqual(rules.network('8.8.8.9/24'), '8.8.8.0/24')
        self.assertEqual(rules.network('8.8.8.8'), '8.8.8.8')
        for value in ('https://a.com', 'a.com/path', '../etc', 'a;touch x', '8.8.8.8', '-bad.com', ''):
            with self.subTest(value=value), self.assertRaises(ValueError): rules.domain(value)
        for value in ('0.0.0.0/0', '172.0.0.0/8', '10.1.1.1', '192.168.64.2', '127.0.0.1', '224.0.0.1', '8.8', '::1', '8.8.8.8; id'):
            with self.subTest(value=value), self.assertRaises(ValueError): rules.network(value)

    def test_missing_defaults_but_invalid_config_fails_closed(self):
        self.assertEqual(rules.load()['domains'], list(rules.DEFAULT_DOMAINS))
        self.config.write_text('{broken')
        with self.assertRaises(ValueError): rules.load()
        resolver = DomainResolver(Mock())
        result = resolver.resolve(DNSRecord.question('yandex.ru'), None)
        self.assertEqual(result.header.rcode, RCODE.REFUSED)

    def test_hot_configuration_and_domain_boundary(self):
        self.save(['example.com'])
        resolver = DomainResolver(Mock())
        resolver.upstream = Mock(return_value=DNSRecord.question('api.example.com').reply())
        self.assertEqual(resolver.resolve(DNSRecord.question('api.example.com'), None).header.rcode, RCODE.NOERROR)
        self.save([])
        self.assertEqual(resolver.resolve(DNSRecord.question('api.example.com'), None).header.rcode, RCODE.REFUSED)
        self.assertFalse(rules.contains('example.com.evil.org', ['example.com']))

    def test_shared_dns_route_and_manual_pin(self):
        self.save(['keep.com'], ['8.8.8.8'])
        routes = Routes(self.root / 'routes.json', dry_run=True)
        routes.install = Mock(return_value=False)
        routes.remove_entry = Mock()
        routes.ensure({'8.8.8.8'}, domain='removed.com')
        routes.ensure({'8.8.8.8'}, domain='keep.com')
        routes.maintain()
        self.assertEqual(routes.entries['8.8.8.8']['names'], ['keep.com'])
        self.save([], ['8.8.8.8'])
        routes.maintain()
        self.assertIn('8.8.8.8', routes.entries)
        self.save([], [])
        routes.maintain()
        routes.remove_entry.assert_called_once()
        self.assertNotIn('8.8.8.8', routes.entries)

    def test_failed_host_removal_keeps_ownership_for_retry(self):
        self.save([])
        routes = Routes(self.root / 'routes.json')
        routes.entries = {'8.8.8.8': {'owned': True, 'expires': 0, 'names': [], 'legacy': False}}
        routes.lookup = Mock(return_value={'destination': '8.8.8.8', 'gateway': GATEWAY, 'flags': '<HOST,STATIC>'})
        routes.command = Mock(return_value=Mock(returncode=1))
        with self.assertRaisesRegex(RuntimeError, 'Could not remove owned route'):
            routes.maintain()
        self.assertTrue(routes.entries['8.8.8.8']['owned'])

    def test_legacy_lease_is_not_incorrectly_attributed(self):
        self.save([])
        routes = Routes(self.root / 'routes.json', dry_run=True)
        routes.install = Mock(return_value=False)
        routes.remove_entry = Mock()
        routes.entries = {'8.8.4.4': {'owned': True, 'expires': 9999999999}}
        routes.maintain()
        routes.maintain()
        self.assertIn('8.8.4.4', routes.entries)
        routes.remove_entry.assert_not_called()

    def test_prefix_refuses_unowned_conflict_and_preserves_external_route(self):
        p = PrefixRoutes(self.root / 'prefixes.json')
        existing = {'destination': '8.8.8.0', 'mask': '255.255.255.0', 'gateway': '1.1.1.1',
                    'interface': 'en0', 'flags': '<UP,GATEWAY,STATIC>'}
        with patch.object(Routes, 'lookup', return_value={'interface': 'bridge101', 'flags': '<HOST,LLINFO>'}):
            p.lookup = Mock(return_value=existing)
            p.command = Mock()
            with self.assertRaisesRegex(RuntimeError, 'another configuration'): p.install('8.8.8.0/24')
            p.command.assert_not_called()
            p.remove_entry('8.8.8.0/24', {'owned': True})
            p.command.assert_not_called()

    def test_prefix_rebind_and_remove_owned_only(self):
        p = PrefixRoutes(self.root / 'prefixes.json')
        p.entries = {'8.8.8.0/24': {'owned': True}}
        old = {'destination': '8.8.8.0', 'mask': '255.255.255.0', 'gateway': GATEWAY,
               'interface': 'en0', 'flags': '<UP,GATEWAY,STATIC>'}
        new = dict(old, interface='bridge101')
        p.lookup = Mock(side_effect=[old, new])
        p.command = Mock(return_value=Mock(returncode=0))
        with patch.object(Routes, 'lookup', return_value={'interface': 'bridge101', 'flags': '<HOST,LLINFO>'}):
            self.assertTrue(p.install('8.8.8.0/24'))
        self.assertEqual(p.command.call_args_list[0].args, ('delete', '-net', '8.8.8.0/24', GATEWAY))
        p.lookup = Mock(return_value=new)
        p.command.reset_mock()
        p.remove_entry('8.8.8.0/24', {'owned': False})
        p.command.assert_not_called()
        p.remove_entry('8.8.8.0/24', {'owned': True})
        p.command.assert_called_once_with('delete', '-net', '8.8.8.0/24', GATEWAY)

    def test_recovery_waits_for_new_socket(self):
        with patch.object(control, 'run') as run, patch.object(control.time, 'sleep'), \
             patch.object(control.Path, 'exists', return_value=True), \
             patch.object(control.Path, 'stat', return_value=Mock(st_mtime_ns=10, st_mode=0o140000)):
            with self.assertRaisesRegex(RuntimeError, '20 seconds'): control.repair_network()
            run.assert_called_once_with(['/bin/launchctl', 'kickstart', '-k', 'system/io.lazylead.direct-network'])

    def test_control_rolls_back_preferences_and_restarts_dns_on_failure(self):
        target = self.root / 'installed'
        state = self.root / 'state'
        resolvers = self.root / 'resolvers'
        target.mkdir(); state.mkdir(); resolvers.mkdir()
        (target / 'vendor/dnslib').mkdir(parents=True)
        self.save(['keep.com'])
        keep = resolvers / 'keep.com'
        keep.write_bytes(control.resolver_text('keep.com'))
        initial = keep.read_bytes()
        calls = []
        with patch.object(control, 'TARGET', target), patch.object(control, 'STATE', state), \
             patch.object(control, 'RESOLVERS', resolvers), patch.object(control, 'safe'), \
             patch.object(control.Path, 'is_file', return_value=True), \
             patch.object(control, 'run', side_effect=lambda args, **kw: calls.append(args)), \
             patch.object(control, 'reconcile', side_effect=[RuntimeError('route conflict'), None]):
            with self.assertRaisesRegex(RuntimeError, 'route conflict'):
                control.change('domain', 'new.com', False)
        self.assertEqual(rules.load()['domains'], ['keep.com'])
        self.assertEqual(keep.read_bytes(), initial)
        self.assertFalse((resolvers / 'new.com').exists())
        self.assertIn(['/bin/launchctl', 'bootstrap', 'system', '/Library/LaunchDaemons/io.lazylead.gov-dns.plist'], calls)

    def test_control_refuses_foreign_resolver_before_stopping_dns(self):
        target = self.root / 'installed'; target.mkdir()
        (target / 'vendor/dnslib').mkdir(parents=True)
        state = self.root / 'state'; state.mkdir()
        resolvers = self.root / 'resolvers'; resolvers.mkdir()
        (resolvers / 'new.com').write_text('nameserver 8.8.8.8\n')
        self.save([])
        with patch.object(control, 'TARGET', target), patch.object(control, 'STATE', state), \
             patch.object(control, 'RESOLVERS', resolvers), patch.object(control, 'safe'), \
             patch.object(control.Path, 'is_file', return_value=True), patch.object(control, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'another configuration'): control.change('domain', 'new.com', False)
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
