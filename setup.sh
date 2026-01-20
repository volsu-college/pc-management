#!/bin/bash

################################################################################
# Скрипт управления ПК
# Этот скрипт предоставляет утилиты для управления прокси и установки ПО
################################################################################

set -euo pipefail

# Function to load environment variables from .env file
load_env_file() {
    local env_file="${1:-.env}"
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment variables from $env_file"
        # shellcheck disable=SC2086
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
        log_success "Environment variables loaded"
    fi
}

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функции логирования
log_info() {
    echo -e "${BLUE}[ИНФО]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[УСПЕХ]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[ПРЕДУПРЕЖДЕНИЕ]${NC} $1"
}

log_error() {
    echo -e "${RED}[ОШИБКА]${NC} $1"
}

################################################################################
# РАЗДЕЛ УПРАВЛЕНИЯ ПРОКСИ
################################################################################

# Вспомогательная функция для установки прокси для конкретного пользователя
set_proxy_for_user() {
    local proxy_url="$1"
    local target_user="$2"
    local user_home
    
    # Получаем домашний каталог пользователя
    user_home=$(eval echo "~${target_user}")
    
    if [[ ! -d "$user_home" ]]; then
        log_warning "Домашний каталог для пользователя $target_user не найден: $user_home"
        return 1
    fi
    
    local bashrc_path="${user_home}/.bashrc"
    log_info "Конфигурирование прокси для пользователя $target_user в $bashrc_path..."

    # Удалить ранее созданный блок прокси между маркерами если он есть, затем добавить новый помеченный блок
    # Это позволяет безопасно обновлять все переменные прокси в одном месте
    if [[ -f "$bashrc_path" ]]; then
        sudo sed -i '/^# >>> VOLSU_PROXY_START/,/^# <<< VOLSU_PROXY_END/d' "$bashrc_path" || true
    else
        # Создаем файл .bashrc если его нет
        sudo touch "$bashrc_path"
        sudo chown "${target_user}:${target_user}" "$bashrc_path"
    fi

    # Добавляем прокси блок в .bashrc
    {
        echo "# >>> VOLSU_PROXY_START"
        echo "# Конфигурация прокси для volsu-pc-management"
        echo "export HTTP_PROXY=\"$proxy_url\""
        echo "export HTTPS_PROXY=\"$proxy_url\""
        echo "export http_proxy=\"$proxy_url\""
        echo "export https_proxy=\"$proxy_url\""
        echo "export FTP_PROXY=\"$proxy_url\""
        echo "export ftp_proxy=\"$proxy_url\""
        echo "# <<< VOLSU_PROXY_END"
    } | sudo tee -a "$bashrc_path" > /dev/null

    log_success "Параметры прокси записаны в $bashrc_path для пользователя $target_user"
    
    # Конфигурирование прокси для rsync
    local rsync_conf="${user_home}/.rsync"
    if [[ ! -d "$rsync_conf" ]]; then
        sudo mkdir -p "$rsync_conf"
        sudo chown "${target_user}:${target_user}" "$rsync_conf"
    fi
    
    # Создаем конфигурацию rsync
    {
        echo "# Конфигурация прокси для rsync"
        echo "proxy=$proxy_url"
    } | sudo tee "$rsync_conf/rsync.conf" > /dev/null
    sudo chown "${target_user}:${target_user}" "$rsync_conf/rsync.conf"
    log_success "Прокси для rsync настроен для пользователя $target_user"
}

# Функция установки прокси
set_proxy() {
    local proxy_url="$1"
    
    log_info "Установка прокси: $proxy_url"
    
    # Установка прокси для dnf (конфигурация DNF)
    log_info "Конфигурирование прокси для dnf..."
    if [[ -f /etc/dnf/dnf.conf ]]; then
        if grep -q "^proxy=" /etc/dnf/dnf.conf; then
            sudo sed -i "s|^proxy=.*|proxy=$proxy_url|" /etc/dnf/dnf.conf
        else
            echo "proxy=$proxy_url" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
        fi
        log_success "Прокси для DNF настроен"
    else
        log_warning "Файл конфигурации DNF не найден в /etc/dnf/dnf.conf"
    fi
    
    # Определяем текущего пользователя
    local current_user="${USER}"
    
    # Если скрипт запущен через sudo, получаем реального пользователя
    if [[ -n "${SUDO_USER:-}" ]]; then
        current_user="${SUDO_USER}"
        log_info "Скрипт запущен через sudo, настройка прокси для пользователя: $current_user"
    fi
    
    # Установка прокси для текущего пользователя
    set_proxy_for_user "$proxy_url" "$current_user"
    
    # Если скрипт запущен через sudo, также настроить прокси для пользователя student
    if [[ -n "${SUDO_USER:-}" ]] && id "student" &>/dev/null && [[ "$current_user" != "student" ]]; then
        log_info "Настройка прокси также для пользователя student..."
        set_proxy_for_user "$proxy_url" "student"
    fi
    
    # Экспорт в текущую оболочку
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export FTP_PROXY="$proxy_url"
    export ftp_proxy="$proxy_url"

    log_success "Прокси применены в текущей сессии"

    # Конфигурирование прокси для snap
    log_info "Конфигурирование прокси для snap..."

    # Убедимся, что snap доступен — если нет, попытаемся установить и инициализировать snapd
    if ! command -v snap &> /dev/null; then
        log_info "Snap не установлен. Попытка установки snapd..."
        if command -v dnf &> /dev/null; then
            sudo dnf install -y snapd
            # Запуск и включение snapd
            sudo systemctl enable snapd --now
            log_info "Ожидание инициализации snapd..."
            sleep 3

            # Создание symlink /snap -> /var/lib/snapd/snap для classic confinement, если нужно
            if [[ ! -L /snap ]] && [[ ! -d /snap ]]; then
                sudo ln -s /var/lib/snapd/snap /snap
                log_success "Symlink /snap создан для поддержки snap"
            elif [[ -L /snap ]] && [[ $(readlink /snap) != "/var/lib/snapd/snap" ]]; then
                sudo rm -f /snap
                sudo ln -s /var/lib/snapd/snap /snap
                log_success "Symlink /snap переоздан для поддержки snap"
            fi
        else
            log_warning "Менеджер пакетов dnf не найден. Пропуск установки snap"
        fi
    fi

    if command -v snap &> /dev/null; then
        sudo snap set system proxy.http="$proxy_url"
        sudo snap set system proxy.https="$proxy_url"
        log_success "Прокси для snap настроен"
    else
        log_warning "Snap недоступен: пропуск конфигурирования прокси для snap"
    fi
    
    log_success "Конфигурация прокси завершена"
    if [[ -n "${SUDO_USER:-}" ]]; then
        log_info "Прокси настроен для пользователей: $current_user"
        if id "student" &>/dev/null && [[ "$current_user" != "student" ]]; then
            log_info "  и student"
        fi
        log_info "Пользователи должны выполнить: source ~/.bashrc"
    else
        log_info "Пожалуйста, выполните: source ~/.bashrc"
    fi
}

# Вспомогательная функция для отключения прокси для конкретного пользователя
disable_proxy_for_user() {
    local target_user="$1"
    local user_home
    
    # Получаем домашний каталог пользователя
    user_home=$(eval echo "~${target_user}")
    
    if [[ ! -d "$user_home" ]]; then
        log_warning "Домашний каталог для пользователя $target_user не найден: $user_home"
        return 1
    fi
    
    local bashrc_path="${user_home}/.bashrc"
    log_info "Удаление прокси для пользователя $target_user из $bashrc_path..."
    
    # Удаление помеченного блока прокси
    if [[ -f "$bashrc_path" ]]; then
        sudo sed -i '/^# >>> VOLSU_PROXY_START/,/^# <<< VOLSU_PROXY_END/d' "$bashrc_path" || true
        log_success "Прокси удален из $bashrc_path для пользователя $target_user"
    fi
    
    # Удаление конфигурации rsync
    local rsync_conf="${user_home}/.rsync"
    if [[ -f "$rsync_conf/rsync.conf" ]]; then
        sudo rm -f "$rsync_conf/rsync.conf"
        log_success "Конфигурация rsync удалена для пользователя $target_user"
    fi
}

# Функция отключения прокси
disable_proxy() {
    log_info "Отключение конфигурации прокси..."
    
    # Удаление прокси из dnf
    if [[ -f /etc/dnf/dnf.conf ]]; then
        sudo sed -i '/^proxy=/d' /etc/dnf/dnf.conf
        log_success "Прокси удален из конфигурации DNF"
    fi
    
    # Определяем текущего пользователя
    local current_user="${USER}"
    
    # Если скрипт запущен через sudo, получаем реального пользователя
    if [[ -n "${SUDO_USER:-}" ]]; then
        current_user="${SUDO_USER}"
        log_info "Скрипт запущен через sudo, удаление прокси для пользователя: $current_user"
    fi
    
    # Отключение прокси для текущего пользователя
    disable_proxy_for_user "$current_user"
    
    # Если скрипт запущен через sudo, также отключить прокси для пользователя student
    if [[ -n "${SUDO_USER:-}" ]] && id "student" &>/dev/null && [[ "$current_user" != "student" ]]; then
        log_info "Удаление прокси также для пользователя student..."
        disable_proxy_for_user "student"
    fi
    
    # Отмена установки в текущей оболочке
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset http_proxy
    unset https_proxy
    unset FTP_PROXY
    unset ftp_proxy
    
    # Удаление прокси из snap если snap установлен
    if command -v snap &> /dev/null; then
        log_info "Удаление конфигурации прокси для snap..."
        sudo snap unset system proxy.http
        sudo snap unset system proxy.https
        log_success "Прокси удален из конфигурации snap"
    fi
    
    log_success "Конфигурация прокси отключена"
    if [[ -n "${SUDO_USER:-}" ]]; then
        log_info "Прокси удален для пользователей: $current_user"
        if id "student" &>/dev/null && [[ "$current_user" != "student" ]]; then
            log_info "  и student"
        fi
        log_info "Пользователи должны выполнить: source ~/.bashrc"
    else
        log_info "Пожалуйста, выполните: source ~/.bashrc"
    fi
}

# Функция для отображения статуса прокси
show_proxy_status() {
    log_info "Текущие параметры прокси:"
    echo "  HTTP_PROXY: ${HTTP_PROXY:-не установлен}"
    echo "  HTTPS_PROXY: ${HTTPS_PROXY:-не установлен}"
    echo "  FTP_PROXY: ${FTP_PROXY:-не установлен}"
    
    if [[ -f /etc/dnf/dnf.conf ]]; then
        echo -n "  Прокси DNF: "
        grep "^proxy=" /etc/dnf/dnf.conf || echo "не установлен"
    fi
    
    rsync_conf="${HOME}/.rsync/rsync.conf"
    if [[ -f "$rsync_conf" ]]; then
        echo -n "  Прокси rsync: "
        grep "^proxy=" "$rsync_conf" || echo "не установлен"
    else
        echo "  Прокси rsync: не установлен"
    fi
    
    # Отображение статуса прокси snap если snap установлен
    if command -v snap &> /dev/null; then
        echo "  Прокси snap:"
        echo -n "    http: "
        sudo snap get system proxy.http || echo "не установлен"
        echo -n "    https: "
        sudo snap get system proxy.https || echo "не установлен"
    fi
}

