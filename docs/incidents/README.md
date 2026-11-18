# Network incidents

- [18 November 2026 — intermittent IPRoyal latency and timeouts](2026-11-18-iproyal.md)
- [9–11 November 2026 — slow first fallback entry and priority change](2026-11-09-auto-fallback.md)

Record symptoms, comparable controls, what changed, and how recovery is verified.
Use timestamps with timezone. Store private evidence under `out/diagnostics/`.

## Повторить проверку ISP

Из корня репозитория, с доступными локальными секретами:

```sh
python3 tools/probe_isp_exit.py --route OPENAI --trials 3
```

Команда берёт настройки ISP из указанной категории и делает новые HTTPS-запросы
к Cloudflare через SOCKS5. Отчёт с временем, IP, кодом ответа и последним этапом
записывается в `out/diagnostics/YYYY-MM-DD/`. Сравнивай только результаты,
полученные одним и тем же способом. Параметр `--route` выбирает реквизиты,
а путь до прокси определяет текущая маршрутизация ОС. Для сравнения маршрутов
смотри методику и локальные артефакты в записи инцидента. Для проверки правил
Shadowrocket используй [инструкцию к профилю](../../personal/README.md).
