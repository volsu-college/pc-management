#!/bin/bash
set -euo pipefail

# Скрипт настройки киоска для Debian 13 с XFCE
# Использование: ./kiosk.sh [--proxy proxy_server[:port]] user@host [kiosk_url]

PROXY_SERVER=""
PROXY_PORT="5000"

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy)
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                if [[ "$2" == *:* ]]; then
                    PROXY_SERVER="${2%:*}"
                    PROXY_PORT="${2##*:}"
                else
                    PROXY_SERVER="$2"
                fi
                shift 2
            else
                echo "Ошибка: --proxy требует аргумент"
                exit 1
            fi
            ;;
        -*)
            echo "Неизвестный параметр: $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    echo "Использование: $0 [--proxy proxy_server[:port]] user@host [kiosk_url]"
    echo "Пример: $0 nikita@192.168.0.199 https://example.com"
    echo "Пример с прокси: $0 --proxy frp.spo.nn-projects.ru:5000 root@1013404958.volsu.ru https://example.com"
    exit 1
fi

TARGET_HOST="$1"
KIOSK_URL="${2:-https://www.google.com}"
KIOSK_USER="kiosk"

echo "Настройка киоска на $TARGET_HOST"
echo "URL киоска: $KIOSK_URL"

# Выполнение SSH с или без прокси
run_ssh() {
    if [[ -n "$PROXY_SERVER" ]]; then
        echo "Прокси: $PROXY_SERVER:$PROXY_PORT"
        ssh -t -o "proxycommand=socat - PROXY:$PROXY_SERVER:%h:%p,proxyport=$PROXY_PORT" "$TARGET_HOST" bash -s "$KIOSK_USER" "$KIOSK_URL"
    else
        ssh -t "$TARGET_HOST" bash -s "$KIOSK_USER" "$KIOSK_URL"
    fi
}

run_ssh << 'REMOTE_SCRIPT'
set -euo pipefail

KIOSK_USER="$1"
KIOSK_URL="$2"

echo "==> Установка необходимых пакетов..."
sudo apt-get update
sudo apt-get install -y chromium xfce4 lightdm unclutter

echo "==> Установка часового пояса Москва..."
sudo timedatectl set-timezone Europe/Moscow

echo "==> Создание пользователя киоска..."
if ! id "$KIOSK_USER" &>/dev/null; then
    sudo useradd -m -s /bin/bash "$KIOSK_USER"
    echo "Пользователь $KIOSK_USER создан"
else
    echo "Пользователь $KIOSK_USER уже существует"
fi

echo "==> Настройка автовхода LightDM..."
sudo mkdir -p /etc/lightdm/lightdm.conf.d
sudo tee /etc/lightdm/lightdm.conf.d/50-kiosk.conf > /dev/null << EOF
[Seat:*]
autologin-user=$KIOSK_USER
autologin-user-timeout=0
user-session=xfce
EOF

echo "==> Настройка автозапуска киоска..."
KIOSK_HOME="/home/$KIOSK_USER"
sudo mkdir -p "$KIOSK_HOME/.config/autostart"

# Автозапуск Chromium в режиме киоска
sudo tee "$KIOSK_HOME/.config/autostart/chromium-kiosk.desktop" > /dev/null << EOF
[Desktop Entry]
Type=Application
Name=Chromium Kiosk
Exec=/usr/bin/chromium --kiosk --noerrdialogs --disable-infobars --no-first-run --disable-session-crashed-bubble --disable-translate --start-fullscreen --password-store=basic --disable-features=PasswordManager,Translate,TranslateUI "$KIOSK_URL"
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# Unclutter для скрытия курсора мыши при бездействии
sudo tee "$KIOSK_HOME/.config/autostart/unclutter.desktop" > /dev/null << EOF
[Desktop Entry]
Type=Application
Name=Unclutter
Exec=unclutter -idle 1
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

# Отключение гашения экрана
sudo tee "$KIOSK_HOME/.config/autostart/disable-blanking.desktop" > /dev/null << EOF
[Desktop Entry]
Type=Application
Name=Отключение гашения экрана
Exec=xset s off -dpms
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

echo "==> Отключение управления питанием XFCE для пользователя киоска..."
sudo mkdir -p "$KIOSK_HOME/.config/xfce4/xfconf/xfce-perchannel-xml"
sudo tee "$KIOSK_HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
  </property>
</channel>
EOF
sudo chown -R "$KIOSK_USER:$KIOSK_USER" "$KIOSK_HOME/.config"

echo "==> Настройка киоска завершена!"
echo "Перезагрузите систему для запуска режима киоска: sudo reboot"
REMOTE_SCRIPT

echo "Готово! Перезагрузите целевую машину для запуска режима киоска."
