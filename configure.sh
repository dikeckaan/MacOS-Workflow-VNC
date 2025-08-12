#!/usr/bin/env bash
set -euo pipefail

# ========= 設定 =========
VNC_USER="vncuser"
VNC_USER_PW="${VNC_USER_PASSWORD:-$1}"
VNC_PASS="${VNC_PASSWORD:-$2}"
NGROK_AUTH_TOKEN_VAL="${NGROK_AUTH_TOKEN:-$3}"

# ========= Spotlight 無効化 =========
sudo mdutil -i off -a

# ========= ユーザー作成（Secure Token 付与） =========
sudo sysadminctl -addUser "${VNC_USER}" -password "${VNC_USER_PW}" -admin || true
sudo sysadminctl -resetPasswordFor "${VNC_USER}" -newPassword "${VNC_USER_PW}" || true
sudo sysadminctl -secureTokenStatus "${VNC_USER}" || true

# ========= VNC 有効化 =========
KICK="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
sudo "$KICK" -configure -allowAccessFor -allUsers -privs -all
sudo "$KICK" -configure -clientopts -setvnclegacy -vnclegacy yes

# ========= VNC パスワード設定 =========
echo "${VNC_PASS}" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' \
| sudo tee /Library/Preferences/com.apple.VNCSettings.txt

# ========= VNC 再起動 =========
sudo "$KICK" -restart -agent -console
sudo "$KICK" -activate

# ========= TCC 権限リセット（黒画面・許可ダイアログ抑止） =========
sudo tccutil reset ScreenCapture || true
sudo tccutil reset SystemPolicyNetworkVolumes || true

# ========= ngrok インストール =========
if ! command -v ngrok >/dev/null 2>&1; then
  brew install --cask ngrok || brew install ngrok/ngrok/ngrok
fi

# ========= ngrok 起動 =========
ngrok authtoken "${NGROK_AUTH_TOKEN_VAL}"
ngrok tcp 5900 &

# ========= 接続情報表示 =========
sleep 3
if command -v curl >/dev/null 2>&1; then
  echo "===== ngrok TCP endpoint ====="
  curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*' | sed 's/"public_url":"//'
fi

echo "==============================="
echo "VNC 接続ユーザー名: ${VNC_USER}"
