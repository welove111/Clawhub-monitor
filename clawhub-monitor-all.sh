#!/data/data/com.termux/files/usr/bin/bash
# ==============================================================
# clawhub-monitor-all.sh — tracks ALL your ClawHub skills:
#   - downloads, installs (current/all-time), stars
#   - moderation/scan verdict (clean / suspicious / malware)
#   - version changes / new releases
# Runs every 3 hours via cron. Sends ONE consolidated WhatsApp
# message only if something actually changed since last run.
# ==============================================================

set -u

# ---- CONFIG: add/remove your skill slugs here -----------------
SLUGS=(
  "btcvision-oracle"
  "proof-of-contribution"
  "btc-apocalypse-oracle"
  "triskill"
  "btcvision-donation-nudge"
  "btcvision-alert"
  "btcvision-daily-brief"
  "skill-doctor"
  # ClawHub CLI supports an --owner/--ref flag on `inspect`.
)

# ---- CONFIG: add/remove your published plugin names here -------
# Plugins use `clawhub package inspect` (not `clawhub inspect`) and
# a different stats/verdict shape than skills.
PLUGINS=(
  "@welove111/openclaw-btcvision-all-in-one"
)

STATE_DIR="$HOME/.clawhub-monitor"
mkdir -p "$STATE_DIR"
NOW=$(date '+%Y-%m-%d %H:%M GMT')

# --- pull in WA_INSTANCE / WA_TOKEN / WA_GROUP and the send_wa()
# function from your existing monitor script, so credentials live
# in exactly one place.
EXISTING_MONITOR="$HOME/clawhub-monitor.sh"
if [ -f "$EXISTING_MONITOR" ]; then
  # extract only variable assignments + the send_wa function body,
  # rather than running the whole old script's logic
  WA_INSTANCE=$(grep -m1 '^WA_INSTANCE=' "$EXISTING_MONITOR" | cut -d= -f2- | tr -d '"')
  WA_TOKEN=$(grep -m1 '^WA_TOKEN='    "$EXISTING_MONITOR" | cut -d= -f2- | tr -d '"')
  WA_GROUP=$(grep -m1 '^WA_GROUP='    "$EXISTING_MONITOR" | cut -d= -f2- | tr -d '"')
fi

if [ -z "${WA_INSTANCE:-}" ] || [ -z "${WA_TOKEN:-}" ] || [ -z "${WA_GROUP:-}" ]; then
  echo "❌ Could not load WA_INSTANCE/WA_TOKEN/WA_GROUP from $EXISTING_MONITOR — aborting."
  exit 1
fi

send_wa() {
  local msg="$1"
  curl -s -X POST "https://api.ultramsg.com/${WA_INSTANCE}/messages/chat" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "token=${WA_TOKEN}" \
    --data-urlencode "to=${WA_GROUP}" \
    --data-urlencode "body=${msg}" > /dev/null
}

CHANGES=""   # accumulates human-readable change lines
ANY_CHANGE=0

