import importlib.util
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
def module(name):
 spec=importlib.util.spec_from_file_location(name,ROOT/(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
guard=module('guard');firewall=module('firewall')
class GuardTests(unittest.TestCase):
 def test_only_valid_single_ip_accepted(self):
  self.assertEqual(guard.trace_ip('ip=203.0.113.7\nloc=US'),'203.0.113.7')
  for body in ['<html>blocked</html>','ip=bad','ip=1.1.1.1\nip=8.8.8.8','ip=1.1.1.1;killall Codex']:
   self.assertIsNone(guard.trace_ip(body))
 def test_confirmed_mismatch_only(self):
  self.assertEqual(guard.classify('1.1.1.1','8.8.8.8','8.8.8.8'),'wrong_exit')
  for first,second in [(None,None),('8.8.8.8',None),('8.8.8.8','9.9.9.9'),('8.8.8.8','1.1.1.1')]:
   self.assertNotEqual(guard.classify('1.1.1.1',first,second),'wrong_exit')
 def test_timeout_does_not_mask_other_endpoint_leak(self):
  seq=iter([None,None,'8.8.8.8','8.8.8.8'])
  self.assertEqual(guard.check_service('OPENAI','1.1.1.1','utun8',lambda *_:next(seq))['status'],'wrong_exit')
 def test_good_diagnostic_cannot_override_bad_real_host(self):
  seq=iter(['8.8.8.8','8.8.8.8','1.1.1.1'])
  self.assertEqual(guard.check_service('OPENAI','1.1.1.1','utun8',lambda *_:next(seq))['status'],'wrong_exit')
 def test_no_vpn_makes_no_probe(self):
  with patch.object(guard,'vpn_interface',return_value=None),patch.object(guard,'run') as call:
   self.assertIsNone(guard.probe('https://chatgpt.com/cdn-cgi/trace','utun8'));call.assert_not_called()
 def test_render_preserves_direct_and_outer_exclusions(self):
  policy={'services':{'OPENAI':{'networks':['203.0.113.0/24'],'hosts':[]}},'direct_networks':['203.0.113.128/25'],'outer_addresses':['203.0.113.7'],'outer_hosts':['entry.example']}
  values=firewall.tables(policy,{'entry.example':{'ips':['203.0.113.8']}})
  self.assertIn('!203.0.113.7/32',values['OPENAI']);self.assertIn('!203.0.113.8/32',values['OPENAI']);self.assertIn('!203.0.113.128/25',values['OPENAI'])
  with tempfile.TemporaryDirectory() as folder:
   body=firewall.render(Path(folder),values).read_text()
   self.assertIn('utun255',body);self.assertIn('no state',body);self.assertIn('block return out quick',body)
 def test_failed_refresh_retains_cached_records(self):
  policy={'services':{'OPENAI':{'hosts':['chatgpt.com']}},'outer_hosts':[]};cache={'chatgpt.com':{'ips':['203.0.113.7'],'at':1}}
  with patch.object(firewall,'addresses',return_value=('chatgpt.com',None)):
   self.assertEqual(firewall.refresh(policy,cache)['chatgpt.com']['ips'],['203.0.113.7'])
 def test_direct_subnet_cannot_be_overridden_by_ai_host(self):
  policy={'services':{'OPENAI':{'networks':['203.0.113.0/24','203.0.113.200/32'],'hosts':[]}},'direct_networks':['203.0.113.128/25'],'outer_addresses':[],'outer_hosts':[]}
  entries=firewall.tables(policy,{})['OPENAI']
  self.assertNotIn('203.0.113.200/32',entries);self.assertIn('!203.0.113.128/25',entries)
 def test_watch_closes_only_after_confirmed_wrong_exit(self):
  import json
  import subprocess
  with tempfile.TemporaryDirectory() as folder:
   policy=Path(folder)/'policy.json';policy.write_text(json.dumps({'services':{'OPENAI':{'expected_ip':'1.1.1.1','terminate':['Codex','ChatGPT']}}}))
   for status,expected_calls in [('wrong_exit',2),('unavailable',0),('healthy',0)]:
    with patch.object(guard,'POLICY',policy),patch.object(guard,'STATE',Path(folder)),patch.object(guard,'vpn_interface',return_value='utun8'),patch.object(guard,'check_service',return_value={'service':'OPENAI','status':status}),patch.object(guard,'record'),patch.object(guard,'notify'),patch.object(guard,'run',return_value=subprocess.CompletedProcess([],0,'','')) as call:
     guard.watch(enforce=True)
     self.assertEqual(call.call_count,expected_calls)
 def test_busy_watch_is_not_a_successful_check(self):
  with tempfile.TemporaryDirectory() as folder:
   with patch.object(guard,'STATE',Path(folder)),patch.object(guard.fcntl,'flock',side_effect=BlockingIOError),patch.object(guard,'record') as record:
    self.assertEqual(guard.watch(),75);record.assert_not_called()
 def test_cached_firewall_loaded_before_dns(self):
  import json
  import subprocess
  with tempfile.TemporaryDirectory() as folder:
   target=Path(folder);policy={'services':{'OPENAI':{'networks':['203.0.113.0/24'],'hosts':['chatgpt.com']}},'direct_networks':[],'outer_addresses':[],'outer_hosts':[]}
   (target/'policy.json').write_text(json.dumps(policy));(target/'dns-cache.json').write_text(json.dumps({'chatgpt.com':{'ips':['203.0.113.1'],'at':1}}));commands=[]
   def execute(args,**kwargs):
    commands.append(args)
    text='anchor "com.apple/*" all' if args[-2:]==['-s','rules'] and '-a' not in args else 'Status: Enabled' if args[-2:]==['-s','info'] else 'Token : 123' if args[-1]=='-E' else ''
    return subprocess.CompletedProcess(args,0,text,'')
   def refresh(policy,cache):
    self.assertTrue(any('-f' in a and '-n' not in a for a in commands),'DNS attempted before cached rules loaded')
    return cache
   with patch.object(firewall,'ETC',target),patch.object(firewall,'TOKEN',target/'token'),patch.object(firewall.os,'geteuid',return_value=0),patch.object(firewall,'execute',side_effect=execute),patch.object(firewall,'refresh',side_effect=refresh):
    self.assertEqual(firewall.apply(),0)
   self.assertFalse(any('/etc/pf.conf' in a or '-F' in a for a in commands))
if __name__=='__main__':unittest.main()

