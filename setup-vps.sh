#!/usr/bin/env bash
# cc-connect VPS one-shot setup (Ubuntu 22.04/24.04, run as root)
# Installs: swap, Node.js 22, Claude Code CLI, cc-connect, and writes a
# starter config (claudecode agent + telegram platform).
#
# Usage:
#   curl -fsSL <raw-url>/scripts/setup-vps.sh -o s.sh
#   bash s.sh
set -uo pipefail

step() { echo; echo "==> $*"; }
die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "please run as root"

export DEBIAN_FRONTEND=noninteractive

step "[1/6] System packages"
apt-get update -y || die "apt update failed"
apt-get install -y curl git ca-certificates gnupg >/dev/null || die "apt install failed"

step "[2/6] Swap (2G, skip if any swap exists)"
if swapon --show | grep -q .; then
  echo "swap already present, skipping"
else
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile \
    && echo '/swapfile none swap sw 0 0' >> /etc/fstab \
    && echo "2G swap enabled" || echo "WARN: swap setup failed (non-fatal), continuing"
fi

step "[3/6] Node.js 22"
if command -v node >/dev/null 2>&1 && node -e 'process.exit(+process.versions.node.split(".")[0] >= 20 ? 0 : 1)'; then
  echo "node $(node -v) already installed, skipping"
else
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || die "nodesource setup failed"
  apt-get install -y nodejs || die "nodejs install failed"
fi
echo "node: $(node -v), npm: $(npm -v)"

step "[4/6] Claude Code CLI + cc-connect"
npm install -g @anthropic-ai/claude-code cc-connect || die "npm install failed"
echo "claude: $(claude --version 2>/dev/null || echo 'installed (version check skipped)')"
echo "cc-connect: $(cc-connect --version 2>/dev/null || echo 'installed (version check skipped)')"

step "[5/6] Config"
mkdir -p /root/work /root/.cc-connect
CFG=/root/.cc-connect/config.toml
if [ -f "$CFG" ]; then
  echo "$CFG already exists, leaving it untouched"
else
  # Prompts are skippable: just press Enter and edit the file later.
  echo "Telegram bot token (from @BotFather), or press Enter to fill in later:"
  read -r TG_TOKEN </dev/tty || TG_TOKEN=""
  echo "Your Telegram user ID (from @userinfobot), or press Enter to allow everyone (NOT recommended):"
  read -r TG_UID </dev/tty || TG_UID=""
  [ -n "$TG_TOKEN" ] || TG_TOKEN="PUT-YOUR-BOT-TOKEN-HERE"
  [ -n "$TG_UID" ] || TG_UID="*"

  cat > "$CFG" <<EOF
[[projects]]
name = "vps"

[projects.agent]
type = "claudecode"

[projects.agent.options]
work_dir = "/root/work"
mode = "auto" # "default" | "acceptEdits" | "plan" | "auto" | "bypassPermissions"

[[projects.platforms]]
type = "telegram"

[projects.platforms.options]
token = "$TG_TOKEN"
allow_from = "$TG_UID"
EOF
  echo "wrote $CFG"
fi

step "[6/6] Done — next steps"
cat <<'NEXT'
  1. Log in Claude Code:   run `claude` inside /root/work, follow the login URL
     (open the URL in any browser, paste the code back here)
  2. If you skipped the token prompts, edit /root/.cc-connect/config.toml
  3. Start the bridge:     cc-connect
  4. Message your bot on Telegram!
NEXT
