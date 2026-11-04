# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Assemble one complete private artme.conf. No device operations or network tests.

uv run tools/assemble_artme.py
uv run tools/assemble_artme.py --publish

Public inputs: artme.conf (base rules), personal/artme.json, rules/zoom.list.
Private inputs: personal/secrets.local.json and personal/publish.local.json.
The complete output contains secrets and is always written under ignored out/.
"""
import argparse
from copy import deepcopy
import json
import ipaddress
import os
from pathlib import Path
import re
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ROUTES = ('OPENAI', 'CLAUDE', 'OTHER')


def private_write(path, text):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        stream.write(text)


def provider_nodes(provider, url):
    import yaml
    agent = 'clash.meta' if provider == 'blanc' else 'Shadowrocket'
    request = urllib.request.Request(url, headers={'User-Agent': agent})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return yaml.safe_load(response.read())['proxies']
    except Exception as exc:
        raise ValueError(f'Cannot fetch {provider} subscription ({type(exc).__name__}); private URL hidden') from None


def atom(value):
    text = str(value)
    if any(char in text for char in ('\r', '\n', '\x00')):
        raise ValueError('Proxy parameters must not contain control characters')
    if not text or any(char in text for char in ',"#;') or text != text.strip():
        return json.dumps(text, ensure_ascii=False)
    return text


def choose(source, wanted):
    candidates = []
    for node in source:
        if node.get('type') != wanted['protocol']:
            continue
        if wanted['provider'] == 'blanc':
            matched = node['name'].split(',', 1)[0].endswith(' ' + wanted['server'])
        else:
            matched = ' xeovo ' + wanted['server'] + ' (' in node['name']
            if node['type'] == 'vless':
                matched = matched and 'ws-opts' in node
        if matched:
            candidates.append(node)
    if not candidates:
        raise ValueError(f'No compatible source node for {wanted["name"]}')
    node = deepcopy(candidates[0])
    node['name'] = wanted['name']
    if any(node.get(key) for key in ('chain', 'dialer-proxy', 'underlying-proxy')):
        raise ValueError('An entry node already contains a chain')
    return node


def proxy_line(node):
    fields = [node['type'], atom(node['server']), str(int(node['port']))]
    def add(key, value):
        if value is not None and value != '':
            fields.append(key + '=' + atom(value))
    if node['type'] == 'socks5':
        fields.extend([atom(node['username']), atom(node['password'])])
        add('method', 'auto')
        add('udp', '1' if node.get('udp') else '0')
        add('chain', node['chain'])
    elif node['type'] == 'vless':
        add('password', node['uuid'])
        add('tls', 'true' if node.get('tls') else 'false')
        add('peer', node.get('servername', node.get('sni')))
        network = node.get('network', 'tcp')
        if network == 'ws':
            options = node['ws-opts']
            add('obfs', 'websocket')
            add('obfs-uri', options.get('path', '/'))
            headers = options.get('headers', {})
            extra_headers = set(headers) - {'Host', 'host'}
            if extra_headers or options.get('max-early-data'):
                raise ValueError('WebSocket headers/early data require an explicit native mapping')
            add('obfs-host', headers.get('Host', headers.get('host')))
        elif network != 'tcp':
            raise ValueError('Only TCP and WebSocket VLESS transports are configured')
        reality = node.get('reality-opts')
        if reality:
            add('reality', 'true')
            add('pbk', reality['public-key'])
            add('sid', reality.get('short-id'))
        add('flow', node.get('flow'))
        add('fp', node.get('client-fingerprint'))
        add('udp', '1' if node.get('udp') else '0')
    elif node['type'] == 'ss':
        if node.get('plugin') or node.get('cipher') not in ('chacha20-ietf-poly1305', 'aes-128-gcm', 'aes-256-gcm'):
            raise ValueError('Only explicitly mapped AEAD Shadowsocks entries are supported')
        add('method', node['cipher'])
        add('password', node['password'])
        add('udp', '1' if node.get('udp') else '0')
    elif node['type'] == 'trojan':
        if node.get('network', 'tcp') != 'tcp':
            raise ValueError('Only Trojan TLS over TCP is mapped')
        add('password', node['password'])
        add('peer', node.get('servername', node.get('sni', node['server'])))
        add('udp', '1' if node.get('udp') else '0')
    elif node['type'] == 'hysteria2':
        add('auth', node['password'])
        add('peer', node.get('sni', node.get('servername')))
        add('udp', '1')
    else:
        raise ValueError('Unsupported node type')
    if node.get('skip-cert-verify'):
        raise ValueError('Certificate verification must remain enabled')
    return node['name'] + ' = ' + ', '.join(fields)


def voice_rules(document):
    """Accept only public CIDRs from the official voice document; no silent empty list."""
    prefixes = document['prefixes']
    if not prefixes or len(prefixes) > 10000:
        raise ValueError('Unexpected voice prefix count')
    networks = set()
    for record in prefixes:
        if len(record) != 1 or not set(record) <= {'ipv4Prefix', 'ipv6Prefix'}:
            raise ValueError('Unexpected voice prefix schema')
        network = ipaddress.ip_network(next(iter(record.values())), strict=True)
        if not network.is_global or network.prefixlen == 0:
            raise ValueError('Voice prefix is not a public network')
        expected = 'ipv4Prefix' if network.version == 4 else 'ipv6Prefix'
        if expected not in record:
            raise ValueError('Voice address family mismatch')
        networks.add(network)
    return [f"{'IP-CIDR' if net.version == 4 else 'IP-CIDR6'},{net},OPENAI,no-resolve"
            for net in sorted(networks, key=lambda n: (n.version, int(n.network_address), n.prefixlen))]


def assemble(base, settings, secrets, sources, update_url, zoom, voice):
    if set(settings['routes']) != set(ROUTES):
        raise ValueError('Exactly three route groups are required')
    nodes = [choose(sources[s['provider']], s) for s in settings['servers']]
    names = [node['name'] for node in nodes]
    reserved = {'AUTO', 'SERVICE', 'OPENAI', 'CLAUDE', 'OTHER', 'ISP-OPENAI', 'ISP-CLAUDE', 'ISP-OTHER', 'REJECT', 'DIRECT', 'PROXY', 'ARTEM-PERSONAL'}
    if (len(names) != len(set(names)) or set(names) & reserved
            or any(not re.fullmatch('[A-Z0-9-]+', n) for n in names)):
        raise ValueError('Server names must be unique uppercase identifiers, distinct from policies')
    rotation = settings['rotation']
    priority = rotation['priority']
    if not priority or len(priority) != len(set(priority)) or set(priority) != set(names):
        raise ValueError('Rotation priority must contain every entry exactly once')
    if rotation['selected'] not in ['AUTO', *names]:
        raise ValueError('Invalid selected entry')
    interval, timeout = rotation['interval'], rotation['timeout']
    if not isinstance(interval, int) or not 30 <= interval <= 3600 or not isinstance(timeout, int) or not 1 <= timeout <= 30:
        raise ValueError('Invalid entry health-check timing')
    if not rotation['url'].startswith('https://') or any(c in rotation['url'] for c in ',\r\n'):
        raise ValueError('Entry health-check URL must be HTTPS')
    groups = [
        '# AUTO: первый доступный вход по порядку; это проверка VPN, а не всей цепочки ISP.',
        'AUTO = fallback, ' + ', '.join(priority) + f", url={rotation['url']}, interval={interval}, timeout={timeout}",
        '# AUTO по умолчанию; конкретный сервер здесь вручную закрепляет вход для всех категорий.',
        'artem-personal = select, AUTO, ' + ', '.join(names) + ', policy-select-name=' + rotation['selected'],
    ]
    exits = []
    for route in ROUTES:
        options = settings['routes'][route]
        if options['mode'] == 'vpn':
            if route != 'OTHER':
                raise ValueError('AI categories require a fixed ISP exit')
            groups.append(f'{route} = select, artem-personal, REJECT, policy-select-name=artem-personal')
            continue
        if options['mode'] != 'isp':
            raise ValueError('Route mode must be isp or vpn')
        if not isinstance(options['udp'], bool):
            raise ValueError('UDP support must be explicitly true or false')
        credentials = secrets['exits'][options['exit']]
        port = credentials['port']
        if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
            raise ValueError('Invalid SOCKS5 port')
        if any(not isinstance(credentials[key], str) or not credentials[key]
               for key in ('server', 'username', 'password')):
            raise ValueError('Missing SOCKS5 credentials')
        exit_name = 'ISP-' + route
        # Explicit field selection prevents private metadata from changing the generated chain.
        nodes.append({'name': exit_name, 'type': 'socks5',
                      **{key: credentials[key] for key in ('server', 'port', 'username', 'password')},
                      'udp': options['udp'], 'chain': 'artem-personal'})
        exits.append(exit_name)
        groups.append(f'{route} = select, {exit_name}, REJECT, policy-select-name={exit_name}')
    groups.extend(['# Сервисные узлы для просмотра; правила используют OPENAI/CLAUDE/OTHER.',
                   'SERVICE = select, ' + ', '.join(exits) + ', REJECT, policy-select-name=' + exits[0]])
    _, general_and_rest = base.split('[General]', 1)
    general, old_groups_and_rules = general_and_rest.split('[Proxy Group]', 1)
    general = re.sub(r'^update-url\s*=.*$', 'update-url = ' + update_url, general, flags=re.M)
    # The numeric-IP DoT endpoint repeatedly failed certificate validation in native logs.
    general = general.replace(', tls://1.1.1.2:853', '')
    general += '\n# Не пропускать отсутствующий родительский VPN и не подключаться к ISP напрямую.\nclose-if-proxy-chain-missing = true\n'
    _, old_rules = old_groups_and_rules.split('[Rule]', 1)
    rules = [
        '# Диагностика: эти точные имена намеренно стоят перед общими правилами.',
        'DOMAIN,api.ipify.org,OPENAI',
        'DOMAIN,icanhazip.com,CLAUDE',
        'DOMAIN,checkip.amazonaws.com,OTHER',
        'DOMAIN,ifconfig.me,DIRECT',
        '# UDP-диагностика: только Quad9 на альтернативном порту; обычный DNS не меняется.',
        'AND,((DST-PORT,9953),(IP-CIDR,9.9.9.9/32)),OPENAI',
        '# Конкретные проекты телеметрии OpenAI из официального списка.',
        'DOMAIN,o207216.ingest.sentry.io,OPENAI',
        'DOMAIN,o33249.ingest.sentry.io,OPENAI',
        '# Дополнительные собственные домены OpenAI из официального списка.',
        'DOMAIN-SUFFIX,oaistatsig.com,OPENAI',
        'DOMAIN-SUFFIX,openaimerge.com,OPENAI',
        '# Голос: https://openai.com/chatgpt-voice.json; snapshot ' + str(voice['creationTime']),
        *voice_rules(voice),
        '',
    ]
    for line in old_rules.splitlines():
        if line.startswith('RULE-SET,'):
            if '/rules/zoom.list,' not in line:
                raise ValueError('Unexpected external rule set')
            rules.append('# IP Zoom встроены в профиль.')
            for item in zoom.splitlines():
                if not item.strip() or item.lstrip().startswith(('#', ';')):
                    continue
                fields = item.split(',')
                fields.insert(2, 'DIRECT')
                rules.append(','.join(fields))
            continue
        if line and not line.lstrip().startswith(('#', ';')):
            line = ','.join('OTHER' if part == 'PROXY' else part.upper() if part in ('Claude', 'OpenAI') else part
                            for part in line.split(','))
        if line.startswith('IP-CIDR,160.79.104.0/21,'):
            rules.extend(['IP-CIDR,160.79.104.0/23,CLAUDE,no-resolve',
                          'IP-CIDR,153.61.224.0/22,CLAUDE,no-resolve'])
            continue
        if 'Только домены: своих IP-диапазонов OpenAI' in line:
            line = '# Доменные правила дополняют официальный список голосовых IP выше.'
        line = line.replace('через выбранный на главном экране сервер', 'через группу OTHER')
        line = line.replace('Иначе они уходят через PROXY с другого IP.', 'Иначе они относятся к OTHER.')
        line = line.replace('# Домены — здесь; IP-диапазоны (их ~50) — в rules/zoom.list. Если список не скачается, домены всё равно работают.',
                            '# Домены и IP-диапазоны включены в этот файл.')
        rules.append(line)
    header = """# artme — персональный профиль Shadowrocket