# Функция для конфигурирования NetworkManager с статическим IP, шлюзом и DNS
# На основе документации РЕД ОС: https://redos.red-soft.ru/base/redos-7_3/7_3-network/7_3-sett-network/7_3-network-settings/
configure_network_manager() {
    log_info "Конфигурирование NetworkManager согласно документации РЕД ОС..."
    
    # Получение списка сетевых интерфейсов
    local interfaces=($(nmcli device status | awk 'NR>1 {print $1}' | grep -v lo))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_error "Не найдено активных сетевых интерфейсов"
        return 1
    fi
    
    log_info "Доступные сетевые интерфейсы:"
    for i in "${!interfaces[@]}"; do
        echo "  $((i+1)). ${interfaces[$i]}"
    done
    
    echo -n "Выберите номер интерфейса: "
    read -r iface_choice
    
    if [[ ! "$iface_choice" =~ ^[0-9]+$ ]] || (( iface_choice < 1 || iface_choice > ${#interfaces[@]} )); then
        log_error "Неверный выбор"
        return 1
    fi
    
    local interface="${interfaces[$((iface_choice-1))]}"
    log_info "Выбран интерфейс: $interface"
    
    # Получение текущего подключения
    # Использование nmcli device status для получения имени соединения
    local connection=$(nmcli device status | grep "^$interface" | awk '{print $2}')
    
    if [[ -z "$connection" ]] || [[ "$connection" == "--" ]]; then
        log_warning "Подключение не найдено, попытка использовать альтернативный метод..."
        # Альтернативный способ получения названия соединения
        connection=$(nmcli -t -f NAME connection | head -1)
        
        if [[ -z "$connection" ]]; then
            log_error "Не удалось получить название подключения для интерфейса $interface"
            return 1
        fi
    fi
    
    log_info "Выбрано подключение: $connection"
    
    # Запрос параметров сети согласно документации
    echo ""
    echo -n "Введите статический IP адрес (например, 192.168.1.100): "
    read -r static_ip
    
    # Валидация IP адреса
    if ! [[ "$static_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Неверный формат IP адреса"
        return 1
    fi
    
    echo -n "Введите маску подсети (например, 24 для /24 или 255.255.255.0): "
    read -r netmask
    
    # Преобразование маски подсети если нужно (согласно документации)
    if [[ "$netmask" == *.* ]]; then
        # Преобразование стандартной маски в CIDR
        case "$netmask" in
            255.255.255.0) netmask=24 ;;
            255.255.255.128) netmask=25 ;;
            255.255.255.192) netmask=26 ;;
            255.255.255.224) netmask=27 ;;
            255.255.255.240) netmask=28 ;;
            255.255.255.248) netmask=29 ;;
            255.255.255.252) netmask=30 ;;
            255.255.0.0) netmask=16 ;;
            255.0.0.0) netmask=8 ;;
            *) log_warning "Неизвестный формат маски, используется как CIDR" ;;
        esac
    fi
    
    # Валидация маски подсети
    if ! [[ "$netmask" =~ ^[0-9]{1,2}$ ]] || (( netmask < 0 || netmask > 32 )); then
        log_error "Неверная маска подсети. Должна быть от 0 до 32"
        return 1
    fi
    
    echo -n "Введите IP адрес шлюза (gateway) (например, 192.168.1.1): "
    read -r gateway
    
    if ! [[ "$gateway" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Неверный формат IP адреса шлюза"
        return 1
    fi
    
    echo -n "Введите DNS сервер (например, 8.8.8.8): "
    read -r dns_server
    
    if ! [[ "$dns_server" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Неверный формат IP адреса DNS"
        return 1
    fi
    
    log_info "Конфигурирование подключения $connection..."
    
    # Установка параметров согласно документации РЕД ОС
    # Метод: manual (статический IP)
    log_info "Установка статического IP адреса..."
    
    local error_output
    error_output=$(nmcli connection modify "$connection" ipv4.method manual 2>&1)
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_error "Ошибка при установке метода ipv4.method для подключения '$connection'"
        log_error "Детали: $error_output"
        log_info "Доступные подключения:"
        nmcli connection show --active 2>/dev/null || nmcli connection show 2>/dev/null
        return 1
    fi
    
    # Установка IP адреса и маски (address1=192.168.1.100/24,192.168.1.1)
    log_info "Установка адреса: $static_ip/$netmask с шлюзом $gateway..."
    error_output=$(nmcli connection modify "$connection" ipv4.addresses "${static_ip}/${netmask}" 2>&1)
    if [[ $? -ne 0 ]]; then
        log_error "Ошибка при установке ipv4.addresses"
        log_error "Детали: $error_output"
        return 1
    fi
    
    error_output=$(nmcli connection modify "$connection" ipv4.gateway "$gateway" 2>&1)
    if [[ $? -ne 0 ]]; then
        log_error "Ошибка при установке ipv4.gateway"
        log_error "Детали: $error_output"
        return 1
    fi
    
    # Установка DNS (может быть несколько: dns=8.8.8.8;8.8.4.4;192.168.1.1)
    log_info "Установка DNS сервера: $dns_server..."
    error_output=$(nmcli connection modify "$connection" ipv4.dns "$dns_server" 2>&1)
    if [[ $? -ne 0 ]]; then
        log_error "Ошибка при установке ipv4.dns"
        log_error "Детали: $error_output"
        return 1
    fi
    
    # Игнорирование автоматического DNS (ignore-auto-dns=true)
    nmcli connection modify "$connection" ipv4.ignore-auto-dns yes 2>/dev/null
    
    # Отправка имени хоста (DHCP)
    nmcli connection modify "$connection" ipv4.dhcp-send-hostname yes 2>/dev/null
    
    log_success "Параметры сети установлены:"
    echo "  IP адрес и маска: $static_ip/$netmask"
    echo "  Шлюз: $gateway"
    echo "  DNS сервер: $dns_server"
    echo "  Игнорирование авто-DNS: включено"
    
    # Перезагрузка подключения (согласно документации)
    log_info "Применение изменений - перезагрузка подключения..."
    nmcli connection down "$connection" 2>/dev/null
    sleep 1
    nmcli connection up "$connection" 2>/dev/null
    
    # Ожидание инициализации
    sleep 2
    
    # Проверка статуса конфигурации
    log_info "Проверка статуса конфигурации..."
    local ipv4_method=$(nmcli connection show "$connection" | grep "ipv4.method" | awk '{print $2}')
    local ipv4_addresses=$(nmcli connection show "$connection" | grep "ipv4.addresses" | awk '{print $2}')
    local ipv4_gateway=$(nmcli connection show "$connection" | grep "ipv4.gateway" | awk '{print $2}')
    local ipv4_dns=$(nmcli connection show "$connection" | grep "ipv4.dns" | awk '{print $2}')
    
    if [[ "$ipv4_method" == "manual" ]]; then
        log_success "Метод конфигурации: СТАТИЧЕСКИЙ"
    else
        log_warning "Метод конфигурации: $ipv4_method"
    fi
    
    log_success "NetworkManager успешно переконфигурирован"
    log_info "Текущая конфигурация подключения $connection:"
    echo "  Метод: $ipv4_method"
    echo "  Адреса: $ipv4_addresses"
    echo "  Шлюз: $ipv4_gateway"
    echo "  DNS: $ipv4_dns"
    
    log_info "Состояние интерфейса $interface:"
    nmcli device show "$interface" | grep -E "GENERAL.CONNECTION|IP4.ADDRESS|IP4.GATEWAY|IP4.DNS"
}

proxy_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Управление прокси ===${NC}"
        echo "1. Установить прокси"
        echo "2. Отключить прокси"
        echo "3. Показать статус прокси"
        echo "4. Конфигурирование сетевых параметров (IP, DNS, шлюз)"
        echo "5. Вернуться в главное меню"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                echo -n "Введите IP адрес прокси (например, 10.10.9.1): "
                read -r proxy_ip
                proxy_url="http://${proxy_ip}:3127"
                
                # Проверка, требуется ли sudo для настройки нескольких пользователей
                if [[ "${USER}" == "red8" ]] && [[ -z "${SUDO_USER:-}" ]]; then
                    log_info "Для настройки прокси для пользователей red8 и student требуются права sudo"
                    # Устанавливаем SUDO_USER для функции set_proxy
                    export SUDO_USER="${USER}"
                    set_proxy "$proxy_url"
                    unset SUDO_USER
                else
                    set_proxy "$proxy_url"
                fi
                ;;
            2)
                # Проверка, требуется ли sudo для отключения прокси для нескольких пользователей
                if [[ "${USER}" == "red8" ]] && [[ -z "${SUDO_USER:-}" ]]; then
                    log_info "Для отключения прокси для пользователей red8 и student требуются права sudo"
                    # Устанавливаем SUDO_USER для функции disable_proxy
                    export SUDO_USER="${USER}"
                    disable_proxy
                    unset SUDO_USER
                else
                    disable_proxy
                fi
                ;;
            3)
                show_proxy_status
                ;;
            4)
                configure_network_manager
                ;;
            5)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

################################################################################
# РАЗДЕЛ УСТАНОВКИ ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ
################################################################################

# Функция для установки Visual Studio Code через snap
install_vscode() {
    log_info "Установка Visual Studio Code через snap..."
    
    if command -v code &> /dev/null; then
        log_warning "Visual Studio Code уже установлен"
        return 0
    fi
    
    # Проверка установки snap
    if ! command -v snap &> /dev/null; then
        log_info "Snap не установлен. Установка snap..."
        sudo dnf install -y snapd
        
        # Запуск и включение snapd в автозагрузку
        sudo systemctl enable snapd --now
        
        log_info "Ожидание инициализации snapd..."
        sleep 3
    fi
    
    # Исправление для classic confinement: создание symlink /snap если его нет
    log_info "Проверка symlink для classic confinement..."
    if [[ ! -L /snap ]] && [[ ! -d /snap ]]; then
        log_info "Создание symlink /snap -> /var/lib/snapd/snap для поддержки classic confinement..."
        sudo ln -s /var/lib/snapd/snap /snap
        log_success "Symlink создан успешно"
    elif [[ -L /snap ]] && [[ $(readlink /snap) != "/var/lib/snapd/snap" ]]; then
        log_warning "/snap существует но указывает на неправильный путь. Удаление и переновое создание..."
        sudo rm -f /snap
        sudo ln -s /var/lib/snapd/snap /snap
        log_success "Symlink переоздан успешно"
    fi
    
    # Установка Visual Studio Code через snap
    log_info "Установка Visual Studio Code из snap..."
    if sudo snap install code --classic; then
        log_success "Visual Studio Code успешно установлен через snap"
        log_info "Запуск: code или через меню Программирование"
    else
        log_error "Ошибка при установке Visual Studio Code"
        return 1
    fi
}


# Функция для установки PyCharm Community
install_pycharm() {
    log_info "Установка PyCharm Community Edition через snap..."
    
    # Проверка установки PyCharm
    if snap list pycharm-community &> /dev/null; then
        log_warning "PyCharm Community уже установлен"
        return 0
    fi
    
    # Проверка установки snap
    if ! command -v snap &> /dev/null; then
        log_info "Snap не установлен. Установка snap..."
        sudo dnf install -y snapd
        
        # Запуск и включение snapd в автозагрузку
        sudo systemctl enable snapd --now
        
        log_info "Ожидание инициализации snapd..."
        sleep 3
    fi
    
    # Исправление для classic confinement: создание symlink /snap если его нет
    log_info "Проверка symlink для classic confinement..."
    if [[ ! -L /snap ]] && [[ ! -d /snap ]]; then
        log_info "Создание symlink /snap -> /var/lib/snapd/snap для поддержки classic confinement..."
        sudo ln -s /var/lib/snapd/snap /snap
        log_success "Symlink создан успешно"
    elif [[ -L /snap ]] && [[ $(readlink /snap) != "/var/lib/snapd/snap" ]]; then
        log_warning "/snap существует но указывает на неправильный путь. Удаление и переновое создание..."
        sudo rm -f /snap
        sudo ln -s /var/lib/snapd/snap /snap
        log_success "Symlink переоздан успешно"
    fi
    
    # Установка PyCharm Community через snap
    log_info "Установка PyCharm Community из snap..."
    if sudo snap install pycharm-community --classic; then
        log_success "PyCharm Community успешно установлен через snap"
        log_info "Запуск: pycharm-community или через меню Программирование"
    else
        log_error "Ошибка при установке PyCharm Community"
        return 1
    fi
}

