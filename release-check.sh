#!/usr/bin/env bash
# One-command release check for a freeforgood-apps web app.
# Runs, in order: versions agree, privacy lock up to date, self-test at 3 sizes,
# accessibility check, and the security search patterns on everything changed since the last tag.
# Prints one PASS / FAIL / REVIEW / SKIP line per check, short details only for problems,
# and keeps the full output in a log folder.
#
# Usage: bash /tmp/toolkit/release-check.sh [app folder] [extra page ...]
#   app folder  defaults to the current folder (an app repo with index.html at the top)
#   extra page  more pages for the accessibility check, e.g. "index.html#plan" (index.html is always checked)
# Exits 0 when nothing failed (leads marked REVIEW still need a look), 1 when anything failed.
set -uo pipefail

TK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(cd "${1:-.}" && pwd)" || { echo "No such folder: ${1:-.}"; exit 1; }
shift || true
EXTRA_PAGES=("$@")
LOGS="$(mktemp -d /tmp/release-check.XXXXXX)"
CHROME="${CHROME:-/usr/bin/google-chrome}"
export CHROME

[ -f "$APP/index.html" ] || { echo "No index.html in $APP"; exit 1; }
[ -d "$TK/node_modules/puppeteer-core" ] || { echo "Toolkit not set up. Run: (cd $TK && npm ci --ignore-scripts --silent)"; exit 1; }

FAILS=0; REVIEWS=0
line() { printf '%-7s %s\n' "$1" "$2"; }
pass() { line PASS "$1"; }
fail() { line FAIL "$1"; FAILS=$((FAILS + 1)); [ -n "${2:-}" ] && sed 's/^/        /' <<<"$2"; }
skip() { line SKIP "$1"; }

