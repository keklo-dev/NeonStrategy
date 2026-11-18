#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
#  Neon Strategy — установка/обновление выделенного сервера (Ubuntu 24.04).
#  Идемпотентно: повторный запуск = обновление сервера до свежего архива.
#
#  БЫСТРЫЙ СТАРТ (VNC-консоль OneDash или SSH), ОДНА КОМАНДА:
#    curl -fsSL https://raw.githubusercontent.com/keklo-dev/NeonStrategy/linux-server/deploy_server.sh -o /root/deploy_server.sh && bash /root/deploy_server.sh
#
#  Вариант с локальным архивом (залит руками по scp/sftp в /root):
#    bash /root/deploy_server.sh /root/server.tar.gz
#
#  Что делает: пакеты → swap 1 ГБ (если нет) → скачивание server.tar.gz →
#  бэкап /opt/neonstrategy (храним 2 последних) → распаковка → systemd-юнит
#  neonstrategy (автозапуск, Restart=always) → ufw (22 + 7777) → статус+лог.
#
#  ТРАНСПОРТ: по умолчанию WebSocket на 7777/tcp — ЕДИНЫЙ мир для ПК,
#  Android и веб-клиентов (браузеры не умеют UDP). Порт 7777/udp нужен
#  только для режима «-udp» (сервер И клиенты с флагом -udp одновременно).
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

APP_DIR=/opt/neonstrategy
SERVICE=neonstrategy
PORT=7777
ARCHIVE_URL="https://raw.githubusercontent.com/keklo-dev/NeonStrategy/linux-server/server.tar.gz"

echo "== [1/6] Пакеты (curl, ufw)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ufw >/dev/null

echo "== [2/6] Swap (RAM на тарифе 1 ГБ)"
if ! swapon --show --noheadings | grep -q .; then
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  echo "   swap 1 ГБ включён"
else
  echo "   swap уже есть: $(swapon --show --noheadings | awk '{print $1" "$3}')"
fi

echo "== [3/6] Получаю серверный архив"
mkdir -p "$APP_DIR"
tmp=$(mktemp -d)
if [ -n "${1:-}" ] && [ -f "$1" ]; then
  echo "   локальный файл: $1"
  cp "$1" "$tmp/server.tar.gz"
else
  echo "   скачивание: $ARCHIVE_URL"
  curl -fsSL "$ARCHIVE_URL" -o "$tmp/server.tar.gz"
fi

if [ -d "$APP_DIR/NeonStrategyServer_Data" ]; then
  ts=$(date +%Y%m%d-%H%M%S)
  echo "   бэкап $APP_DIR → $APP_DIR.bak-$ts"
  cp -a "$APP_DIR" "$APP_DIR.bak-$ts"
  ls -1dt "$APP_DIR".bak-* | tail -n +3 | xargs -r rm -rf
  find "$APP_DIR" -mindepth 1 -delete
fi

tar xzf "$tmp/server.tar.gz" -C "$APP_DIR"
rm -rf "$tmp"
chmod +x "$APP_DIR/NeonStrategyServer.x86_64"
chown -R root:root "$APP_DIR"

echo "== [4/6] systemd-юнит $SERVICE (автозапуск)"
cat > "/etc/systemd/system/$SERVICE.service" <<EOF
[Unit]
Description=Neon Strategy dedicated server (NGO/WebSocket :$PORT)
After=network.target

[Service]
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/NeonStrategyServer.x86_64 -batchmode -nographics -server -port $PORT -logFile $APP_DIR/server.log
Restart=always
RestartSec=5
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now "$SERVICE"

echo "== [5/6] Firewall (ufw)"
ufw allow 22/tcp comment 'SSH' >/dev/null
ufw allow "$PORT"/tcp comment 'Neon Strategy (WebSocket)' >/dev/null
ufw allow "$PORT"/udp comment 'Neon Strategy (UDP fallback)' >/dev/null
ufw --force enable >/dev/null
echo "   разрешено: 22/tcp, $PORT/tcp, $PORT/udp"

echo "== [6/6] Статус"
systemctl --no-pager status "$SERVICE" 2>/dev/null | head -n 6 || true
sleep 2
echo "--- хвост лога ($APP_DIR/server.log):"
tail -n 12 "$APP_DIR/server.log" 2>/dev/null || true
echo "--- слушающие порты:"
(ss -lntup 2>/dev/null || netstat -lntup) | grep -E ":(22|$PORT)\b" || true
ext_ip=$(curl -fsSL -m 5 ifconfig.me 2>/dev/null || echo '<внешний IP>')
echo
echo "ГОТОВО. Игроки подключаются к $ext_ip:$PORT (WebSocket; сид мира 424242)."
