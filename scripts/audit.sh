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

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