for SLUG in "${SLUGS[@]}"; do
  STATE_FILE="$STATE_DIR/${SLUG}.state"
  JSON=$(clawhub inspect "$SLUG" --json 2>/dev/null)

  if [ -z "$JSON" ]; then
    echo "⚠️  Could not fetch $SLUG, skipping"
    continue
  fi

  DOWNLOADS=$(echo "$JSON"  | grep -o '"downloads": *[0-9]*'       | head -1 | grep -o '[0-9]*$')
  INSTALLS_ALL=$(echo "$JSON" | grep -o '"installsAllTime": *[0-9]*' | head -1 | grep -o '[0-9]*$')
  INSTALLS_CUR=$(echo "$JSON" | grep -o '"installsCurrent": *[0-9]*' | head -1 | grep -o '[0-9]*$')
  STARS=$(echo "$JSON" | grep -o '"stars": *[0-9]*' | head -1 | grep -o '[0-9]*$')
  VERDICT=$(echo "$JSON" | grep -o '"verdict": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
  IS_SUSPICIOUS=$(echo "$JSON" | grep -o '"isSuspicious": *[a-z]*' | head -1 | sed 's/.*: *//')
  IS_MALWARE=$(echo "$JSON" | grep -o '"isMalwareBlocked": *[a-z]*' | head -1 | sed 's/.*: *//')
  VERSION=$(echo "$JSON" | grep -o '"version": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
  DISPLAY_NAME=$(echo "$JSON" | grep -o '"displayName": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')

  DOWNLOADS=${DOWNLOADS:-0}
  INSTALLS_ALL=${INSTALLS_ALL:-0}
  INSTALLS_CUR=${INSTALLS_CUR:-0}
  STARS=${STARS:-0}
  VERDICT=${VERDICT:-unknown}
  VERSION=${VERSION:-unknown}
  DISPLAY_NAME=${DISPLAY_NAME:-$SLUG}

  # --- load previous state ---
  OLD_DOWNLOADS=0; OLD_INSTALLS_ALL=0; OLD_INSTALLS_CUR=0; OLD_STARS=0
  OLD_VERDICT=""; OLD_VERSION=""
  [ -f "$STATE_FILE" ] && source "$STATE_FILE"

  SKILL_CHANGES=""

  if [ "$DOWNLOADS" -gt "$OLD_DOWNLOADS" ] 2>/dev/null; then
    DIFF=$((DOWNLOADS - OLD_DOWNLOADS))
    SKILL_CHANGES="${SKILL_CHANGES}\n  📥 Downloads: ${OLD_DOWNLOADS} → ${DOWNLOADS} (+${DIFF})"
  fi

  if [ "$INSTALLS_ALL" -gt "$OLD_INSTALLS_ALL" ] 2>/dev/null; then
    DIFF=$((INSTALLS_ALL - OLD_INSTALLS_ALL))
    SKILL_CHANGES="${SKILL_CHANGES}\n  ⬇️ Installs (all-time): ${OLD_INSTALLS_ALL} → ${INSTALLS_ALL} (+${DIFF})"
  fi

  if [ "$INSTALLS_CUR" != "$OLD_INSTALLS_CUR" ] 2>/dev/null; then
    SKILL_CHANGES="${SKILL_CHANGES}\n  📊 Active installs: ${OLD_INSTALLS_CUR} → ${INSTALLS_CUR}"
  fi

  if [ "$STARS" -gt "$OLD_STARS" ] 2>/dev/null; then
    DIFF=$((STARS - OLD_STARS))
    SKILL_CHANGES="${SKILL_CHANGES}\n  ⭐ Stars: ${OLD_STARS} → ${STARS} (+${DIFF})"
  fi

  if [ -n "$OLD_VERDICT" ] && [ "$VERDICT" != "$OLD_VERDICT" ]; then
    if [ "$VERDICT" = "clean" ]; then
      ICON="✅"
    elif [ "$IS_MALWARE" = "true" ]; then
      ICON="🛑"
    elif [ "$IS_SUSPICIOUS" = "true" ]; then
      ICON="⚠️"
    else
      ICON="ℹ️"
    fi
    SKILL_CHANGES="${SKILL_CHANGES}\n  ${ICON} Review verdict changed: ${OLD_VERDICT:-pending} → ${VERDICT}"
  elif [ -z "$OLD_VERDICT" ]; then
    # first time we see this skill — report current verdict once
    if [ "$VERDICT" = "clean" ]; then
      SKILL_CHANGES="${SKILL_CHANGES}\n  ✅ Review: ${VERDICT}"
    fi
  fi

  if [ -n "$OLD_VERSION" ] && [ "$VERSION" != "$OLD_VERSION" ]; then
    SKILL_CHANGES="${SKILL_CHANGES}\n  🚀 New version published: ${OLD_VERSION} → ${VERSION}"
  fi

  if [ -n "$SKILL_CHANGES" ]; then
    ANY_CHANGE=1
    CHANGES="${CHANGES}\n*${DISPLAY_NAME}* (${SLUG})${SKILL_CHANGES}\n"
  fi

  # --- save new state ---
  cat > "$STATE_FILE" << EOF
OLD_DOWNLOADS=${DOWNLOADS}
OLD_INSTALLS_ALL=${INSTALLS_ALL}
OLD_INSTALLS_CUR=${INSTALLS_CUR}
OLD_STARS=${STARS}
OLD_VERDICT="${VERDICT}"
OLD_VERSION="${VERSION}"
EOF

done

# ================== PLUGINS ==================
for PKG in "${PLUGINS[@]}"; do
  # use a filesystem-safe key for the state filename (strip @ and /)
  SAFE_KEY=$(echo "$PKG" | tr '@/' '_')
  STATE_FILE="$STATE_DIR/plugin-${SAFE_KEY}.state"

  JSON=$(clawhub package inspect "$PKG" --json 2>/dev/null)
  if [ -z "$JSON" ]; then
    echo "⚠️  Could not fetch plugin $PKG, skipping"
    continue
  fi

  DOWNLOADS=$(echo "$JSON" | grep -o '"downloads": *[0-9]*' | head -1 | grep -o '[0-9]*$')
  INSTALLS=$(echo "$JSON"  | grep -o '"installs": *[0-9]*'  | head -1 | grep -o '[0-9]*$')
  STARS=$(echo "$JSON"     | grep -o '"stars": *[0-9]*'     | head -1 | grep -o '[0-9]*$')
  SCAN_STATUS=$(echo "$JSON" | grep -o '"scanStatus": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
  VERSION=$(echo "$JSON"   | grep -o '"latestVersion": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')
  DISPLAY_NAME=$(echo "$JSON" | grep -o '"displayName": *"[^"]*"' | head -1 | sed 's/.*: *"//;s/"$//')

  DOWNLOADS=${DOWNLOADS:-0}
  INSTALLS=${INSTALLS:-0}
  STARS=${STARS:-0}
  SCAN_STATUS=${SCAN_STATUS:-unknown}
  VERSION=${VERSION:-unknown}
  DISPLAY_NAME=${DISPLAY_NAME:-$PKG}

  OLD_DOWNLOADS=0; OLD_INSTALLS=0; OLD_STARS=0
  OLD_SCAN_STATUS=""; OLD_VERSION=""
  [ -f "$STATE_FILE" ] && source "$STATE_FILE"

  PKG_CHANGES=""

  if [ "$DOWNLOADS" -gt "$OLD_DOWNLOADS" ] 2>/dev/null; then
    DIFF=$((DOWNLOADS - OLD_DOWNLOADS))
    PKG_CHANGES="${PKG_CHANGES}\n  📥 Downloads: ${OLD_DOWNLOADS} → ${DOWNLOADS} (+${DIFF})"
  fi

  if [ "$INSTALLS" -gt "$OLD_INSTALLS" ] 2>/dev/null; then
    DIFF=$((INSTALLS - OLD_INSTALLS))
    PKG_CHANGES="${PKG_CHANGES}\n  ⬇️ Installs: ${OLD_INSTALLS} → ${INSTALLS} (+${DIFF})"
  fi

  if [ "$STARS" -gt "$OLD_STARS" ] 2>/dev/null; then
    DIFF=$((STARS - OLD_STARS))
    PKG_CHANGES="${PKG_CHANGES}\n  ⭐ Stars: ${OLD_STARS} → ${STARS} (+${DIFF})"
  fi

  if [ -n "$OLD_SCAN_STATUS" ] && [ "$SCAN_STATUS" != "$OLD_SCAN_STATUS" ]; then
    if [ "$SCAN_STATUS" = "clean" ] || [ "$SCAN_STATUS" = "passed" ]; then
      ICON="✅"
    elif [ "$SCAN_STATUS" = "pending" ]; then
      ICON="⏳"
    else
      ICON="⚠️"
    fi
    PKG_CHANGES="${PKG_CHANGES}\n  ${ICON} Scan status changed: ${OLD_SCAN_STATUS} → ${SCAN_STATUS}"
  elif [ -z "$OLD_SCAN_STATUS" ]; then
    PKG_CHANGES="${PKG_CHANGES}\n  ⏳ Scan status: ${SCAN_STATUS}"
  fi

  if [ -n "$OLD_VERSION" ] && [ "$VERSION" != "$OLD_VERSION" ]; then
    PKG_CHANGES="${PKG_CHANGES}\n  🚀 New version published: ${OLD_VERSION} → ${VERSION}"
  fi

  if [ -n "$PKG_CHANGES" ]; then
    ANY_CHANGE=1
    CHANGES="${CHANGES}\n*${DISPLAY_NAME}* (plugin)${PKG_CHANGES}\n"
  fi

  cat > "$STATE_FILE" << EOF
OLD_DOWNLOADS=${DOWNLOADS}
OLD_INSTALLS=${INSTALLS}
OLD_STARS=${STARS}
OLD_SCAN_STATUS="${SCAN_STATUS}"
OLD_VERSION="${VERSION}"
EOF

done

if [ "$ANY_CHANGE" -eq 1 ]; then
  MSG="🦞 *ClawHub — Update*\n${CHANGES}\n🕐 ${NOW}"
  send_wa "$MSG"
  echo "📱 Sent consolidated update WhatsApp alert"
else
  echo "✅ Check complete — no changes across ${#SLUGS[@]} skills + ${#PLUGINS[@]} plugins (${NOW})"
fi

# كل ساعتين - تقرير شامل
HOUR=$(date +"%H" | sed "s/^0//")
if [ $((HOUR % 2)) -eq 0 ]; then
  REPORT="🦞 *ClawHub Report*
🕐 ${NOW}
━━━━━━━━━━━━━━━
📦 *Skills (${#SLUGS[@]}):*"

  for SLUG in "${SLUGS[@]}"; do
    STATE_FILE="$STATE_DIR/${SLUG}.state"
    if [ -f "$STATE_FILE" ]; then
      source "$STATE_FILE"
      ICON="✅"
      [ "$OLD_SCAN_STATUS" = "pending" ] && ICON="⏳"
      [ "$OLD_SCAN_STATUS" = "review" ] && ICON="⚠️"
      [ "$OLD_SCAN_STATUS" = "suspicious" ] && ICON="🔴"
      [ "$OLD_SCAN_STATUS" = "malware" ] && ICON="🚨"
      REPORT="${REPORT}
• ${SLUG} — ${ICON} ${OLD_SCAN_STATUS} — ${OLD_DOWNLOADS} ⬇️ installs"
    fi
  done

  REPORT="${REPORT}
━━━━━━━━━━━━━━━"
  send_wa "$REPORT"
  echo "📱 Sent full report"
fi
