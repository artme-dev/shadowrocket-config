#!/usr/bin/env python3
"""User-session route watcher and CLI gate. Never changes the VPN or firewall."""
import argparse
import datetime
import fcntl
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'out/mac-guards/policy.json'
STATE = Path.home() / 'Library/Caches/ai-watch'
LOG = Path.home() / 'Library/Logs/ai-watch.jsonl'
ENDPOINTS = {'OPENAI': ['https://chatgpt.com/cdn-cgi/trace', 'https://api.openai.com/cdn-cgi/trace'],
             'CLAUDE': ['https://api.anthropic.com/cdn-cgi/trace']}


def run(args, timeout=15):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, '', 'timeout')


def vpn_interface():
    result = run(['/sbin/route', '-n', 'get', 'default'])
    match = re.search(r'interface:\s*(utun\d+)\b', result.stdout)
    return match.group(1) if result.returncode == 0 and match else None


def trace_ip(text):
    values = [line[3:].strip() for line in text.splitlines() if line.startswith('ip=')]
    if len(values) != 1:
        return None
    try:
        return str(ipaddress.ip_address(values[0]))
    except ValueError:
        return None


def classify(expected, first, second):
    # A network error, malformed body or a changing exit is inconclusive.
    if first == expected or second == expected:
        return 'healthy' if first == second else 'unstable'
    if first and second and first == second:
        return 'wrong_exit'
    return 'unavailable' if first is None and second is None else 'unstable'


def probe(url, interface):
    if vpn_interface() != interface:
        return None
    # Bind the probe to the checked tunnel; never silently use a direct route or env proxy.
    result = run(['/usr/bin/curl', '--silent', '--show-error', '--fail', '--noproxy', '*',
                  '--proto', '=https', '--interface', interface, '--connect-timeout', '3',
                  '--max-time', '6', '--max-filesize', '16384', url], timeout=8)
    if result.returncode or vpn_interface() != interface:
        return None
    return trace_ip(result.stdout)


def check_service(service, expected, interface, fetch=probe):
    attempts = []
    for url in ENDPOINTS[service]:
        first = fetch(url, interface)
        # Healthy responses need no second round trip. Mismatch/error needs corroboration.
        second = first if first == expected else fetch(url, interface)
        status = classify(expected, first, second)
        attempts.append({'endpoint': url, 'status': status, 'observed': [first] if first == expected else [first, second]})
    if any(a['status'] == 'wrong_exit' for a in attempts):
        status = 'wrong_exit'
    elif all(a['status'] == 'healthy' for a in attempts):
        status = 'healthy'
    elif any(a['status'] == 'healthy' for a in attempts):
        status = 'partial'
    else:
        status = 'unavailable'
    return {'service': service, 'status': status, 'expected': expected, 'checks': attempts}


def write_private(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w') as f:
        json.dump(value, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(temporary, path)


def record(report):
    LOG.parent.mkdir(parents=True, exist_ok=True)
    # Bounded local history; includes IPs but no keys, tokens or subscription URLs.
    if LOG.exists() and LOG.stat().st_size > 2_000_000:
        os.replace(LOG, LOG.with_suffix('.previous.jsonl'))
    fd = os.open(LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, 'a') as f:
        f.write(json.dumps(report, ensure_ascii=False) + '\n')
    write_private(STATE / 'status.json', report)


def notify(service, status, message):
    marker = STATE / (service + '-' + status + '.notice')
    if marker.exists() and time.time() - marker.stat().st_mtime < 600:
        return
    marker.touch(mode=0o600)
    # argv is data, never interpolate network values into AppleScript source.
    script = 'on run argv\ndisplay notification (item 1 of argv) with title "AI route guard"\nend run'
    run(['/usr/bin/osascript', '-e', script, message])


def watch(enforce=False):
    STATE.mkdir(parents=True, exist_ok=True)
    with (STATE / 'watch.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0
        policy = json.loads(POLICY.read_text())
        interface = vpn_interface()
        report = {'at': datetime.datetime.now().astimezone().isoformat(),
                  'mode': 'enforce' if enforce else 'observe', 'interface': interface, 'services': []}
        if not interface:
            report['status'] = 'vpn_unavailable'
            record(report)
            if enforce:
                notify('VPN', 'unavailable', 'Нет маршрута utun: IP-пробы не выполнялись. Проверь VPN.')
            print(json.dumps(report, ensure_ascii=False))
            return 2
        for service, cfg in policy['services'].items():
            result = check_service(service, cfg['expected_ip'], interface)
            result['terminated'] = []
            if enforce and result['status'] == 'wrong_exit':
                for process in cfg['terminate']:
                    outcome = run(['/usr/bin/pkill', '-x', process])
                    if outcome.returncode == 0:
                        result['terminated'].append(process)
            report['services'].append(result)
            if enforce and result['status'] != 'healthy':
                if result['status'] == 'wrong_exit':
                    message = f'{service}: два ответа подтвердили неверный IP. Закрыто: {", ".join(result["terminated"]) or "нет запущенных приложений"}. Проверь Config и ISP.'
                else:
                    message = f'{service}: проверка недоступна или нестабильна. Приложения не закрывались.'
                notify(service, result['status'], message)
        report['status'] = 'healthy' if all(x['status'] == 'healthy' for x in report['services']) else 'attention'
        record(report)
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report['status'] == 'healthy' else 2


def gate(service, arguments):
    cfg = json.loads(POLICY.read_text())['services'][service]
    interface = vpn_interface()
    if not interface:
        raise ValueError('Нет маршрута utun. Запуск запрещён; включи рабочий VPN.')
    result = check_service(service, cfg['expected_ip'], interface)
    if result['status'] != 'healthy':
        raise ValueError(f'{service}: ожидаемый выход не подтверждён ({result["status"]}). Запуск запрещён.')
    import shutil
    command = 'codex' if service == 'OPENAI' else 'claude'
    executable = shutil.which(command)
    if not executable:
        raise ValueError(f'{command} не найден в PATH')
    os.execv(executable, [executable, *arguments])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    w = sub.add_parser('watch'); w.add_argument('--enforce', action='store_true')
    g = sub.add_parser('gate'); g.add_argument('service', choices=['OPENAI','CLAUDE']); g.add_argument('args', nargs=argparse.REMAINDER)
    sub.add_parser('status')
    args = parser.parse_args()
    if args.action == 'watch':
        return watch(args.enforce)
    if args.action == 'gate':
        return gate(args.service, args.args)
    print((STATE / 'status.json').read_text())
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as exc:
        print('AI guard: '+str(exc), file=sys.stderr)
        sys.exit(1)