# Функция для установки libvirt
install_libvirt() {
    log_info "Установка libvirt..."
    
    if command -v virsh &> /dev/null; then
        log_warning "libvirt уже установлен"
        return 0
    fi
    
    # Установка пакетов libvirt согласно документации
    log_info "Установка пакетов: libvirt, qemu-kvm, virt-install, virt-manager..."
    sudo dnf install -y libvirt qemu-kvm virt-install virt-manager openssh-askpass OVMF boost-random boost-program-options boost-regex
    
    if [[ $? -eq 0 ]]; then
        log_success "Пакеты libvirt установлены успешно"
        
        # Запуск и добавление в автозагрузку службы libvirtd
        log_info "Запуск и добавление в автозагрузку службы libvirtd..."
        sudo systemctl enable libvirtd --now
        
        # Проверка статуса
        if systemctl is-active --quiet libvirtd; then
            log_success "Служба libvirtd успешно запущена"
        else
            log_error "Ошибка при запуске службы libvirtd"
            return 1
        fi

        if command -v virsh &> /dev/null; then
             # Добавление текущего пользователя в группу libvirt
            log_info "Добавление пользователя в группу libvirt..."
            sudo usermod -a -G libvirt "$USER"
            log_success "Пользователь добавлен в группу libvirt"
        fi
        
        # Настройка прав доступа к сокетам libvirt
        log_info "Конфигурирование прав доступа к сокетам libvirt..."
        sudo mkdir -p /etc/libvirt/
        
        # Создание конфигурации для расширенного доступа через UNIX сокеты
        if [[ ! -f /etc/libvirt/libvirtd.conf ]] || ! grep -q "unix_sock_group" /etc/libvirt/libvirtd.conf; then
            log_info "Обновление конфигурации libvirtd..."
            sudo tee -a /etc/libvirt/libvirtd.conf > /dev/null <<'LIBVIRT_EOF'

# Разрешить членам группы libvirt подключаться через UNIX сокет
unix_sock_group = "libvirt"
unix_sock_rw_perms = "0770"
LIBVIRT_EOF
            
            # Перезагрузка libvirtd для применения конфигурации
            log_info "Перезагрузка libvirtd..."
            sudo systemctl restart libvirtd
            log_success "Конфигурация libvirtd применена"
        fi
        
        # Создание polkit правил для членов группы libvirt
        log_info "Конфигурирование polkit правил..."
        sudo mkdir -p /etc/polkit-1/rules.d/
        
        if [[ ! -f /etc/polkit-1/rules.d/50-libvirt.rules ]]; then
            sudo tee /etc/polkit-1/rules.d/50-libvirt.rules > /dev/null <<'POLKIT_EOF'
// Разрешить членам группы libvirt управлять виртуальными машинами
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("libvirt")) {
        if (action.id.match(/^org\.libvirt\./)) {
            return polkit.Result.YES;
        }
    }
});
POLKIT_EOF
            log_success "Правила polkit созданы"
        fi
        
        log_warning "Требуется перезагрузка системы или повторный вход в систему для применения прав группы"
        
        # Создание и конфигурация директории для виртуальных машин
        log_info "Конфигурирование директории для виртуальных машин..."
        vm_dir="/home/$USER/virtmachine/images"
        
        # Создание директории если её нет
        if [[ ! -d "$vm_dir" ]]; then
            log_info "Создание директории: $vm_dir"
            mkdir -p "$vm_dir"
        fi
        
        # Установка прав доступа для пользователя
        log_info "Установка прав доступа (rwx) для директории виртуальных машин..."
        sudo chown "$USER:$USER" "/home/$USER/virtmachine" 2>/dev/null || sudo mkdir -p "/home/$USER/virtmachine" && sudo chown "$USER:$USER" "/home/$USER/virtmachine"
        sudo chown "$USER:$USER" "$vm_dir"
        sudo chmod 755 "/home/$USER/virtmachine"
        sudo chmod 755 "$vm_dir"
        
        log_success "Директория $vm_dir настроена с правами для пользователя $USER"
        
    else
        log_error "Ошибка при установке libvirt"
        return 1
    fi
}

# Функция для проверки и исправления прав доступа libvirt директории
check_fix_libvirt_rights() {
    log_info "Проверка прав доступа libvirt..."
    
    # Проверка установки libvirt
    if ! command -v virsh &> /dev/null; then
        log_error "libvirt не установлен на системе"
        log_info "Установите libvirt через опцию '3. Установить libvirt (QEMU-KVM)'"
        return 1
    fi
    
    log_success "libvirt установлен"
    
    vm_dir="/home/$USER/virtmachine/images"
    parent_dir="/home/$USER/virtmachine"
    
    # Проверка существования директорий
    if [[ ! -d "$parent_dir" ]]; then
        log_warning "Директория $parent_dir не существует. Создание..."
        mkdir -p "$parent_dir"
        sudo chown "$USER:$USER" "$parent_dir"
        sudo chmod 755 "$parent_dir"
        log_success "Директория $parent_dir создана"
    fi
    
    if [[ ! -d "$vm_dir" ]]; then
        log_warning "Директория $vm_dir не существует. Создание..."
        mkdir -p "$vm_dir"
    fi
    
    # Проверка и вывод текущих прав
    log_info "Текущие права доступа:"
    echo "  $parent_dir:"
    ls -ld "$parent_dir" | awk '{print "    " $1, $3 ":" $4, "(" $9 ")"}'
    echo "  $vm_dir:"
    ls -ld "$vm_dir" | awk '{print "    " $1, $3 ":" $4, "(" $9 ")"}'
    
    # Проверка и исправление прав
    local need_fix=0
    
    # Проверка владельца родительской директории
    parent_owner=$(stat -c %U "$parent_dir")
    if [[ "$parent_owner" != "$USER" ]]; then
        log_warning "Владелец $parent_dir: $parent_owner (требуется: $USER)"
        need_fix=1
    fi
    
    # Проверка владельца директории images
    vm_owner=$(stat -c %U "$vm_dir")
    if [[ "$vm_owner" != "$USER" ]]; then
        log_warning "Владелец $vm_dir: $vm_owner (требуется: $USER)"
        need_fix=1
    fi
    
    # Проверка прав доступа
    parent_perms=$(stat -c %a "$parent_dir")
    if [[ "$parent_perms" != "755" && "$parent_perms" != "775" ]]; then
        log_warning "Права на $parent_dir: $parent_perms (требуются: 755 или 775)"
        need_fix=1
    fi
    
    vm_perms=$(stat -c %a "$vm_dir")
    if [[ "$vm_perms" != "755" && "$vm_perms" != "775" ]]; then
        log_warning "Права на $vm_dir: $vm_perms (требуются: 755 или 775)"
        need_fix=1
    fi
    
    # Исправление прав если необходимо
    if [[ $need_fix -eq 1 ]]; then
        log_info "Исправление прав доступа..."
        sudo chown "$USER:$USER" "$parent_dir"
        sudo chown "$USER:$USER" "$vm_dir"
        sudo chmod 755 "$parent_dir"
        sudo chmod 755 "$vm_dir"
        log_success "Права доступа исправлены"
        
        log_info "Новые права доступа:"
        echo "  $parent_dir:"
        ls -ld "$parent_dir" | awk '{print "    " $1, $3 ":" $4, "(" $9 ")"}'
        echo "  $vm_dir:"
        ls -ld "$vm_dir" | awk '{print "    " $1, $3 ":" $4, "(" $9 ")"}'
    else
        log_success "Все права доступа установлены корректно"
    fi
}

