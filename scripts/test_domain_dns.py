import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

from dnslib import DNSRecord, RR, QTYPE, RCODE, A, AAAA, CNAME, HTTPS
from domain_dns import DomainResolver, Routes, GATEWAY, in_zone


class DomainTests(unittest.TestCase):
    def resolver(self, answer):
        routes = Mock()
        resolver = DomainResolver(routes)
        resolver.upstream = Mock(return_value=answer)
        return resolver, routes

    def test_domain_boundary(self):
        for name in ('gov.ru', 'GOV.RU.', 'one.two.gov.ru',
                     'gosuslugi.ru', 'GOSUSLUGI.RU.', 'esia.gosuslugi.ru', 'one.two.gosuslugi.ru',
                     'example.ru', 'notgov.ru', 'notgosuslugi.ru', 'one.two.ru',
                     'пример.рф', 'ПРИМЕР.РФ.', 'one.xn--p1ai', 'one.two.xn--p1ai',
                     'tbank-online.com', 'TBANK-ONLINE.COM.', 'one.two.tbank-online.com',
                     'codenrock.com', 'CODENROCK.COM.', 'one.two.codenrock.com'):
            self.assertTrue(in_zone(name))
        for name in ('example.com', 'gov.ru.example.org', 'gosuslugi.ru.example.org',
                     'example.notru', 'example.ru.com', 'example.notxn--p1ai',
                     'one.xn--p1ai.com', 'пример.рф.com', 'nottbank-online.com',
                     'tbank-online.com.example.org', 'tbank-online.net',
                     'notcodenrock.com', 'codenrock.com.example.org', 'codenrock.net'):
            self.assertFalse(in_zone(name))
            question = DNSRecord.question(name)
            resolver, _ = self.resolver(question.reply())
            self.assertEqual(resolver.resolve(question, None).header.rcode, RCODE.REFUSED)
            resolver.upstream.assert_not_called()

    def test_idn_dns_wire_name_gets_routes(self):
        question = DNSRecord.parse(DNSRecord.question('пример.рф').pack())
        answer = question.reply()
        answer.add_answer(RR(question.q.qname, QTYPE.A, ttl=60, rdata=A('95.173.128.90')))
        resolver, routes = self.resolver(answer)
        response = resolver.resolve(question, None)
        self.assertEqual(response.header.rcode, RCODE.NOERROR)
        routes.ensure.assert_called_once_with({'95.173.128.90'}, retention=86460)

    def test_routes_exist_before_address_is_returned(self):
        question = DNSRecord.question('codenrock.com')
        answer = question.reply()
        answer.add_answer(RR('codenrock.com', QTYPE.A, ttl=172800, rdata=A('95.173.128.90')))
        resolver, routes = self.resolver(answer)
        result = resolver.resolve(question, None)
        self.assertEqual(result.header.rcode, RCODE.NOERROR)
        routes.ensure.assert_called_once_with({'95.173.128.90'}, retention=259200)
        routes.ensure.side_effect = RuntimeError('route installation failed')
        failed = resolver.resolve(question, None)
        self.assertEqual(failed.header.rcode, RCODE.SERVFAIL)
        self.assertFalse(failed.rr)

    def test_external_cname_is_resolved_before_return(self):
        question = DNSRecord.question('www.gosuslugi.ru')
        answer = question.reply()
        answer.add_answer(RR('www.gosuslugi.ru', QTYPE.CNAME, rdata=CNAME('edge.example.org')))
        target = DNSRecord.question('edge.example.org').reply()
        target.add_answer(RR('edge.example.org', QTYPE.A, rdata=A('95.173.128.90')))
        resolver, routes = self.resolver(answer)
        resolver.upstream.side_effect = [answer, target]
        result = resolver.resolve(question, None)
        self.assertEqual(len(result.rr), 2)
        self.assertEqual(routes.ensure.call_args.args[0], {'95.173.128.90'})

    def test_ipv6_cannot_bypass_and_ech_is_preserved(self):
        question = DNSRecord.question('gov.ru', 'AAAA')
        resolver, _ = self.resolver(question.reply())
        result = resolver.resolve(question, None)
        self.assertEqual(result.header.rcode, RCODE.NOERROR)
        self.assertFalse(result.rr)
        resolver.upstream.assert_not_called()
        question = DNSRecord.question('gov.ru', 'HTTPS')
        answer = question.reply()
        record = HTTPS.fromZone(['1', '.', 'ipv4hint=95.173.128.90',
                                 'echconfig=Z2FyYmFnZQ==', 'ipv6hint=2606:4700::1111'])
        answer.add_answer(RR('gov.ru', QTYPE.HTTPS, rdata=record))
        answer.add_ar(RR('gov.ru', QTYPE.AAAA, rdata=AAAA('2606:4700::1111')))
        resolver, routes = self.resolver(answer)
        result = resolver.resolve(question, None)
        parsed = DNSRecord.parse(result.pack())
        self.assertEqual({key for key, _ in parsed.rr[0].rdata.params}, {4, 5})
        self.assertFalse(parsed.ar)
        self.assertEqual(routes.ensure.call_args.args[0], {'95.173.128.90'})

    def test_private_addresses_are_rejected(self):
        with tempfile.TemporaryDirectory() as work:
            routes = Routes(Path(work) / 'routes.json', dry_run=True)
            with self.assertRaises(ValueError):
                routes.ensure({'192.168.1.1'})

    def test_only_kernel_clone_is_removed(self):
        with tempfile.TemporaryDirectory() as work:
            routes = Routes(Path(work) / 'routes.json')
            routes.lookup = Mock(side_effect=[
                {'interface': 'bridge101', 'flags': '<HOST,LLINFO>'},
                {'flags': '<HOST,WASCLONED,IFSCOPE>', 'interface': 'utun5'},
                {'gateway': GATEWAY, 'interface': 'bridge101'},
            ])
            routes.command = Mock(return_value=Mock(returncode=0, stderr=''))
            self.assertTrue(routes.install('95.173.128.90'))
            self.assertEqual(routes.command.call_args_list[0].args,
                             ('delete', '-host', '-ifscope', 'utun5', '95.173.128.90'))
            routes.lookup.side_effect = [
                {'interface': 'bridge101', 'flags': '<HOST,LLINFO>'},
                {'flags': '<HOST,STATIC>', 'interface': 'utun5'}, {'gateway': 'other'}]
            routes.command.reset_mock()
            with self.assertRaises(RuntimeError):
                routes.install('95.173.128.90')
            self.assertFalse(any(call.args[0] == 'delete' for call in routes.command.call_args_list))

    def test_vm_restart_repairs_only_owned_host_route_on_wrong_interface(self):
        with tempfile.TemporaryDirectory() as work:
            routes = Routes(Path(work) / 'routes.json')
            address = '95.173.128.90'
            stale = {'gateway': GATEWAY, 'interface': 'en0', 'destination': address, 'flags': '<HOST,STATIC>'}
            bridge = {'interface': 'bridge102', 'flags': '<HOST,LLINFO>'}
            healthy = {'gateway': GATEWAY, 'interface': 'bridge102'}
            routes.entries[address] = {'owned': True}
            routes.lookup = Mock(side_effect=[bridge, stale, healthy])
            routes.command = Mock(return_value=Mock(returncode=0, stderr=''))
            self.assertTrue(routes.install(address))
            self.assertEqual([call.args for call in routes.command.call_args_list],
                             [('delete', '-host', address, GATEWAY), ('add', '-host', address, GATEWAY)])
            routes.lookup.side_effect = [bridge, healthy]
            routes.command.reset_mock()
            self.assertFalse(routes.install(address))
            routes.command.assert_not_called()
            for owned, destination in ((False, address), (True, '95.173.128.0')):
                routes.entries[address] = {'owned': owned}
                routes.lookup.side_effect = [bridge, dict(stale, destination=destination)]
                with self.assertRaises(RuntimeError):
                    routes.install(address)
                routes.command.assert_not_called()

    def test_absent_vm_bridge_never_creates_route_through_vpn_or_en0(self):
        with tempfile.TemporaryDirectory() as work:
            routes = Routes(Path(work) / 'routes.json')
            routes.command = Mock()
            for gateway in ({'interface': 'en0'}, {'interface': 'utun5'},
                            {'interface': 'bridge101', 'flags': '<GATEWAY,HOST>'}):
                routes.lookup = Mock(return_value=gateway)
                with self.assertRaises(RuntimeError):
                    routes.install('95.173.128.90')
                routes.command.assert_not_called()

    def test_route_verification_checks_interface_not_just_gateway(self):
        with tempfile.TemporaryDirectory() as work:
            routes = Routes(Path(work) / 'routes.json')
            routes.lookup = Mock(side_effect=[
                {'interface': 'bridge101'}, {'interface': 'utun5'},
                {'gateway': GATEWAY, 'interface': 'en0'}])
            routes.command = Mock(return_value=Mock(returncode=0, stderr=''))
            with self.assertRaises(RuntimeError):
                routes.install('95.173.128.90')

    def test_cleanup_preserves_other_routes(self):
        with tempfile.TemporaryDirectory() as work:
            routes = Routes(Path(work) / 'routes.json')
            routes.command = Mock()
            routes.lookup = Mock(return_value={'gateway': GATEWAY, 'flags': '<STATIC>', 'destination': '95.173.128.0'})
            routes.remove_entry('95.173.128.90', {'owned': True})
            routes.command.assert_not_called()
            routes.lookup.return_value = {'gateway': GATEWAY, 'flags': '<HOST,STATIC>', 'destination': '95.173.128.90'}
            routes.remove_entry('95.173.128.90', {'owned': False})
            routes.command.assert_not_called()
            routes.remove_entry('95.173.128.90', {'owned': True})
            routes.command.assert_called_once_with('delete', '-host', '95.173.128.90', GATEWAY)


if __name__ == '__main__':
    unittest.main()
