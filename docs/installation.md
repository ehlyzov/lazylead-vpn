# Установка и обновление

[К README](../README.md)

## Обновление настроенного Mac

Если VM, DNS и маршруты уже настроены, для обновления приложения достаточно:

```bash
git pull --ff-only
swift run LazyleadVPNCoreSelfTest
./scripts/build_app_bundle.sh
./scripts/install_app.sh
```

Скрипт сохраняет предыдущую версию в `build/`, закрывает старое приложение,
устанавливает новую версию в `/Applications` и запускает её. VM не перезапускается.
Обновление приложения не переписывает настройки сети и очередь Transmission.

При обновлении с экспериментальной схемы Transmission на Mac обновите также
системный помощник Yandex Cloud:

```bash
sudo ./scripts/install_direct_routes.sh
```

Он использует уже собранный `build/direct-network/yandex-cloud-ipv4.txt`, удаляет
только старые scoped `/1` маршруты и частный PF anchor Lazylead, восстанавливает
локальный путь к VM при необходимости и проверяет доступ к Yandex API.
Новая схема использует маршруты назначения и Transmission внутри Lima.
Если снимка нет, сначала соберите его, как показано ниже.

После изменения `scripts/domain_dns.py` обновите копию DNS-службы:

```bash
./scripts/prepare_dependencies.sh
sudo ./scripts/install_gov_routes.sh
```

Несмотря на историческое имя, этот установщик обслуживает все `.ru` и `.рф`.

## Новый Mac: 1. Подготовка

Поддерживается Apple Silicon, macOS 14+, Ubuntu 24.04 ARM64 в Lima 2+.
В инструкции используется имя VM `lazylead-vpn`. Если у вас уже есть VM с другим
именем, например `existing-vpn`, используйте её имя во всех командах и настройках.
Не создавайте вторую VM поверх существующей конфигурации.

```bash
xcode-select --install
brew install lima
git clone https://github.com/ehlyzov/lazylead-vpn.git
cd lazylead-vpn
./scripts/prepare_dependencies.sh
```

`prepare_dependencies.sh` скачивает официальный socket_vmnet 1.2.2 и dnslib
0.9.26, проверяет SHA-256 и сохраняет их в `build/`. Установка системных правил
производится отдельными командами с `sudo`. Установщики не добавляют sudoers.

## 2. Прямое сетевое подключение VM

Проверьте, что физический интернет Mac использует `en0`:

```bash
networksetup -listallhardwareports
```

Текущая реализация socket_vmnet привязана к `en0`. Если ваш физический интерфейс
другой, сначала адаптируйте `scripts/install_direct_network.sh` и проверки,
не запускайте команды вслепую.

```bash
sudo ./scripts/install_direct_network.sh
python3 scripts/create_direct_vm_config.py
limactl validate build/lima-direct.yaml
limactl start --name=lazylead-vpn build/lima-direct.yaml
```

Генератор создаёт отдельный YAML с `direct0`, `vzNAT`, writable virtiofs-монтажом
вашего `~/Downloads`, локальным портом 9092 и provisioning-сценарием. Существующие
VM он не изменяет. `vm_direct_network.sh` применяется при старте VM и исключает
маршруты/DNS через хост из её интернет-пути.

Проверьте адреса:

```bash
limactl shell --workdir / lazylead-vpn ip -4 -brief address
limactl shell --workdir / lazylead-vpn ip -4 route show default
```

Ожидается единственный IPv4 default route через `direct0`, интерфейс `lima0`
с адресом `192.168.64.2/24` и Mac с `192.168.64.1/24`. Эти два адреса фиксированы
в текущей реализации. Если DHCP выдал другой адрес, остановитесь и согласуйте
адреса в помощниках; не устанавливайте маршруты на неверный шлюз.

## 3. Маршрутизатор и DNS внутри VM

```bash
limactl shell --workdir / lazylead-vpn sudo apt-get update
limactl shell --workdir / lazylead-vpn sudo apt-get install -y iptables curl dnsutils python3-yaml
limactl copy scripts/vm_direct_router.sh lazylead-vpn:/tmp/lazylead-direct-router
limactl copy packaging/lazylead-direct-router.service lazylead-vpn:/tmp/lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn sudo install -m 0755 /tmp/lazylead-direct-router /usr/local/sbin/lazylead-direct-router
limactl shell --workdir / lazylead-vpn sudo install -m 0644 /tmp/lazylead-direct-router.service /etc/systemd/system/lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn sudo systemctl daemon-reload
limactl shell --workdir / lazylead-vpn sudo systemctl enable --now lazylead-direct-router.service
limactl shell --workdir / lazylead-vpn sudo bash -s < scripts/vm_domain_dns.sh
```

Маршрутизатор разрешает forwarding только от `192.168.64.1` через `lima0` к
`direct0`, делает NAT и пропускает обратные пакеты установленных соединений.
DNS слушает `192.168.64.2:1053` по TCP и UDP.

## 4. Правила на Mac

Все `.ru`, `.рф` и их поддомены:

```bash
sudo ./scripts/install_gov_routes.sh
```

Успешный результат: `VERIFIED: .ru and .рф domains and their subdomains use Lima (IPv4).`

Yandex Cloud, включая сервисы вне `.ru`:

```bash
python3 scripts/collect_yandex_cloud_routes.py --output build/direct-network
sudo ./scripts/install_direct_routes.sh
```

Сборщик читает официальные диапазоны, CDN и каталог API. По умолчанию HTTP
запросы сборщика используют `en0`; `--interface ''` использует обычный маршрут
Mac. Снимок не обновляется автоматически: периодически повторяйте обе команды.
Установщик проверяет публичные IPv4-префиксы и доступ к API.

## 5. Transmission и файлы на Mac

```bash
GUEST_USER="$(limactl shell --workdir / lazylead-vpn id -un)"
limactl shell --workdir / lazylead-vpn sudo bash -s -- "$GUEST_USER" < scripts/vm_transmission.sh
open http://127.0.0.1:9092/transmission/web/
```

Файлы сохраняются в `~/Downloads`, незавершённые — в
`~/Downloads/.transmission-incomplete`. Очередь нативного Transmission на Mac
не импортируется автоматически. RPC доступен только на loopback гостя и Mac.
Данные приложения находятся в `/var/lib/lazylead-transmission` внутри VM.

## 6. Приложение

```bash
./scripts/build_app_bundle.sh
./scripts/install_app.sh
```

Настройки приложения читаются из `/usr/local/etc/lazylead-vpn/env`:

```text
LAZYLEAD_ROUTING_MODE=direct
LAZYLEAD_VM_NAME=lazylead-vpn
LAZYLEAD_VM_GATEWAY=192.168.64.2
```

Чтобы создать файл на новом Mac:

```bash
sudo mkdir -p /usr/local/etc/lazylead-vpn
sudo install -m 0644 examples/direct.env.example /usr/local/etc/lazylead-vpn/env
```

При существующей настройке измените только необходимые строки, сохранив
корпоративные параметры. Переменные окружения процесса имеют приоритет над файлом;
`LAZYLEAD_VPN_CONFIG` позволяет выбрать другой путь. Перезапустите приложение
после изменения режима или имени VM.

Для `.pkg`: `./scripts/build_installer_pkg.sh`. Пакет из `dist/` устанавливает
приложение, но не создаёт VM, не меняет маршруты и не настраивает Check Point.
