"""Screen private VLESS/Hysteria2 entry snapshots without changing system VPN or contacting ISP.

Input: ignored JSON array of Clash-style VLESS/Hysteria2 nodes with non-secret display names.
Uses an isolated sing-box bound to a named physical interface and loopback listeners.
Results are preliminary entry-only measurements, not ISP-chain or voice benchmarks.
"""
import argparse
import concurrent.futures
import datetime
import ipaddress
import json
import os
from pathlib import Path
import socket
import statistics
import subprocess
import time
import urllib.parse
import urllib.request


def save(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def outbound(node, tag, interface):
    if node['type'] not in ('vless', 'hysteria2') or node.get('skip-cert-verify') or (node['type'] == 'vless' and not node.get('tls')):
        raise ValueError('Only TLS-verified VLESS/Hysteria2 entries are supported')
    host = node['server']
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        # Resolve once before timed probes, retain the original TLS name.
        addresses = [ipaddress.ip_address(x[4][0]) for x in socket.getaddrinfo(host, node['port'], socket.AF_INET, socket.SOCK_STREAM)]
        address = next((a for a in addresses if a.is_global), None)
        if address is None:
            # Shadowrocket may return fake 198.18/15 addresses, which must never be
            # used by a sidecar explicitly bound outside its tunnel. Resolve via TLS.
            query = urllib.parse.urlencode({'name': host, 'type': 'A'})
            with urllib.request.urlopen('https://dns.google/resolve?' + query, timeout=10) as response:
                answer = json.loads(response.read())
            addresses = [ipaddress.ip_address(a['data']) for a in answer.get('Answer', []) if a.get('type') == 1]
            address = next((a for a in addresses if a.is_global), None)
            if address is None:
                raise ValueError('No public IPv4 from verified HTTPS DNS')
    if not address.is_global:
        raise ValueError('Entry must resolve to a public address')
    tls = {'enabled': True, 'server_name': node.get('servername', node.get('sni', host)),
           'utls': {'enabled': True, 'fingerprint': node.get('client-fingerprint', 'chrome')}}
    if node['type'] == 'hysteria2':
        tls.pop('utls', None)
        return {'type': 'hysteria2', 'tag': tag, 'server': str(address), 'server_port': node['port'],
                'password': node['password'], 'tls': tls, 'bind_interface': interface}
    entry = {'type': 'vless', 'tag': tag, 'server': str(address), 'server_port': node['port'],
             'uuid': node['uuid'], 'tls': tls, 'bind_interface': interface}
    if node.get('flow'):
        entry['flow'] = node['flow']
    if node.get('network') == 'ws':
        options = node['ws-opts']
        entry['transport'] = {'type': 'ws', 'path': options.get('path', '/'), 'headers': options.get('headers', {})}
    elif node.get('network', 'tcp') != 'tcp':
        raise ValueError('Unsupported VLESS transport')
    if node.get('reality-opts'):
        options = node['reality-opts']
        tls['reality'] = {'enabled': True, 'public_key': options['public-key'], 'short_id': options.get('short-id', '')}
    return entry


def sample(name, port, trial):
    # Fresh TLS connections; discard response bodies. Curl handles verified HTTPS.
    command = ['curl', '--silent', '--show-error', '--noproxy', '', '--socks5-hostname', f'127.0.0.1:{port}',
               '--connect-timeout', '5', '--max-time', '10', '--output', '/dev/null',
               '--write-out', '%{json}', 'https://www.cloudflare.com/cdn-cgi/trace']
    result = subprocess.run(command, capture_output=True, text=True)
    try:
        timing = json.loads(result.stdout)
    except ValueError:
        timing = {}
    return {'name': name, 'trial': trial, 'curl_exit': result.returncode,
            'http': timing.get('http_code'), 'ttfb_seconds': timing.get('time_starttransfer'),
            'total_seconds': timing.get('time_total'), 'downloaded_bytes': timing.get('size_download', 0)}


def download_sample(name, port, byte_count):
    command = ['curl', '--silent', '--show-error', '--noproxy', '', '--socks5-hostname', f'127.0.0.1:{port}',
               '--connect-timeout', '5', '--max-time', '30', '--output', '/dev/null',
               '--write-out', '%{json}', 'https://speed.cloudflare.com/__down?bytes=' + str(byte_count)]
    response = subprocess.run(command, capture_output=True, text=True)
    try:
        data = json.loads(response.stdout)
    except ValueError:
        data = {}
    size = data.get('size_download', 0)
    total = data.get('time_total', 0)
    first = data.get('time_starttransfer', 0)
    return {'name': name, 'curl_exit': response.returncode, 'http': data.get('http_code'),
            'requested_bytes': byte_count, 'downloaded_bytes': size,
            'valid': response.returncode == 0 and data.get('http_code') == 200 and size == byte_count,
            'ttfb_seconds': first, 'total_seconds': total,
            'body_mbps': round(size * 8 / 1e6 / (total - first), 2) if total > first else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--nodes', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--interface', required=True)
    parser.add_argument('--download-bytes', type=int, default=0, help='Optional single download per entry, maximum 5 MB')
    args = parser.parse_args()
    if not 0 <= args.download_bytes <= 5000000:
        raise ValueError('Download size must be between 0 and 5 MB')
    if args.interface not in dict(socket.if_nameindex()).values():
        raise ValueError('Physical interface is absent')
    nodes = json.loads(args.nodes.read_text())
    if not nodes or len(nodes) > 150 or len({n['name'] for n in nodes}) != len(nodes):
        raise ValueError('Entry names must be unique; maximum 150 nodes')
    args.output.mkdir(parents=True, exist_ok=True, mode=0o700)
    reservations, inbounds, entries, rules, ports = [], [], [], [], []
    resolution_errors = []
    try:
        for i, node in enumerate(nodes):
            tag = f'entry-{i}'
            try:
                entry = outbound(node, tag, args.interface)
            except (OSError, ValueError, KeyError):
                resolution_errors.append(node['name'])
                continue
            listener = socket.socket()
            listener.bind(('127.0.0.1', 0))
            reservations.append(listener)
            port = listener.getsockname()[1]
            ports.append((node['name'], port))
            inbounds.append({'type': 'socks', 'tag': tag, 'listen': '127.0.0.1', 'listen_port': port})
            entries.append(entry)
            rules.append({'inbound': [tag], 'action': 'route', 'outbound': tag})
        if not entries:
            raise ValueError('No resolvable entries')
        config = {'log': {'level': 'error'}, 'inbounds': inbounds, 'outbounds': entries, 'route': {'rules': rules}}
        config_path = args.output / 'sidecar.private.json'
        save(config_path, config)
        checked = subprocess.run(['sing-box', 'check', '-c', str(config_path)], capture_output=True)
        if checked.returncode:
            raise ValueError('Isolated benchmark configuration rejected; details hidden')
    finally:
        for listener in reservations:
            listener.close()
    results = []
    report = {'timestamp': datetime.datetime.now().astimezone().isoformat(), 'interface': args.interface,
              'method': '3 cold HTTPS traces per entry, round-robin; <=3 concurrent requests; no ISP authentication or relay',
              'limitations': ['Cloudflare is anycast: this does not measure a fixed destination near ISP',
                              'One Mac access network only; phone/cellular results may differ',
                              'Optional small downloads are screening samples, not sustained capacity; no UDP loss, jitter or failure recovery measurement',
                              'Hysteria2 can reuse its outer QUIC connection between cold origin-HTTPS requests'],
              'resolution_errors': resolution_errors, 'results': results, 'downloads': [], 'summary': []}
    log_path = args.output / 'sidecar.private.log'
    with log_path.open('w') as log:
        log_path.chmod(0o600)
        process = subprocess.Popen(['sing-box', 'run', '-c', str(config_path)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 5
            for _, port in ports:
                while True:
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise ValueError('Isolated listeners unavailable')
                    with socket.socket() as connection:
                        if connection.connect_ex(('127.0.0.1', port)) == 0:
                            break
                    time.sleep(.05)
            with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
                for trial in range(1, 4):
                    futures = [executor.submit(sample, name, port, trial) for name, port in ports]
                    for future in concurrent.futures.as_completed(futures):
                        item = future.result()
                        results.append(item)
                        save(args.output / 'results.private.json', report)
                    print(f'Completed round {trial}/3 for {len(ports)} entries', flush=True)
            if args.download_bytes:
                for name, port in ports:
                    report['downloads'].append(download_sample(name, port, args.download_bytes))
                    save(args.output / 'results.private.json', report)
                    print(f'Download completed: {name}', flush=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            report['sidecar_stopped'] = process.poll() is not None
            save(args.output / 'results.private.json', report)
    for node in nodes:
        attempts = [r for r in results if r['name'] == node['name']]
        good = [r for r in attempts if r['curl_exit'] == 0 and r['http'] == 200]
        summary = {'name': node['name'], 'success': len(good), 'attempts': len(attempts),
                   'median_ttfb': round(statistics.median(r['ttfb_seconds'] for r in good), 3) if good else None,
                   'worst_ttfb': round(max(r['ttfb_seconds'] for r in good), 3) if good else None}
        report['summary'].append(summary)
    save(args.output / 'results.private.json', report)
    for summary in sorted(report['summary'], key=lambda r: (-r['success'], r['median_ttfb'] or 999)):
        print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    main()
