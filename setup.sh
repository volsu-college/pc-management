#!/bin/bash

################################################################################
# Скрипт управления ПК
# Этот скрипт предоставляет утилиты для управления прокси и установки ПО
################################################################################

set -euo pipefail

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
    
    # Установка прокси в .bashrc для переменной окружения HTTP_PROXY
    log_info "Конфигурирование прокси для .bashrc..."
    bashrc_path="${HOME}/.bashrc"
    
    # Удаление существующих параметров прокси если они есть
    sed -i '/^export HTTP_PROXY=/d' "$bashrc_path"
    sed -i '/^export HTTPS_PROXY=/d' "$bashrc_path"
    sed -i '/^export http_proxy=/d' "$bashrc_path"
    sed -i '/^export https_proxy=/d' "$bashrc_path"
    
    # Добавление новых параметров прокси
    cat >> "$bashrc_path" <<EOF

# Конфигурация прокси
export HTTP_PROXY="$proxy_url"
export HTTPS_PROXY="$proxy_url"
export http_proxy="$proxy_url"
export https_proxy="$proxy_url"
EOF
    
    # Экспорт в текущую оболочку
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    
    # Конфигурирование прокси для rsync
    log_info "Конфигурирование прокси для rsync..."
    rsync_conf="${HOME}/.rsync"
    mkdir -p "$rsync_conf"
    cat > "$rsync_conf/rsync.conf" <<EOF
# Конфигурация прокси для rsync
proxy=$proxy_url
EOF
    log_success "Прокси для rsync настроен"
    
    # Конфигурирование прокси для ftp
    log_info "Конфигурирование прокси для ftp..."
    
    # Удаление существующих параметров ftp прокси если они есть
    sed -i '/^export ftp_proxy=/d' "$bashrc_path"
    sed -i '/^export FTP_PROXY=/d' "$bashrc_path"
    
    # Добавление параметров прокси для ftp
    cat >> "$bashrc_path" <<EOF

# Конфигурация прокси для FTP
export FTP_PROXY="$proxy_url"
export ftp_proxy="$proxy_url"
EOF
    
    # Экспорт FTP прокси в текущую оболочку
    export FTP_PROXY="$proxy_url"
    export ftp_proxy="$proxy_url"
    
    log_success "Прокси для FTP настроен"

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
    
    log_success "Параметры прокси применены к .bashrc"
    log_success "Конфигурация прокси завершена. Пожалуйста, выполните: source ~/.bashrc"
}

# Функция отключения прокси
disable_proxy() {
    log_info "Отключение конфигурации прокси..."
    
    # Удаление прокси из dnf
    if [[ -f /etc/dnf/dnf.conf ]]; then
        sudo sed -i '/^proxy=/d' /etc/dnf/dnf.conf
        log_success "Прокси удален из конфигурации DNF"
    fi
    
    # Удаление прокси из .bashrc
    bashrc_path="${HOME}/.bashrc"
    sed -i '/^export HTTP_PROXY=/d' "$bashrc_path"
    sed -i '/^export HTTPS_PROXY=/d' "$bashrc_path"
    sed -i '/^export http_proxy=/d' "$bashrc_path"
    sed -i '/^export https_proxy=/d' "$bashrc_path"
    sed -i '/^export FTP_PROXY=/d' "$bashrc_path"
    sed -i '/^export ftp_proxy=/d' "$bashrc_path"
    
    # Удаление конфигурации rsync
    rsync_conf="${HOME}/.rsync"
    if [[ -f "$rsync_conf/rsync.conf" ]]; then
        rm -f "$rsync_conf/rsync.conf"
        log_success "Конфигурация rsync удалена"
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
    log_info "Пожалуйста, выполните: source ~/.bashrc"
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
                set_proxy "$proxy_url"
                ;;
            2)
                disable_proxy
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

