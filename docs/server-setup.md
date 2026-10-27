# Конфигурация виртуальной машины devops-vm

Документ описывает конфигурацию целевого узла, полученную в практических работах
№ 5–7. Требование к полноте: восстановление конфигурации со снимка состояния
`01-clean-install` исключительно по настоящему описанию за 10 минут.

Порядок восстановления: разделы 1–3 (машина и сеть) → раздел 5 (SSH) → раздел 6
(межсетевой экран) → раздел 8 (веб-сервер) → раздел 9 (контейнеризация).
Раздел 4 справочный: учётная запись `devops` создаётся в разделе 5.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Средство виртуализации | Oracle VirtualBox 7.2 |
| Наименование | `devops-vm` |
| Тип и версия гостевой системы | Linux / Ubuntu (64-bit) |
| Версия ОС | Ubuntu Server 24.04 LTS (без графической подсистемы) |
| Объём оперативной памяти | 2048 МБ |
| Количество ядер процессора | 2 |
| Объём дискового накопителя | 25 ГБ, динамически расширяемый, разметка «Use an entire disk» |
| Имя узла | `devops-vm` |
| Учётная запись, созданная установщиком | `student` (входит в группу `sudo`) |
| Компоненты установки | OpenSSH server — установлен; Featured snaps — не выбирались |

Проверка: `hostnamectl` (строка `Operating System`), `nproc`, `free -m`.

## 2. Сетевые интерфейсы

| Адаптер | Тип | Адрес | Назначение |
| --- | --- | --- | --- |
| 1 | NAT | `10.0.2.15/24`, шлюз `10.0.2.2` | выход в Интернет, установка пакетов |
| 2 | Виртуальный адаптер хоста (Host-only) | `192.168.56.101/24` | доступ с хостовой системы к службам узла |

Сеть Host-only создана в менеджере сетей VirtualBox как `vboxnet0`
(`192.168.56.1/24`). Адаптер Host-only назначен до первого запуска машины, оба
адаптера включены.

Проверка: `ip -brief address` — ожидаются `10.0.2.15` и `192.168.56.101`.
Маршрут по умолчанию: `ip route` → `default via 10.0.2.2 dev enp0s3`.

## 3. Правило проброса портов

| Параметр | Значение |
| --- | --- |
| Наименование правила | `ssh` |
| Протокол | TCP |
| Адрес хостовой системы | `127.0.0.1` |
| Порт хостовой системы | `2222` |
| Адрес гостевой системы | не заполняется |
| Порт гостевой системы | `2222` |

Порт гостевой системы изменён с 22 на 2222 одновременно с директивой `Port 2222`
(раздел 5). Правило задаётся в настройках адаптера 1: «Дополнительно» → «Проброс
портов».

Проверка с хостовой системы: `ssh devops` (псевдоним из `~/.ssh/config`).

## 4. Учётные записи

| Имя | Группы | Аутентификация | Назначение |
| --- | --- | --- | --- |
| `student` | `student`, `sudo` | пароль | учётная запись установщика, резервный вход через консоль |
| `devops` | `devops`, `sudo`, `docker` | только открытый ключ (`~/.ssh/devops_vm.pub`) | рабочая учётная запись администрирования и деплоя |
| `www-data` | `www-data` | вход запрещён (`/usr/sbin/nologin`) | рабочие процессы Nginx |
| `app` | системная, без домашнего каталога | вход запрещён | процесс приложения в контейнере (раздел 9) |

Пароль `student` зафиксирован в журнале выполнения работы. Ключевая пара
`~/.ssh/devops_vm` (ed25519, комментарий `devops-vm-key`) создана на хостовой
системе; открытая часть размещена в `/home/devops/.ssh/authorized_keys`.

Проверка: `groups devops`, `stat -c '%a %n' /home/devops/.ssh /home/devops/.ssh/authorized_keys`
— ожидаются `700` и `600`.

## 5. Служба SSH

| Параметр | Значение |
| --- | --- |
| Пакет | `openssh-server` |
| Порт | `2222` |
| Файл конфигурации | `/etc/ssh/sshd_config` + дополняющий `/etc/ssh/sshd_config.d/99-hardening.conf` |
| Эталонная копия | `/etc/ssh/sshd_config.backup` |
| Активация | `ssh.service`, активация по сокету `ssh.socket` отключена |

Содержимое `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

Конфликтующая директива `PasswordAuthentication yes` в файле `50-cloud-init.conf`
закомментирована, поскольку файлы каталога обрабатываются в лексикографическом
порядке и действует первое встреченное значение.

Порядок применения:

```
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf
grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd          # 0.0.0.0:2222
```

Проверка: `sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'`.

Ключи хоста: `/etc/ssh/ssh_host_ed25519_key(.pub)`; отпечаток —
`ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`.

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny (incoming)`, `allow (outgoing)`, `deny (routed)`.
Регистрация событий: `sudo ufw logging medium`.

| № | Действие | Порт | Комментарий |
| --- | --- | --- | --- |
| 1 | `limit` | `2222/tcp` | `SSH rate-limited` |
| 2 | `allow` | `80/tcp` | `HTTP` |
| 3 | `allow` | `443/tcp` | `HTTPS` |

Порядок применения (разрешающее правило создаётся до активации):

```
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp  comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
```

Проверка: `sudo ufw status verbose` — строка `Status: active`, политика `deny (incoming)`,
правило с признаком `LIMIT` для 2222/tcp.

## 7. Снимки состояния

| Наименование | Момент создания |
| --- | --- |
| `01-clean-install` | после установки ОС, обновления пакетов и проверки сети, до создания учётной записи `devops` |
| `02-keys-configured` | после настройки ключевой аутентификации и файла `~/.ssh/config` (ПР № 5, задание 1) |
| `03-ssh-hardened` | после применения `99-hardening.conf`, смены порта на 2222 и проверок отказа (ПР № 5, задание 2) |

Снимки создаются в менеджере снимков VirtualBox при выключенной гостевой системе
(`sudo poweroff`) либо в работающем состоянии без сохранения состояния ОЗУ.
