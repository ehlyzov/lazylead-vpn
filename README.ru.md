# Lazylead VPN

[English](README.md) | **Русский**

Приложение в строке меню macOS для управления сетевым шлюзом в Lima.
Текущая версия — **0.4.0**. Основной режим: выбранный трафик идёт через
виртуальную машину напрямую к провайдеру, а основной VPN на Mac продолжает работать.
**Check Point сохранён как отдельный режим.**

## Куда идёт трафик

| Трафик | Путь в основном режиме |
| --- | --- |
| Все домены `.ru`, `.рф` и их поддомены | Mac → Lima → провайдер |
| `gov.ru`, `gosuslugi.ru`, `esia.gosuslugi.ru` | Входят в правило `.ru` |
| `tbank-online.com` и его поддомены | Mac → Lima → провайдер |
| `codenrock.com` и его поддомены | Mac → Lima → провайдер |
| Плеер `hideogenius.com`, узел `ppc.ipchanger.live` и их поддомены | Mac → Lima → провайдер |
| Yandex Cloud: опубликованные IPv4-сети, API, консоль, Object Storage, CDN | Mac → Lima → провайдер, по установленному снимку адресов |
| Transmission внутри Lima | Lima → провайдер; файлы сохраняются в `~/Downloads` на Mac |
| Остальной трафик Mac | Обычный маршрут Mac, например Pepper VPN |

Приложение само не создаёт VPN-туннель и не настраивает Pepper. Маршруты и DNS
устанавливаются отдельно системными помощниками. Для их работы Lima должна быть запущена.
Маршрутизация выбранных сайтов реализована для **IPv4**.

## Начать работу

- **Новый Mac:** [пошаговая установка](docs/ru/installation.md).
- **Уже настроенный Mac:** [обновление приложения](docs/ru/installation.md#обновление-настроенного-mac).
- **Ежедневная работа, Transmission, автозапуск:** [использование](docs/ru/usage.md).
- **Не открывается сайт или пропал доступ к Lima:** [диагностика и отключение правил](docs/ru/troubleshooting.md).
- **Корпоративный VPN:** [режим Check Point](docs/ru/checkpoint.md).
- **Как устроена сеть и какие есть ограничения:** [архитектура](docs/ru/architecture.md).

В меню приложения:

| Пункт | Действие |
| --- | --- |
| `Start Lima (Direct)` | Запустить VM и проверить, что её единственный IPv4 default route использует `direct0` |
| `Stop Lima` | Остановить VM; выбранные сайты и Transmission станут недоступны |
| `Traffic & Routes…` | Учёт трафика Lima и текущей скорости; домены, диапазоны Yandex Cloud, состояние Transmission и IPv4-маршруты с поиском |
| `Settings…` | Посмотреть версию, режим, VM, пути, журнал и таблицу маршрутов |
| `Quit Lazylead VPN` / `⌘Q` | Закрыть приложение; VM и системные службы продолжают работать |

Transmission Web UI: [127.0.0.1:9092/transmission/web/](http://127.0.0.1:9092/transmission/web/).

## Сборка и проверки

Нужны Apple Silicon, macOS 14+, Xcode Command Line Tools и Lima 2+.
Полный Xcode для приложения не требуется.

```bash
./scripts/prepare_dependencies.sh
swift run LazyleadVPNCoreSelfTest
PYTHONPATH=build/domain-routing/vendor python3 scripts/test_domain_dns.py
python3 scripts/test_host_direct_routes.py
./scripts/build_app_bundle.sh
./scripts/install_app.sh
```

Приложение: `build/Lazylead VPN.app`; установка: `/Applications/Lazylead VPN.app`.
Версия хранится в [`VERSION`](VERSION), Git revision записывается в `Info.plist`.
Для сборки установочного пакета: `./scripts/build_installer_pkg.sh`.
Пакет устанавливает только приложение; VM и системные правила настраиваются по инструкции.
Локальные сборки подписываются ad-hoc, но не имеют Developer ID/notarization.

Исходники Check Point и примеры конфигурации не содержат рабочих корпоративных
адресов или учётных данных. Локальные конфиги, ключи, диагностические отчёты и
артефакты сборки исключены из Git.
