#!/usr/bin/env bash
set -euo pipefail

# ========= 入力 =========
VNC_USER="vncuser"
VNC_USER_PW="${VNC_USER_PASSWORD:-${1:-}}"
VNC_PASS="${VNC_PASSWORD:-${2:-}}"
NGROK_AUTH_TOKEN_VAL="${NGROK_AUTH_TOKEN:-${3:-}}"

# ========= デバッグ出力（長さのみ表示） =========
echo "[DEBUG] VNC_USER_PASSWORD length: ${#VNC_USER_PW}"
echo "[DEBUG] VNC_PASSWORD length: ${#VNC_PASS}"
echo "[DEBUG] NGROK_AUTH_TOKEN length: ${#NGROK_AUTH_TOKEN_VAL}"

# ========= バリデーション =========
if [[ -z "${VNC_USER_PW}" || -z "${VNC_PASS}" || -z "${NGROK_AUTH_TOKEN_VAL}" ]]; then
  echo "[ERROR] 必須の値が空です" >&2
  exit 1
fi

# …この後は既存処理を続行…


# ========= Spotlight 無効化 =========
sudo mdutil -i off -a || true

# ========= ユーザー作成（Secure Tokenは警告に留める） =========
echo "[INFO] Create admin user: ${VNC_USER}"
if ! id -u "${VNC_USER}" >/dev/null 2>&1; then
  sudo sysadminctl -addUser "${VNC_USER}" -password "${VNC_USER_PW}" -admin || true
fi
sudo sysadminctl -resetPasswordFor "${VNC_USER}" -newPassword "${VNC_USER_PW}" || true
sudo sysadminctl -secureTokenStatus "${VNC_USER}" || true

# ========= VNC 有効化 =========
KICK="/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
sudo "$KICK" -configure -allowAccessFor -allUsers -privs -all
sudo "$KICK" -configure -clientopts -setvnclegacy -vnclegacy yes

# ========= VNC パスワード設定（レガシー互換） =========
echo "${VNC_PASS}" | perl -we 'BEGIN { @k = unpack "C*", pack "H*", "1734516E8BA8C5E2FF1C39567390ADCA"}; $_ = <>; chomp; s/^(.{8}).*/$1/; @p = unpack "C*", $_; foreach (@k) { printf "%02X", $_ ^ (shift @p || 0) }; print "\n"' \
| sudo tee /Library/Preferences/com.apple.VNCSettings.txt >/dev/null

# ========= VNC 再起動 =========
sudo "$KICK" -restart -agent -console
sudo "$KICK" -activate

# ========= TCC 権限リセット =========
sudo tccutil reset ScreenCapture || true
sudo tccutil reset SystemPolicyNetworkVolumes || true

# ========= ngrok インストール =========
if ! command -v ngrok >/dev/null 2>&1; then
  brew install --cask ngrok || brew install ngrok/ngrok/ngrok
fi

# ========= ngrok 設定（厳格チェック） =========
echo "[INFO] Configure ngrok authtoken"
set +e
ngrok config add-authtoken "${NGROK_AUTH_TOKEN_VAL}"
NGROK_RC=$?
set -e
if [[ $NGROK_RC -ne 0 ]]; then
  echo "[ERROR] ngrok authtoken 設定に失敗（形式不正または空の可能性: ERR_NGROK_105 など）。ダッシュボードのトークンを再確認してください。" >&2
  exit 1
fi

# ========= ngrok 起動 =========
echo "[INFO] Start ngrok tcp 5900"
nohup ngrok tcp 5900 >/tmp/ngrok.log 2>&1 &
sleep 3

# ========= 接続情報表示 =========
if command -v curl >/dev/null 2>&1; then
  echo "===== ngrok TCP endpoint ====="
  if ! curl -fsS http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*' | sed 's/"public_url":"//'; then
    echo "[WARN] ngrok のエンドポイント取得に失敗。/tmp/ngrok.log を確認してください。" >&2
    echo "------ /tmp/ngrok.log (tail) ------"
    tail -n 50 /tmp/ngrok.log || true
  fi
fi

echo "==============================="
echo "VNC 接続ユーザー名: ${VNC_USER}"
echo "VNC 接続パスワード: ${VNC_USER_PW}"
