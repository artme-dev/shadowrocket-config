# shadowrocket-config

Общий конфиг Shadowrocket. Маршрутизация: российское — напрямую, Claude — через отдельную группу, остальное — через прокси.

## Установка на клиенте

1. Settings → Language → English (так проще ориентироваться по инструкции).
2. Добавь сервер/подписку: Home → «+».
3. Config → «+» → вставь URL:
   ```
   https://raw.githubusercontent.com/artme-dev/shadowrocket-config/main/artme.conf
   ```
   Затем тапни по конфигу → **Use Config**.
4. Settings → GeoLite2 Database (нужно для правила `GEOIP,RU`):
   - Country: `https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/Country-without-asn.mmdb`
   - ASN: `https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/GeoLite2-ASN.mmdb`
5. Home → Connectivity Test → включи тумблер, разреши установку VPN-профиля.
6. Проверь, что в группе **Claude** (Home → Proxy Group) есть нужный сервер. Если пусто — имя сервера не попадает в regex в `[Proxy Group]`.

## Как менять

Всё в `artme.conf`. Исключение — длинные списки IP-диапазонов: они лежат в `rules/*.list` (в этом же репозитории) и подключаются строкой `RULE-SET,<raw-url>,POLICY`. Сейчас это `rules/zoom.list`. В `.list` политика не указывается: `IP-CIDR,1.2.3.0/24,no-resolve`.

- Добавить домен: строка в нужный блок `[Rule]` — `DOMAIN-SUFFIX,example.com,PROXY` / `DIRECT` / `Claude`.
- Порядок в `[Rule]` важен: первое совпавшее правило побеждает (Claude → прокси → напрямую → GEOIP → FINAL).
- Запушь в `main`. Клиенты подтянут через `update-url`; вручную: Config → ⓘ → Update.

`raw.githubusercontent.com` кэширует файлы ~5 минут.

Синтаксис: `DOMAIN-SUFFIX,example.com,POLICY`, `DOMAIN,host.example.com,POLICY`, `DOMAIN-KEYWORD,example,POLICY`, `IP-CIDR,1.2.3.0/24,POLICY,no-resolve`.

## Не коммитить

Ссылки на подписки, ключи VLESS, IP серверов, CA-сертификаты для HTTPS-декрипции — репозиторий публичный.
