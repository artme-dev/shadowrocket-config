"""Probe the configured ISP SOCKS5 through the existing OS route; never change it.

Credentials stay in personal/secrets.local.json. No API keys or accounts are used.
"""
import argparse
import datetime
import ipaddress
import json
import re
import socket
import ssl
import struct
import time
from pathlib import Path

from assemble_artme import private_write

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    ('neutral-speed', 'speed.cloudflare.com', '/cdn-cgi/trace'),
    ('neutral-www', 'www.cloudflare.com', '/cdn-cgi/trace'),
    ('chatgpt', 'chatgpt.com', '/cdn-cgi/trace'),
    ('openai-trace', 'api.openai.com', '/cdn-cgi/trace'),
    ('openai-api', 'api.openai.com', '/v1/models'),
    ('anthropic-trace', 'api.anthropic.com', '/cdn-cgi/trace'),
    ('claude-web', 'claude.ai', '/'),
    ('ordinary-web', 'example.com', '/'),
]
REPLIES = {0: 'accepted', 1: 'general failure', 2: 'connection not allowed by ruleset',
           3: 'network unreachable', 4: 'host unreachable', 5: 'connection refused',
           6: 'TTL expired', 7: 'command unsupported', 8: 'address type unsupported'}


def read_exact(sock, length):
    data = b''
    while len(data) < length:
        chunk = sock.recv(length - len(data))
        if not chunk:
            raise EOFError('peer closed connection')
        data += chunk
    return data


def probe(credentials, target, trial, destination_ip=None):
    label, host, path = target
    result = {'target': label, 'host': host, 'path': path, 'trial': trial,
              'stage': 'tcp', 'socks_reply': None, 'http_status': None, 'exit_ip': None}
    result['destination_type'] = 'ipv4' if destination_ip else 'domain'
    if destination_ip:
        address = ipaddress.IPv4Address(destination_ip)
        if not address.is_global:
            raise ValueError('Only public IPv4 targets may be probed')
        result['destination_ip'] = str(address)
    started = time.monotonic()
    sock = None
    try:
        sock = socket.create_connection((credentials['server'], credentials['port']), timeout=8)
        sock.settimeout(8)
        result['stage'] = 'auth-method'
        sock.sendall(b'\x05\x01\x02')
        greeting = read_exact(sock, 2)
        if greeting != b'\x05\x02':
            result['method_reply'] = greeting.hex()
            return result
        result['stage'] = 'auth'
        user = credentials['username'].encode()
        password = credentials['password'].encode()
        if not 0 < len(user) < 256 or not 0 < len(password) < 256:
            raise ValueError('invalid credential length')
        sock.sendall(b'\x01' + bytes([len(user)]) + user + bytes([len(password)]) + password)
        auth = read_exact(sock, 2)
        result['auth_status'] = auth[1]
        if auth != b'\x01\x00':
            return result
        result['stage'] = 'socks-connect'
        if destination_ip:
            request_address = b'\x01' + socket.inet_aton(destination_ip)
        else:
            encoded_host = host.encode('idna')
            request_address = b'\x03' + bytes([len(encoded_host)]) + encoded_host
        sock.sendall(b'\x05\x01\x00' + request_address + struct.pack('!H', 443))
        reply = read_exact(sock, 4)
        if reply[0] != 5:
            raise ValueError('invalid SOCKS version')
        result['socks_reply'] = reply[1]
        result['socks_message'] = REPLIES.get(reply[1], 'unknown response')
        if reply[1] != 0:
            return result
        size = {1: 4, 4: 16}.get(reply[3])
        if reply[3] == 3:
            size = read_exact(sock, 1)[0]
        if size is None:
            raise ValueError('invalid SOCKS address type')
        read_exact(sock, size + 2)
        result['stage'] = 'tls'
        sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
        result['tls_version'] = sock.version()
        result['stage'] = 'http'
        sock.sendall((f'GET {path} HTTP/1.1\r\nHost: {host}\r\n'
                      'User-Agent: ISP-Connectivity-Probe/1.0\r\nConnection: close\r\n\r\n').encode())
        data = b''
        while len(data) < 131072:
            chunk = sock.recv(8192)
            if not chunk:
                break
            data += chunk
            if b'\r\n\r\n' in data and path != '/cdn-cgi/trace':
                break
        text = data.decode('utf-8', 'replace')
        status = re.match(r'HTTP/\S+ (\d{3})', text)
        if status:
            result['http_status'] = int(status[1])
        ip = re.search(r'(?:\r?\n)ip=([0-9a-fA-F:.]+)', text)
        if ip:
            result['exit_ip'] = ip[1]
        result['stage'] = 'complete' if status else 'http'
    except Exception as exc:
        result['error_type'] = type(exc).__name__
        # Exception text is not retained because network libraries may include secrets.
    finally:
        if sock is not None:
            sock.close()
        result['seconds'] = round(time.monotonic() - started, 2)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--route', choices=('OPENAI', 'CLAUDE', 'OTHER'), default='OPENAI',
                        help='Select credentials from the desired profile; does not select a live route')
    parser.add_argument('--target', choices=[target[0] for target in TARGETS], default='neutral-www')
    parser.add_argument('--trials', type=int, choices=range(1, 11), default=3, metavar='1–10')
    args = parser.parse_args()

    settings = json.loads((ROOT / 'personal/artme.json').read_text())
    route = settings['routes'][args.route]
    if route['mode'] != 'isp':
        parser.error(f'{args.route} has no ISP exit in personal/artme.json')
    secrets_path = ROOT / 'personal/secrets.local.json'
    if not secrets_path.is_file():
        parser.error('Missing local personal/secrets.local.json')
    credentials = json.loads(secrets_path.read_text())['exits'][route['exit']]
    target = next(target for target in TARGETS if target[0] == args.target)
    started = datetime.datetime.now().astimezone()
    results = []
    for trial in range(1, args.trials + 1):
        result = probe(credentials, target, trial)
        results.append(result)
        print(json.dumps(result), flush=True)
    report = {
        'timestamp': started.isoformat(),
        'profile_route_for_credentials': args.route,
        'port': credentials['port'],
        'transport': 'Explicit SOCKS5 connection over the existing OS route to the proxy',
        'dns': 'Destination hostname resolved by the SOCKS5 proxy',
        'tls_verification': True,
        'results': results,
    }
    path = ROOT / 'out/diagnostics' / started.date().isoformat() / f'isp-probe-{started:%H%M%S-%f}.private.json'
    private_write(path, json.dumps(report, indent=2) + '\n')
    print(f'Saved {path}')


if __name__ == '__main__':
    main()