# ---- 1. Versions agree -------------------------------------------------------
VERSION="$(grep -oE 'APP_VERSION *= *"[^"]+"' "$APP/index.html" | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
NAME="$(basename "$APP")"
echo "Release check: $NAME ${VERSION:-(no APP_VERSION)}"
echo "Full output: $LOGS"
echo
if [ -z "$VERSION" ]; then
  fail "versions: no APP_VERSION = \"X.Y.Z\" in index.html"
else
  bad=""
  if [ -f "$APP/sw.js" ]; then grep -q -- "-$VERSION\"" "$APP/sw.js" || bad+="sw.js cache name isn't *-$VERSION"$'\n'; fi
  if [ -f "$APP/selftest.html" ]; then
    st="$(grep -oE 'APP_VERSION *= *"[^"]+"' "$APP/selftest.html" | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
    [ "$st" = "$VERSION" ] || bad+="selftest.html says ${st:-nothing} (rebuild it)"$'\n'
  fi
  if [ -f "$APP/CHANGELOG.md" ]; then
    top="$(grep -m1 -E '^## ' "$APP/CHANGELOG.md" | sed -E 's/^## +v?([^ ]+).*/\1/')"
    [ "$top" = "$VERSION" ] || bad+="CHANGELOG.md's newest entry is ${top:-missing}"$'\n'
  fi
  if [ -z "$bad" ]; then pass "versions agree ($VERSION)"; else fail "versions don't agree with $VERSION" "${bad%$'\n'}"; fi
fi

# ---- 2. Privacy lock up to date ----------------------------------------------
LOCKED=()
for f in "$APP"/*.html; do grep -q "Content-Security-Policy" "$f" && grep -q "sha256-" "$f" && LOCKED+=("$f"); done
if [ ${#LOCKED[@]} -eq 0 ]; then
  fail "privacy lock: no page has a CSP with script fingerprints"
elif python3 -I "$TK/lock.py" --check "${LOCKED[@]}" >"$LOGS/lock.txt" 2>&1; then
  pass "privacy lock up to date ($(for f in "${LOCKED[@]}"; do basename "$f"; done | paste -sd, - | sed 's/,/, /g'))"
else
  fail "privacy lock out of date (run lock.py or the rebuild step)" "$(grep -v 'up to date' "$LOGS/lock.txt" | sed "s#$APP/##")"
fi

# ---- Local server for the browser checks -------------------------------------
if [ ! -x "$CHROME" ]; then
  skip "self-test: no Chrome at $CHROME (set CHROME), so it wasn't run"
  skip "accessibility: no Chrome, so it wasn't run"
else
  PORT="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  python3 -I -m http.server "$PORT" --bind 127.0.0.1 -d "$APP" >"$LOGS/server.txt" 2>&1 &
  SERVER=$!
  trap 'kill $SERVER 2>/dev/null' EXIT
  for _ in $(seq 50); do python3 -I -c "import urllib.request as u; u.urlopen('http://127.0.0.1:$PORT/index.html')" 2>/dev/null && break; sleep 0.1; done
  BASE="http://127.0.0.1:$PORT"

  # ---- 3. Self-test at three sizes -------------------------------------------
  if [ ! -f "$APP/selftest.html" ]; then
    skip "self-test: no selftest.html"
  elif node "$TK/selftest-runner.mjs" "$BASE/selftest.html" >"$LOGS/selftest.txt" 2>&1; then
    checks="$(grep -m1 -oE '[0-9]+ (checks|passed)' "$LOGS/selftest.txt" || true)"
    pass "self-test passed at 3 sizes${checks:+ ($checks each)}"
  else
    fail "self-test" "$(grep -E 'FAILED|issue:|page errors|Error' "$LOGS/selftest.txt" | head -12)"
  fi

  # ---- 4. Accessibility ------------------------------------------------------
  PAGES=("$BASE/index.html")
  for p in "${EXTRA_PAGES[@]+"${EXTRA_PAGES[@]}"}"; do PAGES+=("$BASE/${p#/}"); done
  if node "$TK/a11y-check.mjs" "${PAGES[@]}" >"$LOGS/a11y.txt" 2>&1; then
    pass "accessibility: nothing found on ${#PAGES[@]} page(s), 4 sizes, light and dark"
  else
    # One line per problem: the same tap-target or input problem at every size is listed once
    fail "accessibility" "$( { grep -E '^===|^- \[|^Errors' "$LOGS/a11y.txt"
      grep -E 'tap target|under 16px|zoom is blocked|scrolls sideways' "$LOGS/a11y.txt" | sed -E 's/^[^:]+: //' | sort -u | sed 's/^/(some sizes) /'; } | sed "s#$BASE/##" | head -15)"
  fi
fi

# ---- 5. Security search patterns on what changed since the last tag ----------
cd "$APP" || exit 1
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [ "$(git rev-parse --is-shallow-repository)" = "true" ] && git fetch -q --unshallow --tags 2>/dev/null
  git fetch -q --tags 2>/dev/null
  SINCE="$(git tag --sort=-v:refname | grep -vx "v$VERSION" | head -1)"
  {
    if [ -n "$SINCE" ]; then git diff --no-color -U0 "$SINCE" -- . | grep -E '^\+' | grep -vE '^\+\+\+ '
    else git ls-files -z | xargs -0 grep -IhE '' 2>/dev/null; fi
    git ls-files --others --exclude-standard -z | xargs -0 -r grep -IhE '' 2>/dev/null
  } >"$LOGS/changed-lines.txt"
  SCOPE="${SINCE:+since $SINCE}"; SCOPE="${SCOPE:-whole repo (no earlier tag)}"
else
  find . -type f -not -path './node_modules/*' -print0 | xargs -0 grep -IhE '' 2>/dev/null >"$LOGS/changed-lines.txt"
  SCOPE="whole folder (not a git repo)"
fi
# Lines over 2000 characters are embedded fonts or images; skip them so base64 can't look like a key
awk 'length($0) <= 2000' "$LOGS/changed-lines.txt" | grep -nEf "$TK/patterns.txt" >"$LOGS/leads.txt"
LEADS="$(wc -l <"$LOGS/leads.txt" | tr -d ' ')"
if [ "$LEADS" -eq 0 ]; then
  pass "security patterns: no leads in changes $SCOPE"
else
  line REVIEW "security patterns: $LEADS lead(s) in changes $SCOPE. A lead isn't a finding until someone looks."
  REVIEWS=$((REVIEWS + 1))
  cut -d: -f2- "$LOGS/leads.txt" | sed -E 's/^[+ \t]+//' | cut -c1-140 | sort -u | head -15 | sed 's/^/        /'
  [ "$LEADS" -gt 15 ] && echo "        (all of them: $LOGS/leads.txt)"
fi

# ---- Summary -----------------------------------------------------------------
echo
if [ "$FAILS" -gt 0 ]; then echo "RESULT: FAILED ($FAILS check(s))"; exit 1
elif [ "$REVIEWS" -gt 0 ]; then echo "RESULT: PASSED, with leads to review"; exit 0
else echo "RESULT: ALL PASSED"; exit 0; fi
