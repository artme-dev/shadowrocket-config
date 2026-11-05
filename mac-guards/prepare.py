#!/usr/bin/env python3
"""Prepare local policy and DNS seeds from the accepted config. No privileged changes."""
import ipaddress,json,os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
settings=json.loads((ROOT/'personal/artme.json').read_text())
secrets=json.loads((ROOT/'personal/secrets.local.json').read_text())
body=(ROOT/'out/artme.conf').read_text()
nodes=json.loads((ROOT/'out/artme-nodes.json').read_text())
target=ROOT/'out/mac-guards';target.mkdir(parents=True,exist_ok=True,mode=0o700)
services={}
hosts={'OPENAI': ['chatgpt.com','ab.chatgpt.com','ws.chatgpt.com','chat.openai.com','openai.com','platform.openai.com','api.openai.com','auth.openai.com','ios.chat.openai.com','android.chat.openai.com','cdn.oaistatic.com','persistent.oaistatic.com','files.oaiusercontent.com','sora.com','chat.com'],
        'CLAUDE':['api.anthropic.com','claude.ai','console.anthropic.com','platform.claude.com']}
for service in hosts:
 cfg=settings['routes'][service]
 if cfg['mode']!='isp':raise ValueError('Guard requires explicit static ISP')
 expected=str(ipaddress.ip_address(secrets['exits'][cfg['exit']]['server']))
 services[service]={'expected_ip':expected,'hosts':hosts[service],'networks':[],
                    'terminate':['codex','Codex','ChatGPT'] if service=='OPENAI' else []}
direct=[]
for line in body.split('[Rule]',1)[1].splitlines():
 fields=line.strip().split(',')
 if len(fields)>2 and fields[0] in ('IP-CIDR','IP-CIDR6'):
  network=str(ipaddress.ip_network(fields[1]))
  if fields[2] in services:services[fields[2]]['networks'].append(network)
  if fields[2]=='DIRECT':direct.append(network)
outer=set();outer_hosts=set()
for node in nodes:
 try:outer.add(str(ipaddress.ip_address(node['server'])))
 except ValueError:outer_hosts.add(node['server'])
policy={'schema':1,'services':services,'direct_networks':direct,'outer_addresses':sorted(outer),'outer_hosts':sorted(outer_hosts)}
f=target/'policy.json';fd=os.open(f,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as stream:json.dump(policy,stream,indent=2);stream.write('\n')
subprocess.run(['/usr/bin/python3',str(ROOT/'mac-guards/firewall.py'),'prepare','--directory',str(target)],check=True)
