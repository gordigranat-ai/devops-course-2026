#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

REPO_ROOT="$(git rev-parse --show-toplevel)"          # требование 2
LOCAL_DIR="${REPO_ROOT}/site/"                        # завершающий / — копируется содержимое

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")         ;;
    --dry-run)  DRY_RUN=1 ;;
    *)
        echo "Неизвестный аргумент: $1" >&2
        echo "Использование: $0 [--dry-run]" >&2
        exit 2
        ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл ${LOCAL_DIR}index.html не найден — доставка отменена" >&2
    exit 1
fi

if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения:" >&2
    git -C "${REPO_ROOT}" status --short >&2
    echo "Зафиксируйте изменения (git add, git commit) и повторите запуск" >&2
    exit 1
fi

# Одно SSH-соединение на запуск (требование 8), без интерактивного ввода (требование 9)
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=5"
RSYNC_OPTS=(-avz --delete --chmod=D755,F644)

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}
if [[ ${DRY_RUN} -eq 1 ]]; then
    rsync "${RSYNC_OPTS[@]}" --dry-run -e "${SSH_CMD}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    # 4. При --dry-run — завершение с кодом 0 без проверки доступности
    echo "[dry-run] План операций выведен, состояние сервера не изменено"
    exit 0
fi

rsync "${RSYNC_OPTS[@]}" -e "${SSH_CMD}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 5. Проверка доступности ${SITE_URL} и завершение с корректным кодом возврата
if ! curl -fsS --max-time 10 --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен, доставка не подтверждена" >&2
    exit 1
fi

echo "Доставка выполнена успешно. Коммит: $(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
exit 0
