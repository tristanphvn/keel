#!/bin/bash
# Refresh the global qmd index: re-scan every collection, then embed new or changed docs.
# The scheduler, on-edit-hook.sh, and setup-qmd.sh call it. So can you, by hand.
# One run at a time. The lock is a symlink whose target is the holder's PID, made atomically.
# A caller that finds the lock held leaves a rerun flag. The holder loops while the flag
# reappears, so edits made during a long embed land in the same run.
set -uo pipefail
# launchd and hooks may not carry the user's env, so pin what setup found. qmd's launcher
# execs node or bun, so the dirs setup found them in go on PATH next to qmd's own.
unset QMD_CONFIG_DIR
export XDG_CONFIG_HOME={{XDG_CONFIG_HOME}} XDG_CACHE_HOME={{XDG_CACHE_HOME}}
QMD={{QMD_BINARY}}
RUNTIME_PATH={{RUNTIME_PATH}}
export PATH="$(dirname "$QMD")${RUNTIME_PATH:+:$RUNTIME_PATH}:$HOME/.bun/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
if [ "$(uname -s)" = Darwin ]; then
  LOG="$HOME/Library/Logs/qmd/reconcile.log"
else
  LOG="${XDG_STATE_HOME:-$HOME/.local/state}/qmd/reconcile.log"
fi
# Lock and flag live in a per-user dir, so every caller agrees whatever its TMPDIR is.
STATE="$(dirname "$LOG")"
LOCK="$STATE/reconcile.lnk"
RERUN="$STATE/reconcile.rerun"
mkdir -p "$STATE"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG"; }

acquire() {
  ln -s "$$" "$LOCK" 2>/dev/null && return 0
  local holder; holder=$(readlink "$LOCK" 2>/dev/null) || return 1
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    # The holder is dead. Rename the link aside (atomic) so only one reclaimer gets it. If the
    # moved link is not the dead holder's, put it back without replacing a newer one.
    mv -- "$LOCK" "$LOCK.$$" 2>/dev/null || return 1
    local moved; moved=$(readlink "$LOCK.$$" 2>/dev/null)
    rm -f -- "$LOCK.$$"
    if [ "$moved" != "$holder" ]; then
      ln -s "$moved" "$LOCK" 2>/dev/null
      return 1
    fi
    ln -s "$$" "$LOCK" 2>/dev/null && { log "reclaimed stale lock from pid $holder"; return 0; }
  fi
  return 1
}

if ! acquire; then
  touch "$RERUN"
  exit 0
fi
trap '[ "$(readlink "$LOCK" 2>/dev/null)" = "$$" ] && rm -f -- "$LOCK"' EXIT

[ -x "$QMD" ] || { log "ERROR: qmd not found at $QMD"; exit 1; }
log "start (${1:-manual})"
pass=0
while :; do
  rm -f -- "$RERUN"
  pass=$((pass + 1))
  if out=$(nice -n 15 "$QMD" update 2>&1); then
    log "update#$pass: $(printf '%s' "$out" | grep -E 'Indexed:' | awk '{n+=$2;u+=$4;r+=$8} END{print n+0" new, "u+0" updated, "r+0" removed"}')"
  else
    log "ERROR update: $(printf '%s' "$out" | tail -3 | paste -sd' ' -)"; exit 1
  fi
  if out=$(nice -n 15 "$QMD" embed 2>&1); then
    log "embed#$pass: $(printf '%s' "$out" | tr '\r' '\n' | grep -E 'Done|All content hashes|No non-empty|chunks failed|rror' | paste -sd' ' -)"
  else
    log "ERROR embed: $(printf '%s' "$out" | tr '\r' '\n' | tail -3 | paste -sd' ' -)"; exit 1
  fi
  [ -e "$RERUN" ] || break
  [ "$pass" -ge 5 ] && { log "stopping after $pass passes; rerun flag left for next run"; touch "$RERUN"; break; }
done
log "done"
