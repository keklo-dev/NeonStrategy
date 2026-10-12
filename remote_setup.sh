#!/usr/bin/env bash
# Neon Strategy — развёртывание выделенного сервера ОДНОЙ командой.
# Запускать на VPS (например, в VNC-консоли) от root:
#   curl -fsSL https://raw.githubusercontent.com/keklo-dev/NeonStrategy/linux-server/remote_setup.sh -o /root/rs.sh && bash /root/rs.sh
# Идемпотентно: бэкапит текущий сервер, ставит новый, перезапускает systemd.
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/keklo-dev/NeonStrategy/linux-server"
APP="/opt/neonstrategy"
PORT="${NGS_PORT:-7777}"
SEED="${NGS_SEED:-424242}"

echo "==> Neon Strategy server deploy"

# 1. curl (на случай чистой системы)
if ! command -v curl >/dev/null 2>&1; then
  echo "==> установка curl"
  apt-get update -y && apt-get install -y curl
fi

# 2. swap 1 ГБ (у бокса мало RAM) — если своп ещё не включён
if ! swapon --show 2>/dev/null | grep -q .; then
  echo "==> включаю swap 1 ГБ"
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '/swapfile' /etc/fstab 2>/dev/null || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 3. скачиваем сборку
echo "==> скачиваю server.tar.gz"
curl -fsSL "$REPO_RAW/server.tar.gz" -o /root/server.tar.gz

# 4. останавливаем текущий сервер + бэкап (профили игроков лежат в /root/.config — НЕ трогаем)
systemctl stop neonstrategy 2>/dev/null || true
if [ -d "$APP" ]; then
  TS="$(date +%s)"
  echo "==> бэкап текущего сервера → ${APP}.bak-${TS}"
  cp -a "$APP" "${APP}.bak-${TS}"
  # держим только 2 последних бэкапа
  ls -dt ${APP}.bak-* 2>/dev/null | tail -n +3 | xargs -r rm -rf
fi

# 5. чистая установка новой сборки
echo "==> распаковываю новую сборку в $APP"
rm -rf "$APP"
mkdir -p "$APP"
tar xzf /root/server.tar.gz -C "$APP"
chmod +x "$APP/NeonStrategyServer.x86_64"
chown -R root:root "$APP"

# 6. systemd-юнит
echo "==> systemd neonstrategy.service"
cat > /etc/systemd/system/neonstrategy.service <<UNIT
[Unit]
Description=Neon Strategy Dedicated Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP
ExecStart=$APP/NeonStrategyServer.x86_64 -batchmode -nographics -server -port $PORT -seed $SEED -logFile $APP/server.log
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable neonstrategy >/dev/null 2>&1 || true
systemctl restart neonstrategy

sleep 3
echo "==> статус:"
systemctl --no-pager status neonstrategy | head -n 12 || true
echo "==> server.log (хвост):"
sleep 2
tail -n 25 "$APP/server.log" 2>/dev/null || echo "(лог ещё не создан — подождите пару секунд и: tail -f $APP/server.log)"
echo "==> ГОТОВО. Порт UDP $PORT, seed $SEED."
