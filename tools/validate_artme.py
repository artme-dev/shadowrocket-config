"""Offline semantic checks for the complete personal Shadowrocket profile.

Never prints credentials, server addresses, or private subscription URLs.
"""
import argparse
import hashlib
import ipaddress
import json
from pathlib import Path
import re


def parts(line):
    fields, current, quoted, escaped = [], [], False, False
    for char in line:
        if char == '"' and not escaped:
            quoted = not quoted
        if char == ',' and not quoted:
            fields.append(''.join(current).strip()); current = []
        else:
            current.append(char)
        escaped = char == '\\' and not escaped
    if quoted:
        raise ValueError('Unterminated native parameter quotation')
    return fields + [''.join(current).strip()]


def validate_body(body, settings, voice, base):
    def require(condition, message):
        if not condition:
            raise ValueError(message)
    sections, section = {}, None
    for raw in body.splitlines():
        line = raw.strip()
        if not line or line.startswith(('#', ';')):
            continue
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
            require(section not in sections, 'Duplicate config section')
            sections[section] = []
        else:
            require(section is not None, 'Content outside config sections')
            sections[section].append(line)
    require(set(sections) == {'General','Proxy','Proxy Group','Rule'}, 'Unexpected or missing config sections')
    def named(lines):
        result = {}
        for line in lines:
            name, value = line.split('=', 1); name = name.strip()
            require(name.casefold() not in {n.casefold() for n in result}, 'Duplicate policy or setting')
            result[name] = value.strip()
        return result
    general = named(sections['General'])
    require(general.get('close-if-proxy-chain-missing') == 'true', 'Missing strict chain guard')
    require(general.get('udp-policy-not-supported-behaviour') == 'REJECT', 'UDP bypass must be rejected')
    require(general.get('update-url','').startswith('https://'), 'Personal update URL must use HTTPS')
    proxies = {n:parts(v) for n,v in named(sections['Proxy']).items()}
    groups = {n:parts(v) for n,v in named(sections['Proxy Group']).items()}
    require(not (set(proxies) & set(groups)), 'Proxy and group names overlap')
    known = set(proxies) | set(groups) | {'DIRECT','REJECT'}
    require(len({n.casefold() for n in known}) == len(known), 'Policy names collide ignoring case')
    entries = {n['name'] for n in settings['servers']}
    require(set(proxies) == entries | {'ISP-'+r for r,o in settings['routes'].items() if o['mode']=='isp'}, 'Unexpected or missing proxy nodes')
    require(all(proxies[n][0] in ('vless','ss','trojan') for n in entries), 'Shared AI pool contains a protocol without verified native UDP-chain support')
    graph = {}
    for name, fields in proxies.items():
        require(fields[0] in ('vless','ss','trojan','hysteria2','socks5'), 'Unsupported proxy protocol')
        require(1 <= int(fields[2]) <= 65535, 'Invalid proxy port')
        options = dict(f.split('=',1) for f in fields[5 if fields[0]=='socks5' else 3:] if '=' in f)
        require(not any(options.get(k,'').lower() in ('1','true') for k in ('skip-cert-verify','skip-common-name-verify','allowInsecure')), 'TLS certificate checks disabled')
        require(options.get('udp') == '1', 'Every pool/exit node must advertise UDP')
        if fields[0] == 'vless':
            require(options.get('tls') == 'true', 'VLESS first hop must be encrypted')
            if options.get('obfs') == 'websocket':
                require('obfs-uri' in options and 'path' not in options, 'Incorrect native WebSocket path mapping')
        if fields[0] == 'ss':
            require(options.get('method') in ('chacha20-ietf-poly1305','aes-128-gcm','aes-256-gcm'), 'Unsupported Shadowsocks encryption')
        graph[name] = [options['chain']] if 'chain' in options else []
    for name, fields in groups.items():
        members = [v for v in fields[1:] if '=' not in v]
        require(bool(members) and set(members) <= known, 'Unresolved group members')
        graph[name] = members
        selected = next((v.split('=',1)[1] for v in fields if v.startswith('policy-select-name=')),None)
        require(selected is None or selected in members, 'Selected policy absent from group')
    for name, members in graph.items():
        require(set(members) <= known, 'Unresolved parent chain')
        def visit(node, ancestors):
            require(node not in ancestors, 'Policy/chain cycle')
            for child in graph.get(node,[]):
                visit(child, ancestors | {node})
        visit(name,set())
    require(groups['AUTO'][0] == 'fallback', 'Entry selection must preserve fallback priority')
    require(graph['AUTO'] == settings['rotation']['priority'], 'Fallback order differs from settings')
    require(graph['artem-personal'] == ['AUTO', *[n['name'] for n in settings['servers']]], 'Entry selector differs from settings')
    for route in ('OPENAI','CLAUDE'):
        require(set(graph[route]) == {'ISP-'+route,'REJECT'}, 'AI group permits a different exit')
        require(graph['ISP-'+route] == ['artem-personal'], 'AI exit has wrong entry group')
    rules = sections['Rule']
    for line in rules:
        require(not line.startswith('RULE-SET,'), 'External rule dependency remains')
        fields = parts(line)
        policy = fields[-2] if fields[-1]=='no-resolve' else fields[-1]
        require(policy in known, 'Rule references an unknown policy')
        require(line.count('(')==line.count(')'), 'Unbalanced logical rule')
    require(rules[-1]=='FINAL,OTHER', 'Unexpected final route')
    def domain_route(host):
        for line in rules:
            fields = parts(line)
            if fields[0]=='DOMAIN' and fields[1]==host or fields[0]=='DOMAIN-SUFFIX' and (host==fields[1] or host.endswith('.'+fields[1])):
                return fields[2]
        return 'OTHER'
    for host,policy in {'api.ipify.org':'OPENAI','icanhazip.com':'CLAUDE','checkip.amazonaws.com':'OTHER','ifconfig.me':'DIRECT','api.openai.com':'OPENAI','chatgpt.com':'OPENAI','claude.ai':'CLAUDE','api.anthropic.com':'CLAUDE'}.items():
        require(domain_route(host)==policy, 'Diagnostic or AI domain route changed')
    for line in base.split('[Rule]',1)[1].splitlines():
        fields = parts(line)
        if len(fields)>=3 and fields[0] in ('DOMAIN','DOMAIN-SUFFIX') and fields[2]=='DIRECT' and fields[1]!='checkip.amazonaws.com':
            require(domain_route(fields[1])=='DIRECT', 'Existing DIRECT domain exception changed')
    require('GEOIP,RU,DIRECT' in rules, 'Russian GEOIP exception removed')
    geo = rules.index('GEOIP,RU,DIRECT')
    require('AND,((DST-PORT,9953),(IP-CIDR,9.9.9.9/32)),OPENAI' in rules, 'Precise UDP diagnostic rule missing')
    for prefix in voice['prefixes']:
        network = ipaddress.ip_network(next(iter(prefix.values())),strict=True)
        rule = ('IP-CIDR' if network.version==4 else 'IP-CIDR6')+','+str(network)+',OPENAI,no-resolve'
        require(rule in rules and rules.index(rule)<geo, 'Official voice network missing or ordered too late')
    require('IP-CIDR,160.79.104.0/23,CLAUDE,no-resolve' in rules and 'IP-CIDR,153.61.224.0/22,CLAUDE,no-resolve' in rules, 'Claude inbound networks missing')
    return {'entries':len(entries),'isp_exits':len(proxies)-len(entries),'groups':len(groups),'rules':len(rules),'voice_prefixes':len(voice['prefixes']),'sha256':hashlib.sha256(body.encode()).hexdigest()}


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config',type=Path,default=root/'out/artme.conf')
    parser.add_argument('--settings',type=Path,default=root/'personal/artme.json')
    parser.add_argument('--voice',type=Path,required=True)
    args = parser.parse_args()
    report = validate_body(args.config.read_text(),json.loads(args.settings.read_text()),json.loads(args.voice.read_text()),(root/'artme.conf').read_text())
    print(json.dumps({'semantic_validation':'pass',**report},indent=2))


if __name__=='__main__':
    try:
        main()
    except (ValueError,KeyError,FileNotFoundError) as exc:
        raise SystemExit('Validation failed: '+str(exc)) from None