# Функция для установки Visual Studio Code через DNF
install_vscode() {
    log_info "Установка Visual Studio Code через DNF..."
    
    if command -v code &> /dev/null; then
        log_warning "Visual Studio Code уже установлен"
        return 0
    fi
    
    # Вариант 1: Установка с помощью менеджера пакетов согласно RED OS 8 документации
    log_info "Импортирование ключа Microsoft для проверки подлинности пакетов..."
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    
    log_info "Создание файла подключения репозитория Visual Studio Code..."
    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<'VSCODE_REPO_EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
VSCODE_REPO_EOF
    
    log_info "Обновление кеша пакетов..."
    sudo dnf check-update
    
    log_info "Установка Visual Studio Code..."
    sudo dnf install -y code
    
    if command -v code &> /dev/null; then
        log_success "Visual Studio Code успешно установлен"
        log_info "Запуск: code или через меню Программирование"
    else
        log_error "Ошибка при установке Visual Studio Code"
        return 1
    fi
}

# Функция для установки Visual Studio Code через snap
install_vscode_snap() {
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

# Меню выбора метода установки Visual Studio Code
vscode_installation_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Установка Visual Studio Code ===${NC}"
        echo "1. Установить через DNF (рекомендуется)"
        echo "2. Установить через snap"
        echo "3. Вернуться в меню программного обеспечения"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                install_vscode
                ;;
            2)
                install_vscode_snap
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
        
        # Добавление текущего пользователя в группу libvirt
        log_info "Добавление пользователя в группу libvirt..."
        sudo usermod -a -G libvirt "$USER"
        log_success "Пользователь добавлен в группу libvirt"
        
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

# Функция для установки всего ПО
install_all_software() {
    log_info "Установка всех пакетов ПО..."
    
    install_vscode
    install_pycharm
    install_libvirt
    install_fpc
    
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

software_installation() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Установка программного обеспечения ===${NC}"
        echo "1. Установить Visual Studio Code"
        echo "2. Установить PyCharm Community"
        echo "3. Управление libvirt (QEMU-KVM)"
        echo "4. Установить FPC (Free Pascal Compiler)"
        echo "5. Установить все программное обеспечение"
        echo "6. Вернуться в главное меню"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                vscode_installation_menu
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
                install_all_software
                ;;
            6)
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
    local password="volsu"
    
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
    
    # Установка пароля для red8
    log_info "Установка пароля для пользователя 'red8'..."
    echo "red8:qw401hng" | sudo chpasswd
    log_success "Пароль установлен для 'red8'"
    
    # Установка пароля для root
    log_info "Установка пароля для пользователя 'root'..."
    echo "root:qw401hng" | sudo chpasswd
    log_success "Пароль установлен для 'root'"
    
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
        // Разрешить подключение к libvirt
        if (action.id.match(/^org\.libvirt\.unix\.manage$/)) {
            return polkit.Result.YES;
        }
        // Разрешить управление виртуальными машинами (запуск, остановка, пауза)
        if (action.id.match(/^org\.libvirt\.domain\.(getattr|open|list|read-config)$/)) {
            return polkit.Result.YES;
        }
        if (action.id.match(/^org\.libvirt\.domain\.control\.manage$/)) {
            return polkit.Result.YES;
        }
        // Запретить создание и редактирование конфигураций
        if (action.id.match(/^org\.libvirt\.domain\.(create|delete|modify|undefine)$/)) {
            return polkit.Result.NO;
        }
        if (action.id.match(/^org\.libvirt\.network\.control-modify$/)) {
            return polkit.Result.NO;
        }
    }
});
POLKIT_EOF
    
    log_success "Правила polkit созданы"
    
    # Создание конфигурации libvirt для ограничения доступа
    log_info "Конфигурирование libvirt ACL..."
    sudo mkdir -p /etc/libvirt/qemu/
    
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
    log_warning "Пользователь 'student' может:"
    echo "  - Подключаться к libvirt"
    echo "  - Просматривать виртуальные машины"
    echo "  - Запускать и останавливать ВМ"
    log_warning "Пользователь 'student' НЕ может:"
    echo "  - Создавать новые ВМ"
    echo "  - Изменять конфигурацию ВМ"
    echo "  - Удалять ВМ"
    echo "  - Изменять сетевые настройки"
}

# Меню управления пользователями
user_management() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Управление пользователями ===${NC}"
        echo "1. Создать/обновить пользователя 'student' (volsu)"
        echo "2. Вернуться в главное меню"
        echo -n "Выберите опцию: "
        read -r choice
        
        case $choice in
            1)
                setup_student_user
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
    main_menu
fi
