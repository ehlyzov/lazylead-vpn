# Режим Check Point

[К README](../README.md)

Возможность работы с Check Point сохранена. Она включается явно; основной режим
приложения — прямой шлюз к провайдеру через Lima.

## Подготовка

Нужны Lima VM со `snx-rs`, рабочая конфигурация клиента внутри VM и
корпоративные параметры вашей организации. Используйте отдельную VM для
Check Point: provisioning прямого режима отключает `snx-rs.service` и убирает
маршруты через сеть хоста.

Для новой корпоративной VM есть нейтральный шаблон:

```bash
limactl start --name=lazylead-checkpoint examples/lima-vm.yaml
limactl shell --workdir / lazylead-checkpoint sudo apt-get update
limactl shell --workdir / lazylead-checkpoint sudo apt-get install -y curl ca-certificates iproute2 iptables dnsutils
limactl copy /path/to/snx-rs-package.deb lazylead-checkpoint:/tmp/snx-rs-package.deb
limactl shell --workdir / lazylead-checkpoint sudo apt-get install -y /tmp/snx-rs-package.deb
```

Выберите пакет `snx-rs` для ARM64 и вашей версии Ubuntu. Создайте его конфигурацию
в гостевой системе согласно требованиям организации, например
`$HOME/.config/snx-rs/snx-rs.conf`. Пароли, сертификаты и реальный конфиг не должны
попадать в этот репозиторий.

Если другая VZ VM уже заняла `192.168.64.2`, корпоративной VM потребуется другой
адрес. Укажите его в `LAZYLEAD_VM_GATEWAY`. Перед переключением при необходимости
[отключите правила прямого режима](troubleshooting.md#отключение-правил), чтобы
сохранённые маршруты не указывали на VM с другим назначением.

## Настройки Mac

Файл `/usr/local/etc/lazylead-vpn/env` читается приложением и legacy-помощниками.
Пример ниже содержит только публичные и документационные значения — замените их
параметрами своей организации:

```bash
LAZYLEAD_ROUTING_MODE=checkpoint
LAZYLEAD_VM_NAME=lazylead-checkpoint
LAZYLEAD_VM_GATEWAY=192.168.64.2
LAZYLEAD_SNX_CONFIG_PATH='$HOME/.config/snx-rs/snx-rs.conf'
LAZYLEAD_GATEWAY_PROBE_URL=https://vpn.example.com/clients/
LAZYLEAD_BOOTSTRAP_PROBE_IP=203.0.113.10
LAZYLEAD_CORPORATE_PROBE_IP=10.0.0.1
LAZYLEAD_SAML_BROWSER_APP=Safari
VPN_BOOTSTRAP_HOSTS="vpn.example.com sso.example.com"
VPN_PUBLIC_DNS_SERVERS="1.1.1.1 9.9.9.9"
VPN_CORPORATE_ROUTES="10.0.0.0 255.0.0.0 10.0.0.1;172.16.0.0 255.240.0.0 172.16.0.1"
VPN_DNS_DOMAINS="corp.example.com internal.example.com"
VPN_DNS_SERVERS="10.0.0.53 10.0.0.54"
VPN_ROUTE_PROBES="10.0.0.1 10.0.0.53"
```

Перезапустите Lazylead VPN. В меню появятся `Connect` и `Disconnect`.

- `Connect` запускает VM, готовит bootstrap-маршруты, запускает `snx-rs`,
  открывает браузер для SAML/2FA и после соединения устанавливает корпоративные маршруты/DNS.
- `Disconnect` останавливает `snx-rs` и удаляет корпоративные host routes/DNS.
  Bootstrap-маршруты остаются для следующего подключения.
- `Settings…` показывает режим и позволяет повторно открыть последнюю 2FA-страницу.
- `Quit` закрывает приложение; для отключения туннеля сначала используйте `Disconnect`.

Запросы администратора при смене маршрутов штатны. При необходимости можно
явно установить узкие sudoers-правила через
`sudo ./scripts/install_passwordless_sudo.sh`. Основной `.pkg` больше не включает
их автоматически. Прямой режим в этих правилах не нуждается.

Для возврата к прямому режиму восстановите `LAZYLEAD_ROUTING_MODE=direct`, имя
прямой VM и её адрес. Перезапустите приложение и установите нужные правила по
[инструкции](installation.md).

Корпоративное SAML/2FA-подключение в выпуске 0.2.0 не проверялось на рабочем
Check Point gateway: сохранены код, параметры и сборочные проверки этого режима.
