#!/usr/bin/python3
"""Read PF state, then verify bound TCP probes are blocked by our exact anchor."""
import ipaddress,json,os,re,subprocess,sys
from pathlib import Path
ANCHOR='com.apple/249.ArtmeAIGuard'
def call(args):return subprocess.run(args,capture_output=True,text=True,timeout=12)
def counters():
 result=call(['/sbin/pfctl','-a',ANCHOR,'-vvsr'])
 if result.returncode:raise ValueError('Cannot read guard rules')
 counts={};current=None
 for line in result.stdout.splitlines():
  label=re.search(r'label "ARTME_(OPENAI|CLAUDE)"',line)
  if line.startswith('@'):current=label.group(1) if label else None
  packets=re.search(r'Packets:\s*(\d+)',line)
  if current and packets:counts[current]=counts.get(current,0)+int(packets.group(1));current=None
 return counts
if os.geteuid()!=0:raise SystemExit('Run verify.sh; administrator rights required for PF counters')
etc=Path('/usr/local/etc/artme-ai-guard');cache=json.loads((etc/'dns-cache.json').read_text())
info=call(['/sbin/pfctl','-s','info']);enabled='Status: Enabled' in info.stdout
labels=counters();result={'pf_enabled':enabled,'blocking_labels':sorted(labels),'tests':[]}
iface=None
for candidate in ('en0','en1','en2','en3','en4','en5'):
 route=call(['/sbin/route','-n','get','-ifscope',candidate,'default'])
 if route.returncode==0 and 'gateway:' in route.stdout:iface=candidate;break
result['physical_interface']=iface
if iface:
 control=call(['/usr/bin/nc','-z','-G','3','-b',iface,'1.1.1.1','443'])
 result['unprotected_tcp_control_connected']=control.returncode==0
 for service,host in [('OPENAI','api.openai.com'),('CLAUDE','api.anthropic.com')]:
  address=next((ip for ip in cache[host]['ips'] if ipaddress.ip_address(ip).version==4),None)
  if not address:continue
  before=counters().get(service,0)
  probe=call(['/usr/bin/nc','-z','-G','3','-b',iface,address,'443'])
  after=counters().get(service,0)
  result['tests'].append({'service':service,'connected':probe.returncode==0,'block_counter_increased':after>before,
                          'pass':probe.returncode!=0 and after>before})
result['pass']=enabled and len(result['tests'])==2 and all(t['pass'] for t in result['tests'])
# Do not claim a connectivity failure itself proves blocking: rule counters are mandatory.
print(json.dumps(result,indent=2))
sys.exit(0 if result['pass'] else 2)
