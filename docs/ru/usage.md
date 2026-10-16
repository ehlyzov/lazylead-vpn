# Ежедневная работа

[К README](../../README.ru.md) | [English](../usage.md)

## Запуск и завершение

Подключите основной VPN на Mac, если он нужен, затем откройте Lazylead VPN и
выберите `Start Lima (Direct)`. Если VM уже работает, команда проверит её сеть.
Состояние Connected означает, что проверка default route VM прошла; оно не
заменяет отдельную проверку системных маршрутов или доступности каждого сайта.

`Quit Lazylead VPN` закрывает только интерфейс приложения. `Stop Lima`
останавливает VM, включая Transmission. Пока VM выключена, DNS-правила и
выбранные маршруты остаются на Mac. Для возврата к обычной сети используйте
[отключение правил](troubleshooting.md#отключение-правил).

После изменения правил перезапустите браузер, чтобы закрыть старые соединения
и сбросить его DNS-кэш. На проверенном Mac Brave 1.96.60 с Secure DNS «текущий
поставщик ОС» учитывал системное правило; отдельный DoH-провайдер может его обходить.

## Transmission

Откройте [Web UI](http://127.0.0.1:9092/transmission/web/) при работающей VM.
Добавляйте торренты в Web UI; скачанные файлы появятся в `~/Downloads` на Mac.
Очередь и настройки сохраняются внутри VM между её запусками. Не удаляйте VM,
если хотите сохранить её состояние.

Проверить службу, заменив имя VM своим:

```bash
limactl shell --workdir / lazylead-vpn systemctl status lazylead-transmission.service
```

## Автозапуск приложения

```bash
./scripts/install_launch_agent.sh '/Applications/Lazylead VPN.app'
```

Это запускает интерфейс приложения после входа в macOS. Для запуска VM нажмите
`Start Lima (Direct)` — этот LaunchAgent сам не выполняет Connect.
Отключение автозапуска:

```bash
launchctl bootout "gui/$(id -u)/io.lazylead.vpn.autostart"
launchctl disable "gui/$(id -u)/io.lazylead.vpn.autostart"
```

## Обновление адресов Yandex Cloud

```bash
python3 scripts/collect_yandex_cloud_routes.py --output build/direct-network
sudo ./scripts/install_direct_routes.sh
```

DNS-служба для `.ru`/`.рф` изучает новые адреса по запросам автоматически.
Для остальных зон Yandex Cloud используется отдельный снимок префиксов.