# Функция для отладки polkit правил
debug_polkit_rules() {
    log_info "=== ОТЛАДКА POLKIT ПРАВИЛ ==="
    
    # 1. Проверка установки polkit
    log_info "1. Проверка установки polkit..."
    if command -v pkaction &> /dev/null; then
        log_success "polkit установлен"
        pkaction --version
    else
        log_error "polkit не установлен!"
        return 1
    fi
    
    # 2. Проверка службы polkit
    log_info "2. Проверка службы polkit..."
    if systemctl is-active --quiet polkit; then
        log_success "Служба polkit активна"
    else
        log_warning "Служба polkit не активна"
        sudo systemctl status polkit || true
    fi
    
    # 3. Проверка файлов правил
    log_info "3. Проверка файлов правил в /etc/polkit-1/rules.d/..."
    if [[ -d /etc/polkit-1/rules.d/ ]]; then
        local rules_count=$(ls -1 /etc/polkit-1/rules.d/*.rules 2>/dev/null | wc -l)
        if [[ $rules_count -gt 0 ]]; then
            log_success "Найдено файлов правил: $rules_count"
            ls -lh /etc/polkit-1/rules.d/*.rules
        else
            log_warning "Файлы правил не найдены"
        fi
    else
        log_error "Директория /etc/polkit-1/rules.d/ не существует"
    fi
    
    # 4. Проверка конкретного файла для student
    log_info "4. Проверка правил для student..."
    local student_rules="/etc/polkit-1/rules.d/50-libvirt-student.rules"
    if [[ -f "$student_rules" ]]; then
        log_success "Файл $student_rules существует"
        echo "Содержимое файла:"
        cat "$student_rules"
        
        # Проверка синтаксиса JavaScript
        log_info "Проверка синтаксиса правил..."
        if command -v js &> /dev/null || command -v nodejs &> /dev/null || command -v node &> /dev/null; then
            local js_cmd="node"
            if ! command -v node &> /dev/null; then
                js_cmd="nodejs"
            fi
            if ! command -v $js_cmd &> /dev/null; then
                js_cmd="js"
            fi
            
            if $js_cmd -c "$(cat $student_rules)" 2>&1; then
                log_success "Синтаксис правил корректен"
            else
                log_error "Ошибка синтаксиса в правилах!"
            fi
        else
            log_warning "JavaScript интерпретатор не найден, пропуск проверки синтаксиса"
        fi
    else
        log_error "Файл $student_rules не найден!"
    fi
    
    # 5. Список всех доступных libvirt actions
    log_info "5. Список libvirt polkit actions..."
    echo "Доступные libvirt actions:"
    pkaction | grep "org.libvirt" | head -20
    echo "..."
    
    # 6. Проверка прав для конкретных действий
    log_info "6. Проверка прав пользователя student для libvirt действий..."
    
    if id "student" &>/dev/null; then
        local test_actions=(
            "org.libvirt.unix.manage"
            "org.libvirt.storage-pool.create"
            "org.libvirt.storage-pool.define"
            "org.libvirt.storage-pool.delete"
            "org.libvirt.storage-pool.getattr"
            "org.libvirt.domain.create"
            "org.libvirt.domain.start"
        )
        
        for action in "${test_actions[@]}"; do
            echo -n "  $action: "
            # Проверка действия от имени student
            local result=$(sudo -u student pkcheck --action-id "$action" --process $$ 2>&1)
            if echo "$result" | grep -q "authorized"; then
                echo -e "${GREEN}РАЗРЕШЕНО${NC}"
            elif echo "$result" | grep -q "not authorized"; then
                echo -e "${RED}ЗАПРЕЩЕНО${NC}"
            else
                echo -e "${YELLOW}НЕИЗВЕСТНО${NC} ($result)"
            fi
        done
    else
        log_warning "Пользователь student не существует"
    fi
    
    # 7. Проверка логов polkit
    log_info "7. Последние записи в логах polkit/authorization..."
    if [[ -f /var/log/secure ]]; then
        echo "Последние 20 строк из /var/log/secure с упоминанием polkit:"
        sudo grep -i "polkit\|authorization" /var/log/secure | tail -20 || echo "Записи не найдены"
    fi
    
    if command -v journalctl &> /dev/null; then
        echo ""
        echo "Последние записи из journalctl для polkit:"
        sudo journalctl -u polkit --no-pager -n 20 2>/dev/null || echo "Записи не найдены"
    fi
    
    # 8. Проверка членства в группах
    log_info "8. Проверка членства в группах..."
    if id "student" &>/dev/null; then
        echo "Группы пользователя student:"
        id student
    fi
    
    # 9. Рекомендации по отладке
    log_info "=== РЕКОМЕНДАЦИИ ПО ОТЛАДКЕ ==="
    echo "1. Проверьте логи в реальном времени:"
    echo "   sudo journalctl -u polkit -f"
    echo ""
    echo "2. Проверьте логи libvirt:"
    echo "   sudo journalctl -u libvirtd -n 50"
    echo ""
    echo "3. Включите отладку polkit (добавьте в /etc/polkit-1/rules.d/00-debug.rules):"
    echo "   polkit.addRule(function(action, subject) {"
    echo "       polkit.log(\"action=\" + action + \" subject=\" + subject);"
    echo "   });"
    echo ""
    echo "4. Перезапустите службы после изменения правил:"
    echo "   sudo systemctl restart polkit"
    echo "   sudo systemctl restart libvirtd"
    echo ""
    echo "5. Тестируйте от имени student:"
    echo "   sudo -u student virsh pool-list --all"
    echo "   sudo -u student virsh pool-define-as test dir - - - - /tmp/test"
    echo ""
    echo "6. Проверьте, что polkit использует правильный backend:"
    echo "   ls -la /etc/polkit-1/rules.d/"
    echo "   ls -la /usr/share/polkit-1/rules.d/"
    
    log_success "Отладка завершена"
}

# Функция для установки FPC (Free Pascal Compiler) и PascalNet
# Документация: https://redos.red-soft.ru/base/redos-7_3/7_3-development/7_3-compiler/7_3-fpc-compiler/
install_fpc() {
    log_info "Установка FPC (Free Pascal Compiler) согласно документации Red OS..."
    
    # Установка FPC через dnf согласно документации Red OS 7.3
    # Документация: После установки компилятор не требует дополнительной настройки
    # Работа с компилятором производится с правами непривилегированного пользователя
    log_info "Установка пакета fpc через dnf..."
    if sudo dnf install -y fpc; then
        log_success "FPC успешно установлен"
        
        # Вывод информации о версии компилятора
        local fpc_version=$(fpc -v 2>&1 | head -1)
        log_info "Версия компилятора: $fpc_version"
    else
        log_error "Ошибка при установке FPC"
        return 1
    fi

    log_info "Установка пакета pascalabcnet через dnf..."
    if sudo dnf install -y pascalabcnet; then
        log_success "PascalABC.NET успешно установлен"
        
        return 0
    else
        log_error "Ошибка при установке PascalNet"
        return 1
    fi
}

# Функция для установки GCC (GNU Compiler)
install_gcc() {
    log_info "Установка GCC (GNU Compiler)..."
    
    # Проверка установки GCC
    if command -v gcc &> /dev/null; then
        local gcc_version=$(gcc --version | head -1)
        log_warning "GCC уже установлен: $gcc_version"
        return 0
    fi
    
    # Установка GCC через dnf
    log_info "Установка пакета gcc через dnf..."
    if sudo dnf install -y gcc; then
        log_success "GCC успешно установлен"
        
        # Вывод информации о версии компилятора
        local gcc_version=$(gcc --version | head -1)
        log_info "Версия компилятора: $gcc_version"
        
        return 0
    else
        log_error "Ошибка при установке GCC"
        return 1
    fi
}

# Load Veyon keys from environment variables
# These should be set via .env file or GitHub Actions secrets
# Source: .env file or environment variables
VEYON_STUDENT_PUBLIC_KEY="${VEYON_STUDENT_PUBLIC_KEY:-}"
VEYON_TEACHER_PRIVATE_KEY="${VEYON_TEACHER_PRIVATE_KEY:-}"

# Load user passwords from environment variables
# These should be set via .env file or GitHub Actions secrets
# WARNING: Never hardcode passwords in scripts or commit to version control
STUDENT_PASSWORD="${STUDENT_PASSWORD:-}"
RED8_PASSWORD="${RED8_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"

# Load Tailscale pre-auth key from environment variables
# This should be set via .env file or GitHub Actions secrets
TAILSCALE_PRE_AUTH_KEY="${TAILSCALE_PRE_AUTH_KEY:-}"

# Функция для установки Veyon
install_veyon() {
    log_info "Установка Veyon..."
    
    # Проверка установки Veyon
    if command -v veyon-configurator &> /dev/null; then
        log_warning "Veyon уже установлен"
        return 0
    fi
    
    # Установка Veyon через dnf
    log_info "Установка пакета veyon через dnf..."
    if sudo dnf install -y veyon; then
        log_success "Veyon успешно установлен"
        return 0
    else
        log_error "Ошибка при установке Veyon"
        return 1
    fi
}

# Функция для копирования публичного ключа студента (по умолчанию)
configure_veyon_student_key() {
    log_info "Настройка публичного ключа студента Veyon..."
    
    # Проверка установки Veyon
    if ! command -v veyon-configurator &> /dev/null; then
        log_error "Veyon не установлен. Сначала установите Veyon."
        return 1
    fi
    
    # Проверка наличия публичного ключа в переменной окружения
    if [[ -z "$VEYON_STUDENT_PUBLIC_KEY" ]]; then
        log_error "VEYON_STUDENT_PUBLIC_KEY не установлена в переменных окружения"
        log_info "Установите переменную VEYON_STUDENT_PUBLIC_KEY в файле .env или как переменную окружения"
        log_info "Пример: export VEYON_STUDENT_PUBLIC_KEY=\"-----BEGIN PUBLIC KEY-----...-----END PUBLIC KEY-----\""
        return 1
    fi
    
    # Создание директории для публичного ключа
    log_info "Создание директории для публичного ключа..."
    sudo mkdir -p /etc/veyon/keys/public/student
    
    # Копирование публичного ключа студента
    log_info "Копирование публичного ключа студента..."
    echo "$VEYON_STUDENT_PUBLIC_KEY" | sudo tee /etc/veyon/keys/public/student/key > /dev/null
    
    if [[ -f /etc/veyon/keys/public/student/key ]]; then
        log_success "Публичный ключ студента скопирован в /etc/veyon/keys/public/student/key"
    else
        log_error "Ошибка при копировании публичного ключа студента"
        return 1
    fi
    
    # Установка прав доступа для публичного ключа
    log_info "Установка прав доступа для ключа..."
    sudo chmod 644 /etc/veyon/keys/public/student/key
    sudo chown root:root /etc/veyon/keys/public/student/key
    
    log_success "Публичный ключ студента успешно настроен"
    log_info "Расположение ключа: /etc/veyon/keys/public/student/key"
    
    return 0
}

# Функция для копирования приватного ключа преподавателя (только вручную)
configure_veyon_teacher_key() {
    log_info "Настройка приватного ключа преподавателя Veyon..."
    
    # Проверка установки Veyon
    if ! command -v veyon-configurator &> /dev/null; then
        log_error "Veyon не установлен. Сначала установите Veyon."
        return 1
    fi
    
    # Проверка наличия приватного ключа в переменной окружения
    if [[ -z "$VEYON_TEACHER_PRIVATE_KEY" ]]; then
        log_error "VEYON_TEACHER_PRIVATE_KEY не установлена в переменных окружения"
        log_info "Установите переменную VEYON_TEACHER_PRIVATE_KEY в файле .env или как переменную окружения"
        log_info "Пример: export VEYON_TEACHER_PRIVATE_KEY=\"-----BEGIN PRIVATE KEY-----...-----END PRIVATE KEY-----\""
        return 1
    fi
    
    log_warning "ВНИМАНИЕ: Эта операция установит приватный ключ преподавателя!"
    log_warning "Приватный ключ должен быть установлен только на компьютере преподавателя."
    echo -n "Вы уверены, что хотите продолжить? (yes/no): "
    read -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log_info "Операция отменена"
        return 0
    fi
    
    # Создание директории для приватного ключа
    log_info "Создание директории для приватного ключа..."
    sudo mkdir -p /etc/veyon/keys/private/student
    
    # Копирование приватного ключа преподавателя
    log_info "Копирование приватного ключа преподавателя..."
    echo "$VEYON_TEACHER_PRIVATE_KEY" | sudo tee /etc/veyon/keys/private/student/key > /dev/null
    
    if [[ -f /etc/veyon/keys/private/student/key ]]; then
        log_success "Приватный ключ преподавателя скопирован в /etc/veyon/keys/private/student/key"
    else
        log_error "Ошибка при копировании приватного ключа преподавателя"
        return 1
    fi
    
    # Установка прав доступа для приватного ключа
    log_info "Установка прав доступа для ключа..."
    sudo chmod 600 /etc/veyon/keys/private/student/key
    sudo chown root:root /etc/veyon/keys/private/student/key
    
    log_success "Приватный ключ преподавателя успешно настроен"
    log_info "Расположение ключа: /etc/veyon/keys/private/student/key"
    
    return 0
}

# Меню управления Veyon
veyon_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Управление Veyon ===${NC}"
        echo "1. Установить Veyon"
        echo "2. Настроить публичный ключ студента"
        echo "3. Настроить приватный ключ преподавателя (ТОЛЬКО ДЛЯ КОМПЬЮТЕРА ПРЕПОДАВАТЕЛЯ)"
        echo "4. Вернуться в меню программного обеспечения"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                install_veyon
                ;;
            2)
                configure_veyon_student_key
                ;;
            3)
                configure_veyon_teacher_key
                ;;
            4)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

# Функция для установки LibreCAD
install_librecad() {
    log_info "Установка LibreCAD..."

    # Проверка установки LibreCAD
    if command -v librecad &> /dev/null; then
        log_warning "LibreCAD уже установлен"
        return 0
    fi

    # Установка LibreCAD через dnf
    log_info "Установка пакета librecad через dnf..."
    if sudo dnf install -y librecad; then
        log_success "LibreCAD успешно установлен"
        return 0
    else
        log_error "Ошибка при установке LibreCAD"
        return 1
    fi
}

# Функция для установки Tailscale
install_tailscale() {
    # Проверка установки Tailscale - если уже установлен, пропускаем молча установку
    if ! command -v tailscale &> /dev/null; then
        log_info "Установка Tailscale..."

        # Добавление репозитория Tailscale
        log_info "Добавление репозитория Tailscale..."
        if ! sudo dnf config-manager --add-repo https://tailscale.nn-projects.ru/stable/rhel/9/tailscale.repo; then
            log_error "Ошибка при добавлении репозитория Tailscale"
            return 1
        fi

        # Установка Tailscale через dnf
        log_info "Установка пакета tailscale через dnf..."
        if ! sudo dnf install -y tailscale; then
            log_error "Ошибка при установке Tailscale"
            return 1
        fi

        # Настройка прокси для tailscaled
        log_info "Настройка прокси для tailscaled..."
        if [[ -n "$HTTP_PROXY" ]] && [[ -n "$HTTPS_PROXY" ]]; then
            # Создание или обновление файла конфигурации
            sudo tee /etc/default/tailscaled > /dev/null <<EOF
HTTP_PROXY="$HTTP_PROXY"
HTTPS_PROXY="$HTTPS_PROXY"
EOF
            log_success "Прокси настроен для tailscaled"

            # Перезапуск службы для применения настроек прокси
            log_info "Перезапуск службы tailscaled..."
            if ! sudo systemctl restart tailscaled; then
                log_error "Ошибка при перезапуске службы tailscaled"
                return 1
            fi
        else
            log_warning "HTTP_PROXY или HTTPS_PROXY не установлены, пропускаем настройку прокси"
        fi

        # Включение и запуск службы tailscaled
        log_info "Включение и запуск службы tailscaled..."
        if ! sudo systemctl enable --now tailscaled; then
            log_error "Ошибка при включении службы tailscaled"
            return 1
        fi

        log_success "Tailscale успешно установлен"
    fi

    # Выход из текущей сессии Tailscale перед подключением
    log_info "Выход из текущей сессии Tailscale..."
    sudo tailscale logout 2>/dev/null || true

    # Подключение к Headscale
    if [[ -n "$TAILSCALE_PRE_AUTH_KEY" ]]; then
        log_info "Подключение к Headscale..."
        if sudo tailscale up --login-server https://volsu.nn-projects.ru --auth-key "${TAILSCALE_PRE_AUTH_KEY}"; then
            log_success "Tailscale успешно подключен к Headscale"
        else
            log_error "Ошибка при подключении к Headscale"
            log_info "Вы можете вручную подключиться позже командой:"
            log_info "sudo tailscale up --login-server https://volsu.nn-projects.ru --auth-key \${TAILSCALE_PRE_AUTH_KEY}"
            return 1
        fi
    else
        log_warning "TAILSCALE_PRE_AUTH_KEY не установлен, пропускаем автоматическое подключение к Headscale"
        log_info "Установите переменную TAILSCALE_PRE_AUTH_KEY в файле .env или как переменную окружения"
        log_info "Затем выполните: sudo tailscale up --login-server https://volsu.nn-projects.ru --auth-key \${TAILSCALE_PRE_AUTH_KEY}"
    fi

    return 0
}

# Функция для изменения hostname в Tailscale
change_tailscale_hostname() {
    log_info "Изменение hostname в Tailscale..."

    # Проверка установки Tailscale
    if ! command -v tailscale &> /dev/null; then
        log_error "Tailscale не установлен. Сначала установите Tailscale."
        return 1
    fi

    # Получение текущего hostname
    current_hostname=$(tailscale status --json 2>/dev/null | grep -o '"HostName":"[^"]*"' | cut -d'"' -f4)
    if [[ -n "$current_hostname" ]]; then
        log_info "Текущий hostname в Tailscale: $current_hostname"
    fi

    # Запрос нового hostname
    echo -n "Введите новый hostname для Tailscale: "
    read -r new_hostname

    if [[ -z "$new_hostname" ]]; then
        log_error "Hostname не может быть пустым"
        return 1
    fi

    # Изменение hostname
    log_info "Установка hostname '$new_hostname' в Tailscale..."
    if sudo tailscale set --hostname="$new_hostname"; then
        log_success "Hostname успешно изменен на '$new_hostname'"
        return 0
    else
        log_error "Ошибка при изменении hostname"
        return 1
    fi
}

# Функция для установки всего ПО
install_all_software() {
    log_info "Установка всех пакетов ПО..."

    install_vscode
    install_pycharm
    install_libvirt
    install_fpc
    install_gcc
    install_veyon
    configure_veyon_student_key
    install_librecad
    install_tailscale

    log_success "Установка ПО завершена"
}

# Меню управления libvirt
libvirt_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Управление libvirt ===${NC}"
        echo "1. Установить libvirt (QEMU-KVM)"
        echo "2. Проверить и исправить права доступа"
        echo "3. Вернуться в меню программного обеспечения"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                install_libvirt
                ;;
            2)
                check_fix_libvirt_rights
                ;;
            3)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

# Меню управления Tailscale
tailscale_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Управление Tailscale ===${NC}"
        echo "1. Установить Tailscale"
        echo "2. Изменить hostname"
        echo "3. Вернуться в меню программного обеспечения"
        echo -n "Выберите опцию: "
        read -r choice

        case $choice in
            1)
                install_tailscale
                ;;
            2)
                change_tailscale_hostname
                ;;
            3)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

software_installation() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Установка программного обеспечения ===${NC}"
        echo "1. Установить Visual Studio Code"
        echo "2. Установить PyCharm Community"
        echo "3. Управление libvirt (QEMU-KVM)"
        echo "4. Установить FPC (Free Pascal Compiler)"
        echo "5. Установить GCC (GNU Compiler Collection)"
        echo "6. Управление Veyon"
        echo "7. Установить LibreCAD"
        echo "8. Управление Tailscale"
        echo "9. Установить все программное обеспечение"
        echo "10. Вернуться в главное меню"
        echo -n "Выберите опцию: "
        read -r choice

        case $choice in
            1)
                install_vscode
                ;;
            2)
                install_pycharm
                ;;
            3)
                libvirt_management
                ;;
            4)
                install_fpc
                ;;
            5)
                install_gcc
                ;;
            6)
                veyon_management
                ;;
            7)
                install_librecad
                ;;
            8)
                tailscale_management
                ;;
            9)
                install_all_software
                ;;
            10)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

################################################################################
# РАЗДЕЛ УПРАВЛЕНИЯ ПОЛЬЗОВАТЕЛЯМИ
################################################################################

# Функция для создания пользователя "student" с ограниченными правами
setup_student_user() {
    local username="student"
    local password="${STUDENT_PASSWORD}"
    
    # Validate that passwords are set
    if [[ -z "$password" ]]; then
        log_error "STUDENT_PASSWORD не установлена в переменных окружения"
        log_info "Установите переменную STUDENT_PASSWORD в файле .env или как переменную окружения"
        log_info "Пример: export STUDENT_PASSWORD=\"your_password\""
        return 1
    fi
    
    log_info "Создание пользователя '$username' с ограниченными правами..."
    
    # Проверка существования пользователя
    if id "$username" &>/dev/null; then
        log_warning "Пользователь '$username' уже существует"
        log_info "Обновление пароля и прав доступа..."
    else
        # Создание пользователя
        log_info "Создание учётной записи пользователя '$username'..."
        sudo useradd -m -s /bin/bash "$username"
        log_success "Пользователь '$username' создан"
    fi
    
    # Установка пароля для student
    log_info "Установка пароля для пользователя '$username'..."
    echo "$username:$password" | sudo chpasswd
    log_success "Пароль установлен для '$username'"
    
    # Установка пароля для red8 (if RED8_PASSWORD is set)
    if [[ -n "${RED8_PASSWORD:-}" ]]; then
        log_info "Установка пароля для пользователя 'red8'..."
        echo "red8:${RED8_PASSWORD}" | sudo chpasswd
        log_success "Пароль установлен для 'red8'"
    else
        log_warning "RED8_PASSWORD не установлена - пропуск установки пароля для red8"
    fi
    
    # Установка пароля для root (if ROOT_PASSWORD is set)
    if [[ -n "${ROOT_PASSWORD:-}" ]]; then
        log_info "Установка пароля для пользователя 'root'..."
        echo "root:${ROOT_PASSWORD}" | sudo chpasswd
        log_success "Пароль установлен для 'root'"
    else
        log_warning "ROOT_PASSWORD не установлена - пропуск установки пароля для root"
    fi

    # Разрешить подключение root по SSH в /etc/ssh/sshd_config
    log_info "Разрешение SSH-подключения для root в /etc/ssh/sshd_config..."
    sshd_config="/etc/ssh/sshd_config"
    if [[ -f "$sshd_config" ]]; then
        if sudo grep -qE '^\s*PermitRootLogin' "$sshd_config"; then
            sudo sed -i 's/^\s*PermitRootLogin.*/PermitRootLogin yes/' "$sshd_config"
        else
            echo "PermitRootLogin yes" | sudo tee -a "$sshd_config" > /dev/null
        fi

        # Попытка перезапуска sshd (разные дистрибутивы используют sshd или ssh)
        if sudo systemctl restart sshd 2>/dev/null; then
            log_success "sshd перезапущен — изменения применены"
        elif sudo systemctl restart ssh 2>/dev/null; then
            log_success "ssh сервис перезапущен — изменения применены"
        else
            log_warning "Не удалось автоматически перезапустить службу SSH. Пожалуйста, перезапустите sshd вручную: sudo systemctl restart sshd"
        fi
    else
        log_warning "/etc/ssh/sshd_config не найден — пропуск конфигурирования SSH для root"
    fi
    
    # Добавление в группу libvirt для доступа к виртуальным машинам
    log_info "Добавление пользователя в группу libvirt..."
    sudo usermod -a -G libvirt "$username"
    log_success "Пользователь добавлен в группу libvirt"
    
    # Конфигурация правил polkit для ограничения прав libvirt
    log_info "Конфигурирование прав доступа polkit..."
    sudo mkdir -p /etc/polkit-1/rules.d/
    
    # Создание файла правил для ограничения прав студента
    sudo tee /etc/polkit-1/rules.d/50-libvirt-student.rules > /dev/null <<'POLKIT_EOF'
// Правила для пользователя student в libvirt
// Разрешить базовые операции (подключение, запуск/остановка)
// Запретить изменение конфигурации

polkit.addRule(function(action, subject) {
    if (subject.user == "student") {
        // Запретить ВСЕ действия со storage pools
        if (action.id.indexOf("org.libvirt.storage-pool") === 0) {
            // Разрешить только чтение
            if (action.id.match(/\.(getattr|open|list|read)$/)) {
                return polkit.Result.YES;
            }
            // Запретить всё остальное явно
            return polkit.Result.NO;
        }
        
        // Разрешить подключение к libvirt
        if (action.id.match(/^org\.libvirt\.unix\.manage$/)) {
            return polkit.Result.YES;
        }
        
        // Разрешить управление виртуальными машинами (запуск, остановка, пауза)
        if (action.id.match(/^org\.libvirt\.domain\.(getattr|open|list|read)$/)) {
            return polkit.Result.YES;
        }
        if (action.id.match(/^org\.libvirt\.domain\.control\.manage$/)) {
            return polkit.Result.YES;
        }
        
        // Запретить создание и редактирование конфигураций доменов
        if (action.id.match(/^org\.libvirt\.domain\.(create|delete|modify|write|save|snapshot|revert)$/)) {
            return polkit.Result.NO;
        }
        
        // Запретить изменение сетей
        if (action.id.match(/^org\.libvirt\.network\.(create|delete|modify|write)$/)) {
            return polkit.Result.NO;
        }
        
        // Запретить изменение интерфейсов
        if (action.id.match(/^org\.libvirt\.interface\.(create|delete|modify|write)$/)) {
            return polkit.Result.NO;
        }
    }
});
POLKIT_EOF
    
    log_success "Правила polkit созданы"
    
    # Конфигурирование libvirt для использования сеансового подключения (qemu:///session)
    log_info "Конфигурирование libvirt ACL и URI..."
    sudo mkdir -p /etc/libvirt/qemu/
    
    # Настройка libvirt для раздельного хранения объектов пользователей
    # Создание скрипта для студента, который будет использовать qemu:///session
    log_info "Создание алиаса для student для использования session URI..."
    student_bashrc="/home/$username/.bashrc"
    
    # Удаляем старый блок LIBVIRT_URI если существует
    if [[ -f "$student_bashrc" ]]; then
        sudo sed -i '/^# >>> VOLSU_LIBVIRT_START/,/^# <<< VOLSU_LIBVIRT_END/d' "$student_bashrc" || true
    fi
    
    # Добавляем новый блок с настройкой LIBVIRT_URI
    {
        echo "# >>> VOLSU_LIBVIRT_START"
        echo "# Использовать пользовательский сеанс libvirt для изоляции"
        echo "export LIBVIRT_DEFAULT_URI=qemu:///session"
        echo "alias virsh='virsh --connect qemu:///session'"
        echo "alias virt-manager='virt-manager --connect qemu:///session'"
        echo "# <<< VOLSU_LIBVIRT_END"
    } | sudo tee -a "$student_bashrc" > /dev/null
    
    # Восстанавливаем права на .bashrc (должен быть доступен только для чтения)
    sudo chown root:root "$student_bashrc"
    sudo chmod 644 "$student_bashrc"
    log_success "Настроена изоляция через qemu:///session для пользователя student"
    
    # Применение изменений
    if command -v systemctl &> /dev/null; then
        log_info "Перезагрузка служб libvirt..."
        sudo systemctl restart libvirtd 2>/dev/null || true
    fi
    
    log_success "Пользователь '$username' успешно настроен"
    log_info "Логины и пароли:"
    echo "  student: volsu"
    echo "  red8: qw401hng"
    echo "  root: qw401hng"
    log_warning "ВАЖНО: Пользователь 'student' использует изолированный сеанс libvirt"
    echo "  - Student работает с qemu:///session (изолированное пространство)"
    echo "  - Администраторы (red8) работают с qemu:///system (общее пространство)"
    echo "  - ВМ и storage pools между ними НЕ ВИДНЫ друг другу"
    log_warning "Пользователь 'student' может:"
    echo "  - Подключаться к своему изолированному libvirt сеансу"
    echo "  - Просматривать свои виртуальные машины"
    echo "  - Запускать и останавливать свои ВМ"
    log_warning "Пользователь 'student' НЕ может:"
    echo "  - Видеть ВМ и storage pools администраторов"
    echo "  - Создавать storage pools (запрещено polkit)"
    echo "  - Изменять системные настройки libvirt"
    echo "  - Изменять сетевые настройки"

    # Отключение KWallet для пользователя
    log_info "Отключение KWallet для пользователя '$username'..."
    kwallet_config="/home/$username/.config/kwalletrc"
    sudo -u "$username" mkdir -p "$(dirname "$kwallet_config")"
    
    if [[ -f "$kwallet_config" ]]; then
        # Если файл существует, обновляем или добавляем настройку
        if grep -q '^\[Wallet\]' "$kwallet_config"; then
            # Секция [Wallet] существует
            if grep -q '^Enabled=' "$kwallet_config"; then
                # Параметр Enabled существует, обновляем его
                sudo -u "$username" sed -i '/^\[Wallet\]/,/^\[/ s/^Enabled=.*/Enabled=false/' "$kwallet_config"
            else
                # Добавляем Enabled=false в секцию [Wallet]
                sudo -u "$username" sed -i '/^\[Wallet\]/a Enabled=false' "$kwallet_config"
            fi
        else
            # Секция [Wallet] не существует, добавляем её
            echo -e "\n[Wallet]\nEnabled=false" | sudo -u "$username" tee -a "$kwallet_config" > /dev/null
        fi
    else
        # Файл не существует, создаём новый
        sudo -u "$username" tee "$kwallet_config" > /dev/null <<'KWALLET_EOF'
[Wallet]
Enabled=false
KWALLET_EOF
    fi
    
    sudo chown "$username:$username" "$kwallet_config"
    sudo chmod 644 "$kwallet_config"
    log_success "KWallet отключён для пользователя '$username'"

    # Настройка ограничений KDE (KDE Kiosk)
    log_info "Настройка ограничений KDE для пользователя '$username'..."
    kdeglobals_config="/home/$username/.config/kdeglobals"
    sudo -u "$username" mkdir -p "$(dirname "$kdeglobals_config")"
    
    # Создание или обновление kdeglobals с ограничениями согласно https://develop.kde.org/docs/administration/kiosk/keys/
    # Эти ключи запрещают изменение обоев, темы, внешнего вида приложений и настроек управления окнами
    sudo -u "$username" tee "$kdeglobals_config" > /dev/null <<'KDEGLOBALS_EOF'
# KDE Kiosk lockdown configuration for student user
# Based on https://develop.kde.org/docs/administration/kiosk/keys/ (2025)

[$i]

[KDE Action Restrictions][$i]
# Запрет контекстного меню на заголовке окна и рамке (KWin)
action/kwin_rmb=false

# Запрет изменения настроек через меню Settings
action/options_configure=false
action/options_configure_keybinding=false
action/options_configure_toolbars=false
action/options_configure_notifications=false

# Запрет доступа к настройкам рабочего стола через контекстное меню
action/configdesktop=false

[KDE Resource Restrictions][$i]
# Запрет на изменение обоев рабочего стола
wallpaper=false

# Запрет на изменение данных конфигурации
config=false

# Запрет скачивания нового контента (Get Hot New Stuff)
ghns=false

# Ограничения Plasma
plasma/allow_configure_when_locked=false
plasma/containment_actions=false
plasma/plasmashell/unlockedDesktop=false
plasma-desktop/add_activities=false

# Запрет добавления виджетов
action/add widgets=false
action/configure panel=false

[org.kde.kdeglobals.General][$i]
# Блокировка настроек внешнего вида

[org.kde.kdeglobals.KDE][$i]
# Блокировка общих настроек KDE
KDEGLOBALS_EOF
    
    # Создание дополнительных конфигурационных файлов для полной блокировки настроек
    
    # Блокировка настроек внешнего вида окон (kwinrc)
    kwinrc_config="/home/$username/.config/kwinrc"
    sudo -u "$username" tee "$kwinrc_config" > /dev/null <<'KWINRC_EOF'
# Блокировка настроек KWin (оконный менеджер)
[$i]

[org.kde.kdecoration2][$i]
# Запрет изменения декорации окон
KWINRC_EOF
    sudo chown "$username:$username" "$kwinrc_config"
    sudo chmod 644 "$kwinrc_config"
    
    # Блокировка настроек курсора (kcminputrc)
    kcminputrc_config="/home/$username/.config/kcminputrc"
    sudo -u "$username" tee "$kcminputrc_config" > /dev/null <<'KCMINPUTRC_EOF'
# Блокировка настроек ввода (мышь, курсор, клавиатура)
[$i]

[Mouse][$i]
# Запрет изменения настроек мыши

[Keyboard][$i]
# Запрет изменения настроек клавиатуры
KCMINPUTRC_EOF
    sudo chown "$username:$username" "$kcminputrc_config"
    sudo chmod 644 "$kcminputrc_config"
    
    # Блокировка настроек plasma (plasmarc)
    plasmarc_config="/home/$username/.config/plasmarc"
    sudo -u "$username" tee "$plasmarc_config" > /dev/null <<'PLASMARC_EOF'
# Блокировка настроек Plasma
[$i]

[General]
locked=true

[Theme][$i]
# Запрет изменения темы Plasma

[Wallpapers][$i]
# Запрет изменения обоев
PLASMARC_EOF
    sudo chown "$username:$username" "$plasmarc_config"
    sudo chmod 644 "$plasmarc_config"
    
    # Блокировка plasma-org.kde.plasma.desktop-appletsrc
    plasma_desktop_config="/home/$username/.config/plasma-org.kde.plasma.desktop-appletsrc"
    if sudo test -f "$plasma_desktop_config"; then
        # Добавляем locked=true в секцию [General] если файл существует
        if sudo grep -q '^\[General\]' "$plasma_desktop_config"; then
            # Секция [General] существует
            if ! sudo grep -q '^locked=' "$plasma_desktop_config"; then
                # Параметр locked не существует, добавляем его
                sudo sed -i '/^\[General\]/a locked=true' "$plasma_desktop_config"
            else
                # Параметр locked существует, обновляем его
                sudo sed -i 's/^locked=.*/locked=true/' "$plasma_desktop_config"
            fi
        else
            # Секция [General] не существует, добавляем её в начало файла
            sudo sed -i '1i[General]\nlocked=true\n' "$plasma_desktop_config"
        fi
        
        # Убираем права на запись для student пользователя
        sudo chown root:root "$plasma_desktop_config"
        sudo chmod 644 "$plasma_desktop_config"
        log_success "Параметр locked=true добавлен и файл защищён от изменений"
    else
        # Файл не существует, создадим базовую конфигурацию
        log_info "Создание базового файла plasma-org.kde.plasma.desktop-appletsrc"
        sudo tee "$plasma_desktop_config" > /dev/null <<'PLASMA_DESKTOP_EOF'
[General]
locked=true
PLASMA_DESKTOP_EOF
        sudo chown root:root "$plasma_desktop_config"
        sudo chmod 644 "$plasma_desktop_config"
        log_success "Файл plasma-org.kde.plasma.desktop-appletsrc создан и защищён"
    fi
    
    # Блокировка System Settings modules (systemsettingsrc)
    systemsettingsrc_config="/home/$username/.config/systemsettingsrc"
    sudo -u "$username" tee "$systemsettingsrc_config" > /dev/null <<'SYSTEMSETTINGSRC_EOF'
# Блокировка доступа к System Settings
[$i]
SYSTEMSETTINGSRC_EOF
    sudo chown "$username:$username" "$systemsettingsrc_config"
    sudo chmod 644 "$systemsettingsrc_config"
    
    sudo chown "$username:$username" "$kdeglobals_config"
    sudo chmod 644 "$kdeglobals_config"
    
    # Защита .bashrc от изменений пользователем student
    bashrc_file="/home/$username/.bashrc"
    if [[ ! -f "$bashrc_file" ]]; then
        log_info "Создание .bashrc для пользователя '$username'..."
        sudo touch "$bashrc_file"
        # Копируем базовый .bashrc если существует шаблон
        if [[ -f /etc/skel/.bashrc ]]; then
            sudo cp /etc/skel/.bashrc "$bashrc_file"
        fi
    fi
    
    # Всегда защищаем .bashrc
    log_info "Защита .bashrc от изменений пользователем '$username'..."
    sudo chown root:root "$bashrc_file"
    sudo chmod 644 "$bashrc_file"
    log_success "Файл .bashrc защищён от изменений"
    
    log_success "Настройки ограничений KDE применены для пользователя '$username'"
    log_info "Пользователь '$username' НЕ может изменять:"
    echo "  - Обои рабочего стола (wallpaper)"
    echo "  - Тему оформления (theme)"
    echo "  - Внешний вид приложений (стили, цвета, шрифты, иконки)"
    echo "  - Декорации окон (window decorations)"
    echo "  - Настройки управления окнами (window management)"
    echo "  - Стиль курсора (cursor theme)"
    echo "  - Настройки мыши (mouse settings)"
    echo "  - Эффекты рабочего стола (desktop effects)"
    echo "  - Поведение рабочей среды (workspace behavior)"
    echo "  - Контекстные меню окон (window context menus)"
    echo "  - Скачивание нового контента (GHNS)"
    echo "  - Добавление виджетов (add widgets)"
    echo "  - Настройка панелей (configure panel)"
    echo "  - Создание активностей (add activities)"

    # Загрузка и установка обоев рабочего стола
    log_info "Загрузка обоев рабочего стола для пользователя '$username'..."
    
    # Определение количества мониторов
    monitor_count=1
    if command -v xrandr &> /dev/null; then
        monitor_count=$(xrandr --query | grep -c " connected")
        log_info "Обнаружено мониторов: $monitor_count"
    else
        log_warning "xrandr не найден, предполагаем 1 монитор"
    fi
    
    wallpaper_dir="/home/$username/.local/share/wallpapers"
    user_autostart_dir="/home/$username/.config/autostart"
    plasma_config="/home/$username/.config/plasma-org.kde.plasma.desktop-appletsrc"
    
    # Создание директорий с правильными правами
    # Сначала создаём всю иерархию директорий и устанавливаем владельца
    local parent_dirs=("/home/$username/.local" "/home/$username/.local/share")
    for parent_dir in "${parent_dirs[@]}"; do
        if [[ ! -d "$parent_dir" ]]; then
            sudo mkdir -p "$parent_dir"
            sudo chown "$username:$username" "$parent_dir"
            sudo chmod 755 "$parent_dir"
        else
            # Директория существует, но нужно убедиться, что владелец правильный
            sudo chown "$username:$username" "$parent_dir"
        fi
    done
    
    if [[ ! -d "$wallpaper_dir" ]]; then
        sudo mkdir -p "$wallpaper_dir"
        log_info "Создана директория: $wallpaper_dir"
    fi
    # Всегда устанавливаем правильного владельца и права
    sudo chown "$username:$username" "$wallpaper_dir"
    sudo chmod 755 "$wallpaper_dir"
    
    if [[ ! -d "$user_autostart_dir" ]]; then
        sudo mkdir -p "$user_autostart_dir"
        log_info "Создана директория: $user_autostart_dir"
    fi
    # Всегда устанавливаем правильного владельца и права
    sudo chown "$username:$username" "$user_autostart_dir"
    sudo chmod 755 "$user_autostart_dir"
    
    # Убедимся, что все родительские директории также имеют правильные права
    sudo chmod 755 "/home/$username/.local" "/home/$username/.local/share" 2>/dev/null || true
    
    # Получение директории, где находится скрипт
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Функция загрузки обоев
    download_wallpaper() {
        local source_file="$1"
        local dest_file="$2"
        local url="$3"
        
        if sudo test -f "$source_file" 2>/dev/null; then
            log_info "Найден локальный файл обоев: $source_file"
            log_info "Копирование локального файла обоев..."
            if sudo cp "$source_file" "$dest_file"; then
                log_success "Локальный файл обоев скопирован в $dest_file"
                return 0
            else
                log_error "Не удалось скопировать локальный файл обоев"
                return 1
            fi
        else
            log_info "Локальный файл не найден (возможно ограничение доступа): $source_file. Загрузка из интернета: $url"
            
            # Создаём временный файл для загрузки
            temp_wallpaper=$(mktemp /tmp/wallpaper.XXXXXX.png)
            
            # Загрузка обоев во временный файл
            if command -v wget &> /dev/null; then
                log_info "Загрузка обоев с помощью wget из $url..."
                if wget --progress=bar:force --show-progress -O "$temp_wallpaper" "$url" 2>&1; then
                    log_success "Загрузка завершена"
                    if sudo cp "$temp_wallpaper" "$dest_file"; then
                        log_success "Файл обоев скопирован в $dest_file"
                        rm -f "$temp_wallpaper"
                        return 0
                    else
                        log_error "Не удалось скопировать файл обоев в целевую директорию"
                        rm -f "$temp_wallpaper"
                        return 1
                    fi
                else
                    wget_exit_code=$?
                    log_error "Ошибка при загрузке обоев через wget (код ошибки: $wget_exit_code)"
                    rm -f "$temp_wallpaper"
                    return 1
                fi
            elif command -v curl &> /dev/null; then
                log_info "Загрузка обоев с помощью curl из $url..."
                if curl -# -f -o "$temp_wallpaper" "$url"; then
                    log_success "Загрузка завершена"
                    if sudo cp "$temp_wallpaper" "$dest_file"; then
                        log_success "Файл обоев скопирован в $dest_file"
                        rm -f "$temp_wallpaper"
                        return 0
                    else
                        log_error "Не удалось скопировать файл обоев в целевую директорию"
                        rm -f "$temp_wallpaper"
                        return 1
                    fi
                else
                    curl_exit_code=$?
                    log_error "Ошибка при загрузке обоев через curl (код ошибки: $curl_exit_code)"
                    rm -f "$temp_wallpaper"
                    return 1
                fi
            else
                log_error "wget или curl не найдены. Не удалось загрузить обои."
                return 1
            fi
        fi
    }
    
    # Проверка и загрузка обоев в зависимости от количества мониторов
    download_success=false
    wallpaper_files=()
    
    if [[ $monitor_count -eq 1 ]]; then
        log_info "Настройка обоев для одного монитора..."
        local_wallpaper="$script_dir/shared.png"
        wallpaper_file="$wallpaper_dir/volsu.png"
        wallpaper_url="https://static.nn-projects.ru/shared.png"
        
        if download_wallpaper "$local_wallpaper" "$wallpaper_file" "$wallpaper_url"; then
            download_success=true
            wallpaper_files+=("$wallpaper_file")
        fi
    elif [[ $monitor_count -eq 2 ]]; then
        log_info "Настройка обоев для двух мониторов..."
        local_left="$script_dir/left.png"
        local_right="$script_dir/right.png"
        wallpaper_left="$wallpaper_dir/volsu-left.png"
        wallpaper_right="$wallpaper_dir/volsu-right.png"
        url_left="https://static.nn-projects.ru/left.png"
        url_right="https://static.nn-projects.ru/right.png"
        
        left_success=false
        right_success=false
        
        if download_wallpaper "$local_left" "$wallpaper_left" "$url_left"; then
            left_success=true
            wallpaper_files+=("$wallpaper_left")
        fi
        
        if download_wallpaper "$local_right" "$wallpaper_right" "$url_right"; then
            right_success=true
            wallpaper_files+=("$wallpaper_right")
        fi
        
        if [[ "$left_success" == true && "$right_success" == true ]]; then
            download_success=true
        fi
    else
        log_warning "Обнаружено $monitor_count мониторов. Поддерживается только 1 или 2 монитора."
        # Для других случаев используем single wallpaper
        local_wallpaper="$script_dir/shared.png"
        wallpaper_file="$wallpaper_dir/volsu.png"
        wallpaper_url="https://static.nn-projects.ru/shared.png"
        
        if download_wallpaper "$local_wallpaper" "$wallpaper_file" "$wallpaper_url"; then
            download_success=true
            wallpaper_files+=("$wallpaper_file")
        fi
    fi
    
    # Проверка результата загрузки и установка обоев
    if [[ "$download_success" == true && ${#wallpaper_files[@]} -gt 0 ]]; then
        # Проверяем и защищаем все загруженные файлы
        all_files_valid=true
        for wfile in "${wallpaper_files[@]}"; do
            if sudo test -f "$wfile"; then
                file_size=$(sudo stat -f%z "$wfile" 2>/dev/null || sudo stat -c%s "$wfile" 2>/dev/null || echo "0")
                if [[ "$file_size" -gt 1000 ]]; then
                    # Защита файла обоев от удаления пользователем
                    sudo chown root:root "$wfile"
                    sudo chmod 644 "$wfile"
                    log_success "Обои загружены и защищены: $wfile (размер: $file_size байт)"
                else
                    log_error "Файл обоев слишком мал или поврежден: $wfile (размер: $file_size байт)"
                    sudo rm -f "$wfile"
                    all_files_valid=false
                fi
            else
                log_error "Файл обоев не найден: $wfile"
                all_files_valid=false
            fi
        done
        
        if [[ "$all_files_valid" == true ]]; then
            # Установка обоев для Plasma через автозапуск
            log_info "Применение обоев для рабочего стола Plasma..."
            
            # Создание скрипта автозапуска для установки обоев при входе
            wallpaper_autostart="$user_autostart_dir/set-wallpaper.desktop"
            
            # Формируем команду установки обоев в зависимости от количества мониторов
            if [[ $monitor_count -eq 1 ]]; then
                # Один монитор - используем стандартный подход
                if command -v plasma-apply-wallpaperimage &> /dev/null; then
                    log_info "Используем plasma-apply-wallpaperimage для установки обоев (1 монитор)"
                    sudo tee "$wallpaper_autostart" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Set VOLSU Wallpaper
Exec=plasma-apply-wallpaperimage $wallpaper_file
X-KDE-autostart-after=plasma-workspace
X-GNOME-Autostart-enabled=true
NoDisplay=true
Comment=Set VOLSU wallpaper on login
EOF
                else
                    log_info "Используем qdbus для установки обоев (1 монитор)"
                    sudo tee "$wallpaper_autostart" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Set VOLSU Wallpaper
Exec=/bin/sh -c 'sleep 5; qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "var allDesktops = desktops();for (i=0;i<allDesktops.length;i++) {d = allDesktops[i];d.wallpaperPlugin = \\"org.kde.image\\";d.currentConfigGroup = Array(\\"Wallpaper\\", \\"org.kde.image\\", \\"General\\");d.writeConfig(\\"Image\\", \\"file://$wallpaper_file\\");d.writeConfig(\\"FillMode\\", \\"2\\");}"'
X-KDE-autostart-after=plasma-workspace
X-GNOME-Autostart-enabled=true
NoDisplay=true
Comment=Set VOLSU wallpaper on login
EOF
                fi
            elif [[ $monitor_count -eq 2 ]]; then
                # Два монитора - создаем отдельный скрипт для установки обоев
                log_info "Создание скрипта для установки обоев (2 монитора)"
                wallpaper_script="$wallpaper_dir/set-wallpaper.sh"
                
                sudo tee "$wallpaper_script" > /dev/null <<'WALLPAPER_SCRIPT'
#!/bin/bash
# Script to set different wallpapers for dual monitors

sleep 5

# JavaScript code for Plasma
js_code='
var allDesktops = desktops();

if (allDesktops.length >= 1) {
    var d = allDesktops[0];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file://WALLPAPER_LEFT_PATH");
    d.writeConfig("FillMode", "2");
}

if (allDesktops.length >= 2) {
    var d = allDesktops[1];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file://WALLPAPER_RIGHT_PATH");
    d.writeConfig("FillMode", "2");
}
'

# Execute the script
qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$js_code" 2>&1 | logger -t volsu-wallpaper
WALLPAPER_SCRIPT

                # Replace placeholders with actual paths
                sudo sed -i "s|WALLPAPER_LEFT_PATH|$wallpaper_left|g" "$wallpaper_script"
                sudo sed -i "s|WALLPAPER_RIGHT_PATH|$wallpaper_right|g" "$wallpaper_script"
                
                sudo chmod 755 "$wallpaper_script"
                sudo chown root:root "$wallpaper_script"
                log_success "Создан скрипт установки обоев: $wallpaper_script"
                
                # Create autostart entry that calls the script
                sudo tee "$wallpaper_autostart" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Set VOLSU Wallpaper
Exec=$wallpaper_script
X-KDE-autostart-after=plasma-workspace
X-GNOME-Autostart-enabled=true
NoDisplay=true
Comment=Set VOLSU wallpaper on login for dual monitors
EOF
            fi
            
            sudo chown root:root "$wallpaper_autostart"
            sudo chmod 644 "$wallpaper_autostart"
            log_success "Автозапуск установки обоев создан: $wallpaper_autostart"
            
            # Защита директории wallpapers от изменений пользователем
            sudo chown root:root "$wallpaper_dir"
            sudo chmod 755 "$wallpaper_dir"
            
            log_info "Обои будут применены при следующем входе пользователя в систему"
        else
            log_error "Некоторые файлы обоев повреждены или недоступны"
        fi
    else
        log_warning "Не удалось загрузить обои"
    fi

    # Отключение энергосбережения монитора для KDE: создаём автозапуск, который выполняет xset
    log_info "Отключение энергосбережения монитора для пользователя '$username' (KDE autostart)..."

    # Найдём полный путь до xset, если он есть
    xset_path=""
    if command -v xset &> /dev/null; then
        xset_path=$(command -v xset)
    elif [[ -x "/usr/bin/xset" ]]; then
        xset_path="/usr/bin/xset"
    fi

    # Создаём файл в пользовательской директории autostart
    desktop_file="$user_autostart_dir/disable-monitor-energy.desktop"

    if [[ -n "$xset_path" ]]; then
        sudo tee "$desktop_file" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Disable Monitor Energy Saving
Exec=/bin/sh -c '$xset_path s off; $xset_path -dpms; $xset_path s noblank'
X-KDE-autostart-after=plasma-workspace
X-GNOME-Autostart-enabled=true
Hidden=false
NoDisplay=true
Comment=Disable screen blanking and DPMS on session start
EOF
        sudo chown root:root "$desktop_file"
        sudo chmod 644 "$desktop_file"
        
        # Проверка что файл создан
        if [[ -f "$desktop_file" ]]; then
            log_success "Автозапуск отключения энергосбережения создан: $desktop_file"
            ls -lh "$desktop_file"
        else
            log_error "Не удалось создать файл: $desktop_file"
        fi
    else
        # Если xset не доступен, попробуем записать powermanagementprofilesrc как запасной вариант
        log_warning "xset не найден; обновляем или создаём powermanagementprofilesrc в домашней директории пользователя"
        pm_file="/home/$username/.config/powermanagementprofilesrc"
        sudo -u "$username" mkdir -p "$(dirname "$pm_file")"

        # Цель: в секции [AC] (или заголовке [AC][DPMSControl]) установить idleTime=21600 (6 часов)
        if [[ -f "$pm_file" ]]; then
            tmpfile="$(mktemp)"
            sudo -u "$username" awk '
                BEGIN { in_ac=0; seen=0 }
                /^\[AC(\]|\]\[DPMSControl\])?/ { print; in_ac=1; next }
                /^\[/ { if(in_ac==1 && seen==0) { print "idleTime=21600"; seen=1 } in_ac=0; print; next }
                { if(in_ac==1 && $0 ~ /^idleTime=/) { print "idleTime=21600"; seen=1; next } print }
                END { if(in_ac==1 && seen==0) print "idleTime=21600" }
            ' "$pm_file" > "$tmpfile" && sudo -u "$username" mv "$tmpfile" "$pm_file"
            sudo chown "$username:$username" "$pm_file" || true
            sudo chmod 644 "$pm_file" || true
            log_success "powermanagementprofilesrc обновлён: $pm_file (idleTime=21600 в секции [AC])"
        else
            sudo -u "$username" tee "$pm_file" > /dev/null <<'PMNEW'
[AC]
idleTime=21600
PMNEW
            sudo chown "$username:$username" "$pm_file"
            sudo chmod 644 "$pm_file"
            log_success "powermanagementprofilesrc создан: $pm_file (idleTime=21600)"
        fi
    fi
    
    # Защита директории autostart от изменений пользователем
    # Делаем это в конце, после создания всех autostart скриптов
    log_info "Защита директории autostart от изменений..."
    sudo chown root:root "$user_autostart_dir"
    sudo chmod 755 "$user_autostart_dir"
    log_success "Директория autostart защищена от изменений пользователем"
    
    # Удаление нежелательных приложений из меню
    log_info "Удаление нежелательных приложений..."
    if [[ -f /usr/share/applications/wine-winemine.desktop ]]; then
        sudo rm -f /usr/share/applications/wine-winemine.desktop
        log_success "Удалён wine-winemine.desktop"
    fi

    # Удаление Wine
    log_info "Удаление Wine..."
    log_info "Удаление Wine бинарников из /usr/bin..."
    sudo rm -f /usr/bin/wine* || true
    log_success "Wine бинарники удалены"
    
    log_info "Удаление пакетов Wine через dnf..."
    sudo dnf remove -y 'wine*' || true
    log_success "Пакеты Wine удалены"
}

# Функция для сброса конфигурации мыши для пользователя

# Функция для удаления всей конфигурации student
delete_student_config() {
    local target_user="${1:-student}"
    
    log_warning "Вы собираетесь удалить весь .config для пользователя '$target_user'"
    echo -n "Это действие нельзя отменить. Вы уверены? (yes/no): "
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Отмена удаления .config"
        return 0
    fi
    
    log_info "Удаление .config для пользователя '$target_user'..."
    
    # Проверка существования пользователя
    if ! id "$target_user" &>/dev/null; then
        log_error "Пользователь '$target_user' не существует"
        return 1
    fi
    
    local user_home=$(eval echo "~$target_user")
    local config_dir="$user_home/.config"
    
    # Удаление всей директории .config
    if [[ -d "$config_dir" ]]; then
        log_info "Удаление директории: $config_dir"
        sudo rm -rf "$config_dir"
        log_success "Директория .config удалена"
    else
        log_info "Директория .config не найдена: $config_dir"
    fi
    
    log_success ".config удален для пользователя '$target_user'"
    log_warning "Пользователю необходимо перезайти в систему для восстановления конфигурации по умолчанию"
    
    return 0
}

reset_mouse_config() {
    local target_user="${1:-student}"
    
    log_info "Сброс конфигурации мыши для пользователя '$target_user'..."
    
    # Проверка существования пользователя
    if ! id "$target_user" &>/dev/null; then
        log_error "Пользователь '$target_user' не существует"
        return 1
    fi
    
    local user_home=$(eval echo "~$target_user")
    local kcminputrc="$user_home/.config/kcminputrc"
    
    # Удаление файла конфигурации ввода
    if [[ -f "$kcminputrc" ]]; then
        log_info "Удаление файла конфигурации: $kcminputrc"
        sudo rm -f "$kcminputrc"
        log_success "Файл конфигурации удален"
    else
        log_info "Файл конфигурации не найден: $kcminputrc"
    fi
    
    # Очистка кэша конфигурации KDE
    local kde_cache_dirs=(
        "$user_home/.cache/ksycoca5*"
        "$user_home/.cache/kde-config"
    )
    
    for cache_pattern in "${kde_cache_dirs[@]}"; do
        if compgen -G "$cache_pattern" > /dev/null 2>&1; then
            log_info "Очистка кэша: $cache_pattern"
            sudo rm -rf $cache_pattern
        fi
    done
    
    log_success "Конфигурация мыши сброшена для пользователя '$target_user'"
    log_warning "Пользователю необходимо перезайти в систему для применения изменений"
    
    return 0
}

# Меню управления пользователями
user_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Управление пользователями ===${NC}"
        echo "1. Актуализировать пользователей"
        echo "2. Сбросить конфигурацию мыши для student"
        echo "3. Удалить конфигурацию для student"
        echo "4. Отладить polkit правила"
        echo "5. Вернуться в главное меню"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                setup_student_user
                ;;
            2)
                reset_mouse_config "student"
                ;;
            3)
                delete_student_config
                ;;
            4)
                debug_polkit_rules
                ;;
            5)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

