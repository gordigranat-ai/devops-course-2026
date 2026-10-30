#!/usr/bin/env bash
# Аудит конфигурации сервера devops-vm (ПР № 5, 6, 7).
# Использование: scripts/audit.sh ; echo $?
# Код возврата 0 — все проверки пройдены, 1 — есть нарушения.
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

# Порог проверки срока действия сертификата, дни. Переопределяется переменной
# окружения: CERT_MIN_DAYS=3650 scripts/audit.sh  (заведомо завышенный порог).
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"
CERT_MIN_SECONDS=$(( CERT_MIN_DAYS * 86400 ))

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: проверьте, что значение параметра port отлично от 22
SSH_PORT="$(sudo sshd -T | awk '/^port /{print $2}')"
check "Порт SSH отличен от 22" "yes" \
      "$( [[ -n "${SSH_PORT}" && "${SSH_PORT}" != "22" ]] && echo yes || echo no )"

# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "Число попыток аутентификации ограничено тремя" "3" \
      "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
#         источник данных: sudo ufw status verbose | grep Default
check "Политика по умолчанию для входящего трафика — deny" "deny" \
      "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"

if sudo nginx -t >/dev/null 2>&1; then NGINX_T=0; else NGINX_T=1; fi
check "Конфигурация nginx синтаксически корректна" "0" "${NGINX_T}"

if sudo openssl x509 -checkend "${CERT_MIN_SECONDS}" -noout \
        -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then CERT_OK=0; else CERT_OK=1; fi
check "Сертификат действителен не менее ${CERT_MIN_DAYS} дн." "0" "${CERT_OK}"

WW_FILES="$(find /var/www/devops-site -perm -o+w 2>/dev/null | wc -l)"
check "В каталоге ресурса нет файлов, доступных на запись всем" "0" "${WW_FILES// /}"
check "Права закрытого ключа TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер СУБД в состоянии healthy" "healthy" \
      "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'not-found')"

BAD_PORTS="$(ss -tln | awk 'NR>1 {print $4}' | grep -E ':(5000|5432)$' \
             | grep -vE '^(127\.0\.0\.1|\[::1\]):' | wc -l)"
check "Порты 5000 и 5432 не опубликованы вне 127.0.0.1" "0" "${BAD_PORTS// /}"

check "Права файла ~/app/.env равны 600" "600" \
      "$(stat -c '%a' "${HOME}/app/.env" 2>/dev/null || echo 'absent')"

echo "[6] Контрольная работа № 2"
REDIS_CID="$(cd ~/kr2 && docker compose ps -q redis 2>/dev/null)"
check "Контейнер Redis в состоянии healthy" "healthy" \
      "$(docker inspect -f '{{.State.Health.Status}}' "${REDIS_CID}" 2>/dev/null || echo 'not-found')"
check "Порт 8002 опубликован только на 127.0.0.1" "127.0.0.1:8002" \
      "$(cd ~/kr2 && docker compose port app 8002 2>/dev/null | awk '{print $1}')"
check "Права файла ~/kr2/.env равны 600" "600" \
      "$(stat -c '%a' "${HOME}/kr2/.env" 2>/dev/null || echo 'absent')"
if sudo openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/kr2.crt >/dev/null 2>&1; then KR2_CERT=0; else KR2_CERT=1; fi
check "Сертификат kr2 действителен не менее 30 дн." "0" "${KR2_CERT}"
check "Ресурс kr2 активирован символической ссылкой" "yes" \
      "$([[ -L /etc/nginx/sites-enabled/kr2 ]] && echo yes || echo no)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
