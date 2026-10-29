# Диагностика и отключение правил

[К README](../../README.ru.md) | [English](../troubleshooting.md)

Во всех командах замените `lazylead-vpn` своим именем VM.

## Не открывается выбранный сайт

```bash
limactl list
limactl shell --workdir / lazylead-vpn ip -4 route show default
ping -c 1 192.168.64.2
route -n get 192.168.64.2
scutil --dns
```

VM должна работать, default route гостя должен использовать только `direct0`,
а `192.168.64.2` должен быть достижим напрямую через мост Mac. Маршрут к
`192.168.64.2` через `192.168.64.2` означает ошибочный рекурсивный маршрут.
При обновлении старой экспериментальной версии выполните
`sudo ./scripts/install_direct_routes.sh`: новый помощник уберёт собственные
старые scoped `/1` маршруты/PF-правило и при необходимости восстановит ARP-путь.

Проверить системный DNS и маршрут адресов, не подменяя resolver через `dig`:

```bash
python3 - <<'PY'
import socket, subprocess
for name in ('yandex.ru', 'президент.рф', 'api.cloud.yandex.net'):
    for address in sorted({row[4][0] for row in socket.getaddrinfo(name, 443, socket.AF_INET)}):
        print(name, address)
        print(subprocess.check_output(['/sbin/route', '-n', 'get', address], text=True))
PY
curl -4 --connect-timeout 5 --max-time 15 https://api.cloud.yandex.net/endpoints
```

Для выбранных адресов ожидается `gateway: 192.168.64.2`. `dig` без явного
сервера не является проверкой правил `/etc/resolver` macOS. Прямой тест службы:
`dig @127.0.0.1 -p 1054 yandex.ru A`.

Журналы Mac:

- `~/Library/Logs/Lazylead VPN/` — приложение;
- `/var/log/lazylead-direct/gov-dns.stderr.log` — DNS-to-route;
- `/var/log/lazylead-direct/routes.stderr.log` — маршруты Yandex Cloud;
- `/var/log/lazylead-direct/stderr.log` — socket_vmnet.

Внутри VM:

```bash
limactl shell --workdir / lazylead-vpn systemctl status lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn resolvectl status direct0
limactl shell --workdir / lazylead-vpn curl -4 --max-time 15 https://api.cloud.yandex.net/endpoints
```

Если внутри VM сайт открывается, а с Mac нет, проверяйте путь Mac→VM и host routes.
Если адреса поменялись, пересоберите снимок Yandex Cloud и установите его заново.
Если работает Terminal, но не браузер, проверьте DoH и перезапустите браузер.
Не повторяйте установщики вслепую при одной и той же ошибке: сохраните сообщение
и проверьте соответствующий компонент.

## Сайты не открываются после перезапуска или пересоздания Lima

Сравните `route -n get 192.168.64.2` и `route -n get <IPv4 сайта>`.
Оба маршрута должны использовать текущий мост Lima. При исчезновении моста
macOS может сохранить шлюз маршрута, но перепривязать его к `en0`.
DNS-помощник восстанавливает только свои точные host-маршруты, если их интерфейс
отличается от текущего моста шлюза. Чужие маршруты и покрывающие префиксы
остаются нетронутыми. Пока у шлюза нет локального моста, новые маршруты не создаются.

После получения исправления один раз обновите DNS-помощник:

```bash
sudo ./scripts/install_gov_routes.sh
```

## Transmission Web UI недоступен

```bash
limactl shell --workdir / lazylead-vpn systemctl status lazylead-transmission.service
limactl shell --workdir / lazylead-vpn findmnt /mnt/mac-downloads
curl --max-time 5 http://127.0.0.1:9092/transmission/web/
```

Нужны запущенная VM, writable virtiofs-монтаж Downloads и port forward
`127.0.0.1:9092 → guest 127.0.0.1:9091`. Изменение mounts требует перезапуска VM.
Не запускайте вторую копию daemon поверх существующей очереди.

## Отключение правил

Пока VM работает, удалите сначала DNS-правила, затем префиксы Yandex Cloud:

```bash
sudo ./scripts/install_gov_routes.sh remove
sudo ./scripts/install_direct_routes.sh remove
limactl stop lazylead-vpn
```

Удаляются только собственные resolver-файлы и учтённые маршруты. Если маршрут
уже изменён другим приложением, помощники не должны удалять чужую запись.
VM, очередь Transmission и скачанные файлы остаются. Приложение можно удалить
из `/Applications` обычным способом.

Чтобы убрать также службу socket_vmnet после остановки VM:

```bash
sudo launchctl bootout system/io.lazylead.direct-network
sudo rm /Library/LaunchDaemons/io.lazylead.direct-network.plist
```

Откат приложения: закройте текущую версию и верните сохранённую
`build/Lazylead VPN.before-<дата>.app` в `/Applications/Lazylead VPN.app`.
