#!/usr/bin/env bash
# Установка сервера Strategyca на Linux-сервер (Ubuntu 22.04 / 24.04, Debian 12).
#
#   bash install.sh                      - сервер на http://IP-СЕРВЕРА:7777 (быстро, без домена)
#   bash install.sh мойдомен.duckdns.org - ещё и HTTPS: https://мойдомен.duckdns.org (нужен домен, смотрящий на этот сервер)
#
# Запускать из папки, где лежит файл StrategycaServer, от root (или через sudo).
# Повторный запуск безопасен: обновит программу, данные игроков не трогает.
set -euo pipefail

DOMAIN="${1:-}"
PORT=7777
APP=/opt/strategyca
DATA=/var/lib/strategyca
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then echo "Запустите от root: sudo bash install.sh $DOMAIN"; exit 1; fi
if [ ! -f "$HERE/StrategycaServer" ]; then echo "Рядом с install.sh нет файла StrategycaServer"; exit 1; fi

# Маленький сервер (1 ГБ памяти): файл подкачки 1 ГБ, чтобы установка пакетов и сервер не упали от нехватки памяти
if [ "$(awk '/MemTotal/ {print $2}' /proc/meminfo)" -lt 1600000 ] && [ "$(swapon --show --noheadings | wc -l)" -eq 0 ]; then
  echo "== Файл подкачки 1 ГБ"
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile && mkswap /swapfile >/dev/null && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "== 1/4 Программа сервера"
id strategyca >/dev/null 2>&1 || useradd --system --home "$DATA" --shell /usr/sbin/nologin strategyca
mkdir -p "$APP" "$DATA"
systemctl stop strategyca 2>/dev/null || true
install -m 755 "$HERE/StrategycaServer" "$APP/StrategycaServer"
# Ключ Google Play для проверки покупок (если есть) - рядом с данными
# Ключи и настройки (если положили рядом с install.sh) - в папку данных
for f in google_play_key.txt firebase-service-account.json server-config.json; do
  if [ -f "$HERE/$f" ]; then install -m 600 "$HERE/$f" "$DATA/$f"; echo "скопирован $f"; fi
done
chown -R strategyca:strategyca "$DATA"

# С доменом сервер слушает только этот компьютер, снаружи к нему ходят через Caddy (HTTPS)
EXTRA=""
if [ -n "$DOMAIN" ]; then EXTRA="--local"; fi

echo "== 2/4 Автозапуск (systemd)"
cat > /etc/systemd/system/strategyca.service <<UNIT
[Unit]
Description=Strategyca game server
After=network-online.target
Wants=network-online.target

[Service]
User=strategyca
WorkingDirectory=$DATA
ExecStart=$APP/StrategycaServer --port $PORT --data $DATA $EXTRA
Restart=always
RestartSec=3
KillSignal=SIGTERM
TimeoutStopSec=20
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now strategyca

echo "== 3/4 Брандмауэр"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow OpenSSH >/dev/null
  if [ -n "$DOMAIN" ]; then ufw allow 80/tcp >/dev/null; ufw allow 443/tcp >/dev/null; else ufw allow $PORT/tcp >/dev/null; fi
  echo "ufw: порты открыты"
else
  echo "ufw выключен - ничего делать не нужно (если у хостинга есть свой брандмауэр в панели - откройте там порт $([ -n "$DOMAIN" ] && echo '80 и 443' || echo $PORT))"
fi

if [ -n "$DOMAIN" ]; then
  echo "== 4/4 HTTPS через Caddy для $DOMAIN"
  if ! command -v caddy >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update -y
    apt-get install -y caddy
  fi
  cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
    encode gzip
    reverse_proxy 127.0.0.1:$PORT
}
CADDY
  systemctl enable caddy >/dev/null 2>&1 || true
  systemctl restart caddy
  ADDR="https://$DOMAIN"
else
  echo "== 4/4 HTTPS пропущен (домен не указан)"
  IP="$(curl -s -4 --max-time 5 https://api.ipify.org || hostname -I | awk '{print $1}')"
  ADDR="http://$IP:$PORT"
fi

sleep 2
echo
if systemctl is-active --quiet strategyca; then
  echo "ГОТОВО. Сервер работает."
else
  echo "Сервер не запустился. Что случилось: journalctl -u strategyca -n 50"
  exit 1
fi
echo "Адрес для игры:  $ADDR"
echo "Проверка: откройте его в браузере - должно быть «Сервер Strategyca работает»."
echo "(для HTTPS сертификат появляется в течение минуты после первого запуска)"
echo
KEYLINE="$(journalctl -u strategyca -n 60 --no-pager 2>/dev/null | grep -o 'http://localhost:[0-9]*/admin?key=[A-Za-z0-9_-]*' | tail -1 || true)"
if [ -n "$KEYLINE" ]; then echo "Модерация жалоб (никому не давайте): ${ADDR}/admin?key=${KEYLINE##*key=}"; fi
echo "Политика конфиденциальности: $ADDR/privacy    Удаление аккаунта: $ADDR/delete-account"
echo "Почту для игроков впишите в $DATA/server-config.json (\"contactEmail\"), затем: systemctl restart strategyca"
echo
echo "Полезное:"
echo "  журнал сервера:     journalctl -u strategyca -f"
echo "  перезапуск:         systemctl restart strategyca"
echo "  данные игроков:     $DATA   (копия: tar czf strategyca-backup.tgz -C $DATA .)"