################################################################################
# РАЗДЕЛ КОПИРОВАНИЯ И РЕЗЕРВНОГО КОПИРОВАНИЯ
################################################################################

# Функция для резервного копирования виртуальных машин
backup_virtual_machines() {
    local backup_dir="./vms"
    
    log_info "Резервное копирование виртуальных машин..."
    
    # Временно отключаем exit on error для этой функции
    set +e
    
    # Проверка установки libvirt
    if ! command -v virsh &> /dev/null; then
        log_error "libvirt не установлен. Операция невозможна."
        set -e
        return 1
    fi
    
    # Создание директории для резервных копий
    if [[ ! -d "$backup_dir" ]]; then
        log_info "Создание директории $backup_dir..."
        mkdir -p "$backup_dir"
    fi
    
    log_info "Получение списка виртуальных машин..."
    local vms=($(sudo virsh list --all --name))
    
    if [[ ${#vms[@]} -eq 0 ]]; then
        log_warning "Нет виртуальных машин для резервного копирования"
        set -e
        return 0
    fi
    
    log_info "Найдено ${#vms[@]} виртуальных машин"
    
    # Создание и форматирование директории для копий
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    backup_path="$backup_dir/backup_$backup_timestamp"
    mkdir -p "$backup_path"
    
    log_info "Резервные копии будут сохранены в: $backup_path"
    
    local failed=0
    local success=0
    
    for vm in "${vms[@]}"; do
        [[ -z "$vm" ]] && continue
        
        log_info "Резервное копирование ВМ: $vm"
        
        # Экспорт XML конфигурации
        if sudo virsh dumpxml "$vm" > "$backup_path/${vm}.xml" 2>/dev/null; then
            log_success "Конфигурация $vm экспортирована"
        else
            log_error "Ошибка при экспорте конфигурации $vm"
            ((failed++))
            continue
        fi
        
        # Получение информации о диск-образах из XML конфигурации
        log_info "Извлечение информации о дисках из конфигурации $vm..."
        
        # Использование более надежного способа извлечения путей с пробелами
        local disks=()
        while IFS= read -r line; do
            if [[ $line =~ \<source\ file=\'([^\']+)\' ]]; then
                disks+=("${BASH_REMATCH[1]}")
            fi
        done < "$backup_path/${vm}.xml"
        
        if [[ ${#disks[@]} -gt 0 ]]; then
            log_info "Найдено ${#disks[@]} дисков для ВМ $vm"
            
            for disk in "${disks[@]}"; do
                [[ -z "$disk" ]] && continue
                
                log_info "Проверка диска: $disk"
                
                if [[ -e "$disk" ]]; then
                    local disk_name=$(basename "$disk")
                    local disk_size=$(du -h "$disk" 2>/dev/null | cut -f1)
                    log_info "Копирование диска: $disk_name (размер: $disk_size)"
                    log_info "Исходный файл: $disk"
                    log_info "Целевой файл: $backup_path/${vm}_${disk_name}"
                    
                    # Попытка копирования с прогрессом используя rsync если доступен
                    if command -v rsync &> /dev/null; then
                        log_info "Использование rsync для копирования с отображением прогресса..."
                        sudo rsync -av --progress "$disk" "$backup_path/${vm}_${disk_name}"
                        local copy_exit_code=$?
                        
                        if [[ $copy_exit_code -eq 0 ]]; then
                            log_success "Диск $disk_name скопирован успешно"
                            log_info "Размер скопированного файла: $(du -h "$backup_path/${vm}_${disk_name}" 2>/dev/null | cut -f1)"
                            ((success++)) || true
                        else
                            log_error "Ошибка при копировании диска $disk_name (код: $copy_exit_code)"
                            log_error "Исходный файл: $disk"
                            log_error "Целевой файл: $backup_path/${vm}_${disk_name}"
                            log_error "Проверьте права доступа и свободное место на диске"
                            ((failed++)) || true
                        fi
                    else
                        # Fallback на cp если rsync недоступен
                        log_info "rsync не найден, используется cp..."
                        if sudo cp -v "$disk" "$backup_path/${vm}_${disk_name}" 2>&1 | while IFS= read -r line; do
                            log_info "$line"
                        done; then
                            log_success "Диск $disk_name скопирован успешно"
                            log_info "Размер скопированного файла: $(du -h "$backup_path/${vm}_${disk_name}" 2>/dev/null | cut -f1)"
                            ((success++)) || true
                        else
                            local copy_exit_code=$?
                            log_error "Ошибка при копировании диска $disk_name (код: $copy_exit_code)"
                            log_error "Исходный файл: $disk"
                            log_error "Целевой файл: $backup_path/${vm}_${disk_name}"
                            log_error "Проверьте права доступа и свободное место на диске"
                            ((failed++)) || true
                        fi
                    fi
                else
                    log_warning "Диск не найден или недоступен: $disk"
                    log_warning "Проверьте существование файла и права доступа"
                    ((failed++)) || true
                fi
            done
        else
            log_warning "Дисков не найдено для ВМ $vm"
            log_warning "Проверьте XML конфигурацию в $backup_path/${vm}.xml"
        fi
        
        # Увеличиваем счетчик успешных ВМ (для статистики)
        ((success++)) || true
    done
    
    log_success "Резервное копирование завершено"
    log_info "Успешно скопировано: $success, Ошибки: $failed"
    if [[ $failed -gt 0 ]]; then
        log_warning "Произошли ошибки при копировании некоторых дисков"
        log_info "Проверьте логи выше для получения подробной информации"
    fi
    log_info "Резервные копии находятся в: $(pwd)/$backup_path"
    
    # Восстанавливаем exit on error
    set -e
    return 0
}

# Функция для восстановления виртуальных машин
restore_virtual_machines() {
    local backup_dir="./vms"
    
    log_info "Восстановление виртуальных машин..."
    
    # Проверка установки libvirt
    if ! command -v virsh &> /dev/null; then
        log_error "libvirt не установлен. Операция невозможна."
        return 1
    fi
    
    # Проверка существования директории
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Директория резервных копий не найдена: $backup_dir"
        return 1
    fi
    
    # Поиск резервных копий
    local backups=($(find "$backup_dir" -maxdepth 1 -type d -name "backup_*" | sort -r))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        log_error "Резервные копии не найдены в: $backup_dir"
        return 1
    fi
    
    log_info "Найдено ${#backups[@]} резервных копий"
    
    # Выбор резервной копии
    echo ""
    log_info "Доступные резервные копии:"
    for i in "${!backups[@]}"; do
        echo "  $((i+1)). $(basename "${backups[$i]}")"
    done
    
    echo -n "Выберите номер резервной копии для восстановления: "
    read -r backup_choice
    
    if [[ ! "$backup_choice" =~ ^[0-9]+$ ]] || (( backup_choice < 1 || backup_choice > ${#backups[@]} )); then
        log_error "Неверный выбор"
        return 1
    fi
    
    local selected_backup="${backups[$((backup_choice-1))]}"
    log_info "Выбрана резервная копия: $(basename "$selected_backup")"
    
    # Поиск XML файлов конфигураций в выбранной резервной копии
    local vm_configs=($(find "$selected_backup" -maxdepth 1 -name "*.xml" -type f))
    
    if [[ ${#vm_configs[@]} -eq 0 ]]; then
        log_error "Конфигурации ВМ не найдены в резервной копии"
        return 1
    fi
    
    log_info "Найдено ${#vm_configs[@]} конфигураций ВМ"
    
    local failed=0
    local success=0
    
    for vm_config in "${vm_configs[@]}"; do
        local vm_name=$(basename "$vm_config" .xml)
        
        log_info "Восстановление ВМ: $vm_name"
        
        # Проверка существования ВМ
        if sudo virsh list --all --name | grep -q "^$vm_name$"; then
            log_warning "ВМ $vm_name уже существует. Пропуск."
            ((failed++))
            continue
        fi
        
        # Восстановление конфигурации и дисков
        if sudo virsh define "$vm_config" 2>/dev/null; then
            log_success "ВМ $vm_name восстановлена из конфигурации"
            
            # Получение всех путей дисков из XML конфигурации (с поддержкой пробелов)
            local disk_paths=()
            while IFS= read -r line; do
                if [[ $line =~ \<source\ file=\'([^\']+)\' ]]; then
                    disk_paths+=("${BASH_REMATCH[1]}")
                fi
            done < "$vm_config"
            
            if [[ ${#disk_paths[@]} -gt 0 ]]; then
                log_info "Восстановление ${#disk_paths[@]} дисков для ВМ $vm_name"
                
                for original_disk_path in "${disk_paths[@]}"; do
                    local disk_basename=$(basename "$original_disk_path")
                    local backup_disk_file="$selected_backup/${vm_name}_${disk_basename}"
                    
                    if [[ -f "$backup_disk_file" ]]; then
                        log_info "Копирование диска: $disk_basename → $original_disk_path"
                        log_info "Исходный файл: $backup_disk_file"
                        log_info "Целевой файл: $original_disk_path"
                        local disk_size=$(du -h "$backup_disk_file" 2>/dev/null | cut -f1)
                        log_info "Размер диска: $disk_size"
                        
                        # Создание директории если необходимо
                        sudo mkdir -p "$(dirname "$original_disk_path")"
                        
                        # Попытка копирования с прогрессом используя rsync если доступен
                        if command -v rsync &> /dev/null; then
                            log_info "Использование rsync для копирования с отображением прогресса..."
                            sudo rsync -av --progress "$backup_disk_file" "$original_disk_path"
                            local restore_exit_code=$?
                            
                            if [[ $restore_exit_code -eq 0 ]]; then
                                log_success "Диск восстановлен: $disk_basename"
                                log_info "Размер восстановленного файла: $(du -h "$original_disk_path" 2>/dev/null | cut -f1)"
                                ((success++)) || true
                            else
                                log_error "Ошибка при восстановлении диска: $disk_basename (код: $restore_exit_code)"
                                log_error "Исходный файл: $backup_disk_file"
                                log_error "Целевой файл: $original_disk_path"
                                log_error "Проверьте права доступа и свободное место на диске"
                                ((failed++)) || true
                            fi
                        else
                            # Fallback на cp если rsync недоступен
                            log_info "rsync не найден, используется cp..."
                            if sudo cp -v "$backup_disk_file" "$original_disk_path" 2>&1 | while IFS= read -r line; do
                                log_info "$line"
                            done; then
                                log_success "Диск восстановлен: $disk_basename"
                                log_info "Размер восстановленного файла: $(du -h "$original_disk_path" 2>/dev/null | cut -f1)"
                                ((success++)) || true
                            else
                                local restore_exit_code=$?
                                log_error "Ошибка при копировании диска: $disk_basename (код: $restore_exit_code)"
                                log_error "Исходный файл: $backup_disk_file"
                                log_error "Целевой файл: $original_disk_path"
                                log_error "Проверьте права доступа и свободное место на диске"
                                ((failed++)) || true
                            fi
                        fi
                    else
                        log_warning "Файл резервной копии диска не найден: $backup_disk_file"
                    fi
                done
            fi
            
            ((success++)) || true
        else
            log_error "Ошибка при восстановлении ВМ $vm_name"
            ((failed++))
        fi
    done
    
    log_success "Восстановление завершено"
    log_info "Успешно: $success, Ошибки: $failed"
}

# Меню управления копированием
copy_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Копирование ===${NC}"
        echo "1. Виртуальные машины"
        echo "2. Вернуться в главное меню"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                vm_copy_menu
                ;;
            2)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

# Подменю для работы с виртуальными машинами
vm_copy_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Копирование - Виртуальные машины ===${NC}"
        echo "1. Создать резервные копии ВМ"
        echo "2. Восстановить ВМ из резервной копии"
        echo "3. Вернуться в меню копирования"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                backup_virtual_machines
                ;;
            2)
                restore_virtual_machines
                ;;
            3)
                break
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

################################################################################
# ГЛАВНОЕ МЕНЮ
################################################################################

main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║    Скрипт управления ПК               ║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
        echo "1. Управление прокси"
        echo "2. Установка программного обеспечения"
        echo "3. Управление пользователями"
        echo "4. Копирование"
        echo "5. Выход"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                proxy_management
                ;;
            2)
                software_installation
                ;;
            3)
                user_management
                ;;
            4)
                copy_management
                ;;
            5)
                log_success "Выход. До свидания!"
                exit 0
                ;;
            *)
                log_error "Неверная опция"
                ;;
        esac
    done
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Обработка аргументов командной строки для внутренних вызовов с sudo
    if [[ "${1:-}" == "--set-proxy" ]] && [[ -n "${2:-}" ]]; then
        set_proxy "$2"
        exit 0
    elif [[ "${1:-}" == "--disable-proxy" ]]; then
        disable_proxy
        exit 0
    else
        main_menu
    fi
fi
