# shadowrocket-config

Общий конфиг Shadowrocket. Маршрутизация: российское — напрямую, Claude — через отдельную группу, остальное — через прокси.

## Установка на клиенте

1. Settings → Language → English (так проще ориентироваться по инструкции).
2. Добавь сервер/подписку: Home → «+».
3. Config → «+» → вставь URL:
   ```
   https://raw.githubusercontent.com/artme-dev/shadowrocket-config/main/shadowrocket.conf
   ```
   Затем тапни по конфигу → **Use Config**.
4. Settings → GeoLite2 Database (нужно для правила `GEOIP,RU`):
   - Country: `https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/Country-without-asn.mmdb`
   - ASN: `https://cdn.jsdelivr.net/gh/Loyalsoldier/geoip@release/GeoLite2-ASN.mmdb`
5. Home → Connectivity Test → включи тумблер, разреши установку VPN-профиля.
6. Проверь, что в группе **Claude** (Home → Proxy Group) есть нужный сервер. Если пусто — имя сервера не попадает в regex в `[Proxy Group]`.

## Обновление

- **Правила** (`rules/*.list`) — просто правь файл и пушь. Клиенты подтянут при следующем обновлении rule-set'ов.
- **Конфиг** (`shadowrocket.conf`) — клиенты обновляют через `update-url`; вручную: Config → потянуть список вниз или ⓘ → Update.

`raw.githubusercontent.com` кэширует файлы ~5 минут.

## Структура

| Файл | Что внутри |
|---|---|
| `shadowrocket.conf` | Основной конфиг: DNS, группы, порядок правил |
| `rules/claude.list` | Домены/IP Anthropic → группа `Claude` |
| `rules/proxy.list` | Всегда через прокси |
| `rules/direct.list` | Всегда напрямую (зоны RU, IP-чекеры) |

Синтаксис строк в `.list`: `DOMAIN-SUFFIX,example.com`, `DOMAIN,host.example.com`, `DOMAIN-KEYWORD,example`, `IP-CIDR,1.2.3.0/24,no-resolve`.

## Не коммитить

Ссылки на подписки, ключи VLESS, IP серверов, CA-сертификаты для HTTPS-декрипции — репозиторий публичный.
