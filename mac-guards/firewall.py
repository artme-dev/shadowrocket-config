#!/usr/bin/python3
"""Root-owned, narrowly scoped PF anchor. No VPN changes, global reload or state flush."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse

ETC = Path('/usr/local/etc/artme-ai-guard')
ANCHOR = 'com.apple/249.ArtmeAIGuard'
TOKEN = Path('/var/run/artme-ai-guard.token')
DOH = ['https://cloudflare-dns.com/dns-query', 'https://dns.google/resolve']


def execute(args, timeout=20, check=True):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and result.returncode:
        raise ValueError(f'{Path(args[0]).name} failed ({result.returncode}): {result.stderr[:300]}')
    return result


def private_json(path, data):
    fd, name = tempfile.mkstemp(prefix=path.name+'.', dir=str(path.parent))
    with os.fdopen(fd,'w') as f:
        json.dump(data,f,indent=2);f.write('\n')
    os.replace(name,path)


def addresses(host):
    result = []
    for typ in ('A','AAAA'):
        success = False
        for server in DOH:
            url = server+'?'+urllib.parse.urlencode({'name':host,'type':typ})
            try:
                response = execute(['/usr/bin/curl','--silent','--show-error','--fail','--noproxy','*',
                                    '--connect-timeout','2','--max-time','4','--max-filesize','131072',
                                    '-H','accept: application/dns-json',url],timeout=6)
                data=json.loads(response.stdout)
                if data.get('Status') != 0:
                    continue
                # A successful empty response can be a CNAME-only answer; retain cache if all empty.
                result.extend(str(ipaddress.ip_address(a['data'])) for a in data.get('Answer',[]) if a.get('type') in (1,28))
                success = True
                break
            except (ValueError,KeyError,subprocess.TimeoutExpired):
                continue
        if not success:
            return host, None  # A partial refresh must not discard known IPv4/IPv6.
    return host, sorted(set(result)) if result else None


def refresh(policy, cache):
    hosts=sorted(set(h for v in policy['services'].values() for h in v['hosts']) | set(policy['outer_hosts']))
    if not all(re.fullmatch(r'[a-zA-Z0-9.-]+',h) for h in hosts):
        raise ValueError('Invalid DNS hostname')
    with ThreadPoolExecutor(max_workers=8) as pool:
        results=list(pool.map(addresses,hosts))
    now=int(time.time())
    for host,ips in results:
        if ips:
            cache[host]={'ips':ips,'at':now}
    return cache


def tables(policy, cache):
    result={}
    for service,cfg in policy['services'].items():
        values=set(cfg['networks'])
        for host in cfg['hosts']:
            values.update(cache.get(host,{}).get('ips',[]))
        # Explicit DIRECT ranges retain precedence, as in the Shadowrocket profile.
        excluded=set(policy['direct_networks'])|set(policy['outer_addresses'])
        for host in policy['outer_hosts']:
            excluded.update(cache.get(host,{}).get('ips',[]))
        exclusions=[ipaddress.ip_network(v,strict=False) for v in excluded]
        # A more-specific positive /32 would override a negative /24 in PF's longest-prefix match.
        # Remove contained positives first, then negate the portions inside retained supernets.
        positive=[ipaddress.ip_network(v,strict=False) for v in values]
        positive=[n for n in positive if not any(n.version==x.version and n.subnet_of(x) for x in exclusions)]
        values={str(n) for n in positive}
        for address in policy['outer_addresses']:
            ipaddress.ip_address(address)  # Outer VPN/ISP endpoints must never be blocked.
        values.update('!'+str(x) for x in exclusions if any(x.version==n.version and x.subnet_of(n) for n in positive))
        for v in values:
            ipaddress.ip_network(v.lstrip('!'),strict=False)
        if not positive:
            raise ValueError('Empty '+service+' table')
        result[service]=sorted(values)
    return result


def render(target, values):
    rules=['# Generated from the accepted personal profile. Only this anchor is managed.']
    # No wildcard interface names in macOS PF. Enumerate a generous utun range; fail closed beyond it.
    tunnels='{ '+ ' '.join('utun'+str(i) for i in range(256))+' }'
    for service,entries in values.items():
        table='artme_'+service.lower()
        filename=target/(table+'.txt')
        filename.write_text('\n'.join(entries)+'\n');filename.chmod(0o600)
        rules.extend(['table <'+table+'> persist file "'+str(filename)+'"',
                      'pass out quick on '+tunnels+' to <'+table+'> no state',
                      'block return out quick to <'+table+'> label "ARTME_'+service+'"'])
    result=target/'pf.rules';result.write_text('\n'.join(rules)+'\n');result.chmod(0o600)
    return result


def apply():
    if os.geteuid()!=0:
        raise ValueError('Administrator rights required')
    import fcntl
    with (ETC/'apply.lock').open('w') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return 0
        policy=json.loads((ETC/'policy.json').read_text())
        cachefile=ETC/'dns-cache.json'
        cache=json.loads(cachefile.read_text())
        missing=[h for cfg in policy['services'].values() for h in cfg['hosts'] if h not in cache]+[h for h in policy['outer_hosts'] if h not in cache]
        if missing:raise ValueError('Missing initial DNS seed; keeping existing anchor')
        active=execute(['/sbin/pfctl','-s','rules']).stdout
        if not re.search(r'anchor "com\.apple/\*"',active):
            raise ValueError('Required com.apple/* anchor missing; main PF rules were NOT reloaded')

        def install_snapshot(values):
            stage=Path(tempfile.mkdtemp(prefix='rules.',dir=str(ETC)))
            rulefile=render(stage,values)
            try:
                execute(['/sbin/pfctl','-n','-a',ANCHOR,'-f',str(rulefile)])
                enabled='Status: Enabled' in execute(['/sbin/pfctl','-s','info']).stdout
                if not TOKEN.exists() or not enabled:
                    result=execute(['/sbin/pfctl','-E'])
                    match=re.search(r'Token\s*:\s*(\d+)',result.stdout+result.stderr)
                    if not match:raise ValueError('PF reference token missing')
                    TOKEN.write_text(match.group(1)+'\n');TOKEN.chmod(0o600)
                execute(['/sbin/pfctl','-a',ANCHOR,'-f',str(rulefile)])
            except Exception:
                import shutil;shutil.rmtree(stage)
                raise
            return stage

        values=tables(policy,cache)
        digest=lambda v:hashlib.sha256(json.dumps(v,sort_keys=True).encode()).hexdigest()
        previous=json.loads((ETC/'status.json').read_text()) if (ETC/'status.json').exists() else {}
        own=execute(['/sbin/pfctl','-a',ANCHOR,'-s','rules']).stdout
        enabled='Status: Enabled' in execute(['/sbin/pfctl','-s','info']).stdout
        stage=Path(previous.get('rules_directory',str(ETC)))
        # Load cached rules immediately at boot BEFORE attempting DNS. No startup DNS gap.
        if not enabled or not all('ARTME_'+k in own for k in values) or previous.get('table_sha256')!=digest(values):
            stage=install_snapshot(values)
        fresh=refresh(policy,cache.copy())
        updated=tables(policy,fresh)
        if updated!=values:stage=install_snapshot(updated)
        private_json(cachefile,fresh)
        private_json(ETC/'status.json',{'at':datetime.datetime.now().astimezone().isoformat(),
                     'anchor':ANCHOR,'table_sizes':{k:len(v) for k,v in updated.items()},
                     'rules_directory':str(stage),'table_sha256':digest(updated),'pf_reference_retained':True})
        # No global reload/state flush; only our versioned temporary files are cleaned.
        for old in ETC.glob('rules.*'):
            if old!=stage and old.is_dir():
                import shutil;shutil.rmtree(old)
        print('AI firewall applied; VPN and unrelated PF anchors unchanged')
        return 0


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['apply','prepare'])
    parser.add_argument('--directory',type=Path)
    args=parser.parse_args()
    if args.action=='apply':return apply()
    target=args.directory
    if target is None:raise ValueError('--directory required')
    policy=json.loads((target/'policy.json').read_text())
    cache=refresh(policy,{})
    missing=[h for v in policy['services'].values() for h in v['hosts'] if h not in cache]
    # Initial seeds may omit optional domains that legitimately return NXDOMAIN, but not core endpoints.
    required={'chatgpt.com','api.openai.com','api.anthropic.com','claude.ai'} | set(policy['outer_hosts'])
    if not required<=set(cache):raise ValueError('Core host resolution failed')
    for service in policy['services'].values():
        service['hosts']=[h for h in service['hosts'] if h in cache]
    private_json(target/'policy.json',policy);private_json(target/'dns-cache.json',cache)
    rulefile=render(target,tables(policy,cache))
    print(json.dumps({'resolved_hosts':len(cache),'omitted_optional_hosts':len(missing),'table_sizes':{k:len(v) for k,v in tables(policy,cache).items()}}))
    # -n parses syntax without loading the rules. Does not need root for pure parsing on this Mac.
    execute(['/sbin/pfctl','-n','-a',ANCHOR,'-f',str(rulefile)])
    return 0


if __name__=='__main__':
    try:sys.exit(main())
    except (OSError,ValueError,KeyError,subprocess.TimeoutExpired) as exc:
        print('AI firewall: '+str(exc),file=sys.stderr);sys.exit(1)