# Содержит ключи и пароли. Не публиковать в открытом репозитории.
# Проверяемая версия клиента: Shadowrocket 2.2.93 (3488); старые клиенты нужно обновить.
# Config → Download from URL → Use Config; Global Routing = Config.
# AI: устройство → artem-personal → ISP-* → сайт. OTHER: устройство → artem-personal → сайт.
# DIRECT-исключения сохранены; точные адреса IP-проверок переопределены выше них.
# Начальный выбор задаёт policy-select-name; приложение может помнить прежний выбор.
# Внешние серверные подписки не нужны. Все узлы и IP-списки встроены в этот файл.
"""
    body = header + '\n[General]' + general + '\n[Proxy]\n'
    body += '\n'.join(proxy_line(node) for node in nodes)
    body += '\n\n[Proxy Group]\n' + '\n'.join(groups) + '\n\n[Rule]\n' + '\n'.join(rules) + '\n'
    return body, nodes


def gh(*args):
    result = subprocess.run(['gh', *args], capture_output=True, text=True)
    if result.returncode:
        raise ValueError('GitHub operation failed; details hidden to avoid exposing private content')
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--sources-dir', type=Path, help='Use provider snapshots already downloaded for this assembly')
    parser.add_argument('--settings', type=Path, default=ROOT / 'personal/artme.json')
    parser.add_argument('--filename', default='artme.conf', help='Separate .conf filename for a reviewable candidate')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'out')
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]{0,75}\.conf', args.filename):
        raise ValueError('Invalid config filename')
    output = args.output_dir.resolve()
    if output != ROOT / 'out' and ROOT / 'out' not in output.parents:
        raise ValueError('Complete private profiles must be written under ignored out/')
    settings = json.loads(args.settings.read_text())
    secrets = json.loads((ROOT / 'personal/secrets.local.json').read_text())
    target = json.loads((ROOT / 'personal/publish.local.json').read_text())
    owner, gist = target['owner'], target['gist']
    update_url = f'https://gist.githubusercontent.com/{owner}/{gist}/raw/{args.filename}'
    providers = {node['provider'] for node in settings['servers']}
    if args.sources_dir:
        sources = {provider: json.loads((args.sources_dir / (provider + '-source.json')).read_text()) for provider in sorted(providers)}
    else:
        sources = {provider: provider_nodes(provider, secrets['providers'][provider]) for provider in sorted(providers)}
    if args.sources_dir:
        voice = json.loads((args.sources_dir / 'chatgpt-voice.json').read_text())
    else:
        with urllib.request.urlopen('https://openai.com/chatgpt-voice.json', timeout=30) as response:
            voice = json.loads(response.read())
    body, nodes = assemble((ROOT / 'artme.conf').read_text(), settings, secrets, sources,
                           update_url, (ROOT / 'rules/zoom.list').read_text(), voice)
    from validate_artme import validate_body
    validation = validate_body(body, settings, voice, (ROOT / 'artme.conf').read_text())
    private_write(output / 'semantic-validation.private.json', json.dumps(validation, indent=2) + '\n')
    path = output / args.filename
    private_write(path, body)
    private_write(output / 'artme-nodes.json', json.dumps(nodes, ensure_ascii=False, indent=2) + '\n')
    print(f'Complete {args.filename} assembled: {len(settings["servers"])} entries, {len(nodes) - len(settings["servers"])} exits. Secrets hidden.')
    if args.publish:
        if gh('api', 'user', '--jq', '.login').strip() != owner:
            raise ValueError('Unexpected GitHub account')
        metadata = json.loads(gh('api', f'gists/{gist}'))
        if metadata['public'] or metadata['owner']['login'] != owner:
            raise ValueError('Target must be the existing secret personal Gist owned by the expected account')
        private_write(output / 'publication-before.private.json', json.dumps(metadata))
        contents = {args.filename: body}
        if args.filename == 'artme.conf':
            aliases = target.get('aliases', [])
            if not isinstance(aliases, list) or len(aliases) > 5:
                raise ValueError('Invalid publication aliases')
            for alias in aliases:
                if not isinstance(alias, str) or not re.fullmatch(r'[a-zA-Z0-9][a-zA-Z0-9._-]{0,75}\.conf', alias) or alias == args.filename or alias not in metadata['files']:
                    raise ValueError('Alias must be a distinct existing config in the same personal Gist')
                contents[alias] = body
        payload = output / 'publish-artme.json'
        private_write(payload, json.dumps({'files': {name: {'content': content} for name, content in contents.items()}}))
        gh('api', '--method', 'PATCH', f'gists/{gist}', '--input', str(payload), '--silent')
        # Verify the exact stored file without displaying its contents or changing other Gist files.
        after = json.loads(gh('api', f'gists/{gist}'))
        stored = after['files'][args.filename]
        for name, previous in metadata['files'].items():
            if name not in contents and after['files'].get(name, {}).get('content') != previous.get('content'):
                raise ValueError('An unrelated publication file changed')
        for name, content in contents.items():
            stored = after['files'][name]
            if stored.get('truncated') or stored['content'] != content:
                raise ValueError('Published file could not be verified byte-for-byte')
        private_write(output / 'artme-url.txt', update_url + '\n')
        print(f'Published and verified {args.filename} in existing secret personal Gist. Other files unchanged.')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, FileNotFoundError) as exc:
        raise SystemExit(f'Assembly failed: {exc}') from None
