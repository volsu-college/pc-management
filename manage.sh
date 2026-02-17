#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOKS_DIR="$SCRIPT_DIR/playbooks"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
ENV_FILE="$SCRIPT_DIR/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Ошибка: файл .env не найден"
    exit 1
fi

FRP_API_URL="https://frp-dashboard.spo.nn-projects.ru/api/proxy/tcpmux"
FRP_PROXY_HOST="frp.spo.nn-projects.ru"
FRP_PROXY_PORT="5000"
FRP_AUTH="Basic $(echo -n "$FRP_USER:$FRP_PASSWORD" | base64)"

ANSIBLE_USER="root"

fetch_hosts() {
    echo "Получение списка хостов с FRP..." >&2

    response=$(curl -s "$FRP_API_URL" \
        -X 'GET' \
        -H 'Accept: application/json' \
        -H "Authorization: $FRP_AUTH")

    if [ -z "$response" ]; then
        echo "Ошибка: не удалось получить данные от API" >&2
        exit 1
    fi

    total=$(echo "$response" | jq -r '.proxies | length')
    online=$(echo "$response" | jq -r '[.proxies[] | select(.status == "online")] | length')

    echo "Всего хостов: $total, онлайн: $online" >&2

    if [ "$online" -eq 0 ]; then
        echo "" >&2
        echo "Нет хостов в сети. Все машины выключены." >&2
        exit 0
    fi

    echo "$response" | jq -r '.proxies[] | select(.status == "online") | .name'
}

generate_inventory() {
    local hosts="$1"

    echo "Генерация inventory файла..."

    cat > "$INVENTORY_FILE" << EOF
[targets]
EOF

    while IFS= read -r host; do
        if [ -n "$host" ]; then
            echo "${host}.volsu.ru" >> "$INVENTORY_FILE"
        fi
    done <<< "$hosts"

    cat >> "$INVENTORY_FILE" << EOF

[targets:vars]
ansible_user=$ANSIBLE_USER
ansible_password=$ANSIBLE_PASSWORD
ansible_ssh_common_args=-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="socat - PROXY:$FRP_PROXY_HOST:%h:%p,proxyport=$FRP_PROXY_PORT"
EOF

    host_count=$(echo "$hosts" | grep -c .)
    echo "Сгенерирован inventory с $host_count хостами"
}

select_playbook() {
    echo ""
    echo "Доступные плейбуки:"
    echo "==================="

    playbooks=()
    i=1
    for playbook in "$PLAYBOOKS_DIR"/*.yml; do
        if [ -f "$playbook" ]; then
            name=$(basename "$playbook" .yml)
            playbooks+=("$playbook")
            echo "  $i) $name"
            ((i++))
        fi
    done

    if [ ${#playbooks[@]} -eq 0 ]; then
        echo "Плейбуки не найдены в $PLAYBOOKS_DIR"
        exit 1
    fi

    echo ""
    read -p "Выберите плейбук (1-${#playbooks[@]}): " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#playbooks[@]} ]; then
        echo "Неверный выбор"
        exit 1
    fi

    selected_playbook="${playbooks[$((selection-1))]}"
    echo "Выбран: $(basename "$selected_playbook")"
    echo "$selected_playbook"
}

run_playbook() {
    local playbook="$1"

    echo ""
    echo "Запуск плейбука: $(basename "$playbook")"
    echo "================================"

    ansible-playbook -i "$INVENTORY_FILE" "$playbook"
}

main() {
    echo "=== Управление ПК ВолГУ ==="
    echo ""

    online_hosts=$(fetch_hosts)
    generate_inventory "$online_hosts"

    selected=$(select_playbook)

    echo ""
    read -p "Запустить плейбук на всех хостах? (y/n): " confirm

    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        run_playbook "$selected"
    else
        echo "Отменено"
        exit 0
    fi
}

main
