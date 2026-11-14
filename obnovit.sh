#!/usr/bin/env bash
# Обновление сервера Strategyca до final-13-fix-2: на войне кланов по фермам можно ходить.
# Запуск: bash obnovit.sh   (из папки, где лежат этот файл и StrategycaServer)
# Данные игроков не трогает; перед обновлением делает их копию в /root.
set -euo pipefail
APP=/opt/strategyca
DATA=/var/lib/strategyca
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ "$(id -u)" -ne 0 ]; then echo "Нужно запускать от root"; exit 1; fi
if [ ! -f "$HERE/StrategycaServer" ]; then echo "Рядом нет файла StrategycaServer - загрузите его в ту же папку"; exit 1; fi
if [ ! -d "$APP" ]; then echo "Сервер не найден в $APP"; exit 1; fi
if [ ! -f "$DATA/google_play_key.txt" ]; then echo "Внимание: нет $DATA/google_play_key.txt - покупки марок не будут проверяться (см. инструкцию). Обновляю дальше."; fi

STAMP="$(date +%Y%m%d-%H%M)"
echo "== 1/3 Копия данных игроков"
tar czf "/root/strategyca-data-$STAMP.tgz" -C "$DATA" .
cp "$APP/StrategycaServer" "/root/StrategycaServer-old-$STAMP"
echo "   данные: /root/strategyca-data-$STAMP.tgz"
echo "   старая программа: /root/StrategycaServer-old-$STAMP"

echo "== 2/3 Новая программа"
systemctl stop strategyca
install -m 755 "$HERE/StrategycaServer" "$APP/StrategycaServer"
systemctl start strategyca
sleep 3

echo "== 3/3 Проверка"
if ! systemctl is-active --quiet strategyca; then
  echo "Новая версия не запустилась - возвращаю старую."
  install -m 755 "/root/StrategycaServer-old-$STAMP" "$APP/StrategycaServer"
  systemctl start strategyca
  echo "Старая версия снова работает. Что случилось: journalctl -u strategyca -n 50"
  exit 1
fi
KEY="$(grep -o '"adminKey"[^,]*' "$DATA/server-config.json" | sed 's/.*: *"\(.*\)"/\1/')"
ADDR="https://strategyca.duckdns.org"
grep -q "reverse_proxy" /etc/caddy/Caddyfile 2>/dev/null || ADDR="http://$(hostname -I | awk '{print $1}'):7777"
echo
echo "ГОТОВО. Сервер обновлён и работает."
echo
echo "Обновление игры (кнопка «Требовать сборку 15» - только когда сборка 15 уже в Google Play):  $ADDR/admin?key=$KEY"
echo "Игроки и их базы:  $ADDR/admin/players?key=$KEY"
echo "Жалобы:            $ADDR/admin?key=$KEY"
echo "Ссылки никому не давайте."
printf '%s\n' "Игроки и их базы: $ADDR/admin/players?key=$KEY" "Жалобы: $ADDR/admin?key=$KEY" > /root/admin-ssylka.txt
echo "Эти же ссылки записаны в файл /root/admin-ssylka.txt (откройте его в WinSCP и скопируйте)."
