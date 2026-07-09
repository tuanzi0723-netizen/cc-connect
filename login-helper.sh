#!/usr/bin/env bash
# Claude Code login helper for headless VPS setups (VNC-friendly).
#
#   bash l.sh        start the login flow; publishes the OAuth URL as a short link
#   bash l.sh save   after the flow finishes, wire the token into cc-connect's config
#
# Why: the OAuth login URL is ~300 chars and can't be copied out of a VNC
# console. This runs `claude setup-token` inside tmux, captures the URL,
# and posts it to a paste service so it can be opened on another device
# via a short link.
set -u
LOG=/tmp/clogin.log
SESSION=clogin
CFG=/root/.cc-connect/config.toml

strip_ansi() { sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

case "${1:-start}" in
start)
  export DEBIAN_FRONTEND=noninteractive
  command -v tmux >/dev/null 2>&1 || apt-get install -y tmux >/dev/null 2>&1
  cd /root/work 2>/dev/null || cd /root
  tmux kill-session -t "$SESSION" 2>/dev/null
  rm -f "$LOG"
  tmux new-session -d -s "$SESSION" "claude setup-token 2>&1 | tee $LOG"
  echo "waiting for the login URL (up to 30s)..."
  URL=""
  for _ in $(seq 1 30); do
    URL=$(strip_ansi <"$LOG" 2>/dev/null | grep -aoE 'https://[^[:space:]]+' | grep -m1 oauth || true)
    [ -n "$URL" ] && break
    sleep 1
  done
  if [ -z "$URL" ]; then
    echo "no URL captured — the flow may be asking something first."
    echo "attach and check:  tmux attach -t $SESSION   (detach: Ctrl+B then D)"
    exit 1
  fi
  SHORT=$(printf '%s' "$URL" | curl -fsS --data-binary @- https://paste.rs 2>/dev/null | head -1)
  [ -n "$SHORT" ] || SHORT=$(printf '%s\n' "$URL" | timeout 10 nc termbin.com 9999 2>/dev/null | tr -d '\0')
  echo
  if [ -n "$SHORT" ]; then
    echo "1. On your PC/phone, open:   $SHORT"
    echo "   it shows the full login URL as text — copy it into the address bar"
  else
    echo "paste services unreachable; the full URL is:"
    echo "$URL"
  fi
  echo "2. Log in, authorize, and copy the authorization code"
  echo "3. Back here:   tmux attach -t $SESSION"
  echo "   type the code + Enter. When it says done, detach (Ctrl+B then D)"
  echo "   and run:     bash l.sh save"
  ;;
save)
  TOKEN=$(strip_ansi <"$LOG" 2>/dev/null | grep -aoE 'sk-ant-oat[0-9]*-[A-Za-z0-9_-]+' | tail -1)
  if [ -z "$TOKEN" ]; then
    echo "no token found in $LOG — did setup-token finish?"
    echo "check with:  tmux attach -t $SESSION"
    exit 1
  fi
  if grep -q CLAUDE_CODE_OAUTH_TOKEN "$CFG" 2>/dev/null; then
    sed -i "s|^CLAUDE_CODE_OAUTH_TOKEN.*|CLAUDE_CODE_OAUTH_TOKEN = \"$TOKEN\"|" "$CFG"
    echo "replaced existing token in $CFG"
  else
    printf '\n[projects.agent.options.env]\nCLAUDE_CODE_OAUTH_TOKEN = "%s"\n' "$TOKEN" >>"$CFG"
    echo "token appended to $CFG"
  fi
  tmux kill-session -t "$SESSION" 2>/dev/null
  echo "all set — now run:  cc-connect"
  ;;
*)
  echo "usage: bash l.sh [start|save]"
  exit 1
  ;;
esac
