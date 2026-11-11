#!/usr/bin/env bash
# push-check: run it for every push, in every repo. With --push it also does the push, but only
# when every check passed, so a mistake gets caught instead of relying on care.
# Prints one PASS or FAIL line per check. Any FAIL blocks the push.
#
# Nothing about either side lives in this file: this side's orgs and the other side's words come
# in as arguments each time, so they're never saved anywhere.
#
# Usage:
#   bash /tmp/toolkit/push-check.sh --org ORG [--org ORG ...] --other WORD [--other WORD ...] [--push]
#        [-C folder] [--remote origin] [--branch name] [--committer "Name <email>"]
#
#   --org        an org or account this side pushes to. Repeat for each. The remote's owner must be one.
#   --other      a word that belongs to the other side: an org, account, domain, email or name.
#                Repeat for each. Matched in any case, with or without spaces, dots, hyphens or
#                underscores between its parts ("Some Org" also catches some-org and SomeOrg).
#   --push       push HEAD to the branch, only if every check passed
#   --all        for sweeps: check every commit in the history instead of just the new ones
#                (org, author, dates, Claude links and the other side's words). Changes nothing:
#                no fetch, no push, no hook. Bot commits are skipped in the author check.
#   -C           the repo folder (default: the current folder)
#   --remote     the remote to push to (default: origin)
#   --branch     the branch to push to (default: the current branch's name)
#   --committer  the committer every new commit must have (default: this folder's git config
#                user.name and user.email, the one git uses when nothing overrides it)
#
# Checks, on every commit that isn't on the remote yet:
#   org         the remote's owner is one of --org, and no --org name matches an --other word
#   remote      the remote branch has nothing this folder doesn't (nothing changed underneath)
#   author      same name and email as the latest pushed commit not made by a bot, and that's
#               a private GitHub noreply address
#   committer   the default committer, and signed, so GitHub shows the commit as Verified (not with --all)
#   dates       author and commit dates in UTC (+0000)
#   claude      no Claude links (chat, session, project, artifact or share links, or a Claude session line)
#   other side  none of the --other words in the added lines, file names, messages, authors or committers
#
# The first run in a folder also adds a small pre-push hook there (only if the folder has none), so a
# plain "git push" stops and says to use --push. The hook holds no words and isn't part of the repo.
#
# Exits 0 when every check passed (and the push worked, with --push), 1 when anything failed,
# 2 when the command itself is wrong. Written for bash 3.2 and up, so it also runs on a Mac.
set -uo pipefail

usage_error(){ echo "push-check: $*" >&2; echo "Run it with --help to see how to use it." >&2; exit 2; }
lower(){ printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

DIR="."; REMOTE="origin"; BRANCH=""; COMMITTER=""; PUSH="no"; ALL="no"
ORGS=(); OTHERS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --org)       [ -n "${2:-}" ] || usage_error "--org needs a name";        ORGS+=("$2"); shift 2 ;;
    --other)     [ -n "${2:-}" ] || usage_error "--other needs a word";      OTHERS+=("$2"); shift 2 ;;
    -C)          [ -n "${2:-}" ] || usage_error "-C needs a folder";         DIR="$2"; shift 2 ;;
    --remote)    [ -n "${2:-}" ] || usage_error "--remote needs a name";     REMOTE="$2"; shift 2 ;;
    --branch)    [ -n "${2:-}" ] || usage_error "--branch needs a name";     BRANCH="$2"; shift 2 ;;
    --committer) [ -n "${2:-}" ] || usage_error "--committer needs \"Name <email>\""; COMMITTER="$2"; shift 2 ;;
    --push)      PUSH="yes"; shift ;;
    --all)       ALL="yes"; shift ;;
    -h|--help)   sed -n '2,/^set -uo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           usage_error "unknown option: $1" ;;
  esac
done
[ "${#ORGS[@]}" -gt 0 ]   || usage_error "give at least one --org (an org or account this side pushes to)"
[ "${#OTHERS[@]}" -gt 0 ] || usage_error "give at least one --other (a word from the other side)"
[ "$PUSH" = "yes" ] && [ "$ALL" = "yes" ] && usage_error "--all only checks, so it can't be used with --push"

# A word becomes a pattern: its letter and number parts, in order, with up to 3 other characters
# between them. "Some Org" -> some[^[:alnum:]]{0,3}org, which also catches Some-Org and SomeOrg.
word_re(){
  local parts
  parts=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | sed 's/^ *//; s/ *$//')
  printf '%s' "$parts" | sed 's/ /[^[:alnum:]]{0,3}/g'
}
RES=()
for w in "${OTHERS[@]}"; do
  letters=$(printf '%s' "$w" | tr -cd '[:alnum:]')
  [ "${#letters}" -ge 3 ] || usage_error "--other \"$w\" is too short to search for safely (3 letters or numbers at least)"
  RES+=("$(word_re "$w")")
done
for o in "${ORGS[@]}"; do
  i=0
  while [ "$i" -lt "${#RES[@]}" ]; do
    if printf '%s\n' "$o" | grep -Eiq -- "${RES[$i]}"; then
      usage_error "\"$o\" is given as this side's --org but matches the other side's word \"${OTHERS[$i]}\". Check which side this is."
    fi
    i=$((i + 1))
  done
done

cd "$DIR" 2>/dev/null || usage_error "no such folder: $DIR"
git rev-parse --git-dir >/dev/null 2>&1 || usage_error "not a git repo: $DIR"
URL=$(git config --get "remote.$REMOTE.url") || usage_error "this repo has no remote called $REMOTE"
if [ -z "$BRANCH" ] && [ "$ALL" = "no" ]; then
  BRANCH=$(git symbolic-ref -q --short HEAD) || usage_error "not on a branch, so give --branch"
fi

FAILS=0
TAB=$(printf '\t')
CORPUS=$(mktemp "${TMPDIR:-/tmp}/push-check.XXXXXX")
trap 'rm -f "$CORPUS"' EXIT
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*"; FAILS=$((FAILS + 1)); }
detail(){ printf '        %s\n' "$*"; }
finish(){
  if [ "$FAILS" -gt 0 ]; then
    echo "push-check: FAIL ($FAILS). Don't push: fix each FAIL, then run it again."
    exit 1
  fi
  echo "push-check: PASS"
  exit 0
}

# The guard hook: a plain "git push" from this folder stops; push-check --push gets through.
HOOK="$(git rev-parse --git-path hooks)/pre-push"
if [ "$ALL" = "yes" ]; then
  :   # sweeps change nothing
elif [ ! -e "$HOOK" ]; then
  mkdir -p "$(dirname "$HOOK")"
  cat > "$HOOK" <<'GUARD'
#!/bin/sh
# push-check guard: pushes from this folder go through push-check.sh --push, which runs the
# checks first. A plain git push stops here.
while read -r lref lsha rref rsha; do
  if [ -z "${PUSH_CHECK_PASSED:-}" ] || [ "$lsha" != "$PUSH_CHECK_PASSED" ]; then
    echo "Blocked: push with push-check.sh --push, so the checks run first." >&2
    exit 1
  fi
done
exit 0
GUARD
  chmod +x "$HOOK"
elif ! grep -q 'push-check guard' "$HOOK" 2>/dev/null; then
  echo "note: this folder already has its own pre-push hook, so the push-check guard wasn't added."
fi

# Owner and name from the remote's address, as written in the config:
# https://github.com/OWNER/NAME(.git), git@github.com:OWNER/NAME.git, or a proxy address ending /OWNER/NAME.
u="${URL%/}"; u="${u%.git}"; NAME="${u##*/}"; rest="${u%/*}"; OWNER="${rest##*[/:]}"
if [ "$ALL" = "yes" ]; then echo "push-check: $OWNER/$NAME, every commit in the history (changes nothing)"
else echo "push-check: $OWNER/$NAME, branch $BRANCH"; fi

# 1. org
org_ok="no"
for o in "${ORGS[@]}"; do
  [ "$(lower "$o")" = "$(lower "$OWNER")" ] && org_ok="yes"
done
if [ "$org_ok" = "yes" ]; then pass "org: $OWNER is one of this side's"
else fail "org: $OWNER isn't one of this side's ($(printf '%s ' "${ORGS[@]}" | sed 's/ $//')). Wrong repo or wrong side?"; fi

# 2. remote (not for --all)
BASE=""; NEWBRANCH="no"
if [ "$ALL" = "yes" ]; then
  :
elif ! git fetch -q "$REMOTE" 2>/dev/null; then
  fail "remote: couldn't fetch $REMOTE, so the other checks can't run"
  finish
elif git rev-parse -q --verify "refs/remotes/$REMOTE/$BRANCH^{commit}" >/dev/null; then
  BASE="refs/remotes/$REMOTE/$BRANCH"
else
  NEWBRANCH="yes"
  BASE=$(git symbolic-ref -q "refs/remotes/$REMOTE/HEAD" 2>/dev/null) || BASE=""
  if [ -z "$BASE" ]; then
    def=$(git ls-remote --symref "$REMOTE" HEAD 2>/dev/null | awk '$1 == "ref:" { sub("refs/heads/", "", $2); print $2; exit }')
    if [ -n "$def" ] && git rev-parse -q --verify "refs/remotes/$REMOTE/$def^{commit}" >/dev/null; then
      BASE="refs/remotes/$REMOTE/$def"
    fi
  fi
fi
if [ "$ALL" = "yes" ]; then
  :
elif [ -z "$BASE" ]; then
  pass "remote: nothing has been pushed to $REMOTE yet"
elif [ "$NEWBRANCH" = "yes" ]; then
  pass "remote: $BRANCH is a new branch, compared with ${BASE#refs/remotes/}"
elif git merge-base --is-ancestor "$BASE" HEAD 2>/dev/null; then
  pass "remote: nothing new on $REMOTE/$BRANCH"
else
  fail "remote: $REMOTE/$BRANCH has commits this folder doesn't. Bring them in first, then check again."
fi

if [ -n "$BASE" ]; then RANGE="$BASE..HEAD"; else RANGE="HEAD"; fi
COMMITS=$(git rev-list --reverse "$RANGE" 2>/dev/null)
N=$(printf '%s\n' "$COMMITS" | grep -c . || true)
if [ "$N" -eq 0 ]; then
  echo "push-check: nothing new to push"
  finish
fi
if [ "$ALL" = "yes" ]; then echo "push-check: $N commit(s) to check"
else echo "push-check: $N new commit(s) to check"; fi

# 3. author
EXP_AUTHOR=""
if [ "$ALL" = "yes" ]; then AUTHOR_FROM="HEAD"; else AUTHOR_FROM="$BASE"; fi
if [ -n "$AUTHOR_FROM" ]; then
  EXP_AUTHOR=$(git log -n 300 --format='%an <%ae>' "$AUTHOR_FROM" 2>/dev/null | grep -v '\[bot\]' | head -n 1 || true)
fi
if [ -z "$EXP_AUTHOR" ]; then
  fail "author: there's no pushed commit to match (nothing pushed yet, or only bot commits). Make the repo's first commit on GitHub, then check again."
else
  bad=""
  case "$EXP_AUTHOR" in
    *"@users.noreply.github.com>") ;;
    *) fail "author: the latest pushed commit's author isn't a private GitHub noreply address, so it can't be the one to match" ;;
  esac
  nbad=0
  for c in $COMMITS; do
    a=$(git log -1 --format='%an <%ae>' "$c")
    if [ "$ALL" = "yes" ]; then case "$a" in *"[bot]"*) continue ;; esac; fi
    if [ "$a" != "$EXP_AUTHOR" ]; then bad="$bad$(git rev-parse --short "$c") is by $a$TAB"; nbad=$((nbad + 1)); fi
  done
  if [ -z "$bad" ]; then pass "author: all $N match $EXP_AUTHOR"
  else
    fail "author: $nbad not by the repo's author ($EXP_AUTHOR)"
    printf '%s' "$bad" | tr "$TAB" '\n' | head -n 5 | while IFS= read -r l; do detail "$l"; done
  fi
fi

# 4. committer (not for --all: older history has commits GitHub itself made, like uploads)
if [ "$ALL" = "no" ]; then
  if [ -n "$COMMITTER" ]; then EXP_COMMITTER="$COMMITTER"
  else EXP_COMMITTER="$(git config user.name) <$(git config user.email)>"; fi
  bad=""
  for c in $COMMITS; do
    cm=$(git log -1 --format='%cn <%ce>' "$c")
    h=$(git rev-parse --short "$c")
    [ "$cm" = "$EXP_COMMITTER" ] || bad="$bad$h is committed by $cm$TAB"
    git cat-file commit "$c" | sed '/^$/q' | grep -q '^gpgsig' || bad="$bad$h isn't signed, so GitHub won't show it as Verified$TAB"
  done
  if [ -z "$bad" ]; then pass "committer: all $N by $EXP_COMMITTER, signed"
  else
    fail "committer: not the default committer, or not signed"
    printf '%s' "$bad" | tr "$TAB" '\n' | head -n 5 | while IFS= read -r l; do detail "$l"; done
  fi
fi

# 5. dates
bad=""
for c in $COMMITS; do
  z=$(git log -1 --format='%ad %cd' --date=format:%z "$c")
  [ "$z" = "+0000 +0000" ] || bad="$bad$(git rev-parse --short "$c") has $(git log -1 --format='author date %ad, commit date %cd' --date=iso "$c")$TAB"
done
if [ -z "$bad" ]; then pass "dates: all in UTC"
else
  fail "dates: not in UTC (export TZ=UTC before committing)"
  printf '%s' "$bad" | tr "$TAB" '\n' | head -n 5 | while IFS= read -r l; do detail "$l"; done
fi

# Everything that goes out, one record per line: "where<TAB>text".
for c in $COMMITS; do
  h=$(git rev-parse --short "$c")
  git log -1 --format='%B' "$c" | awk -v h="$h" '{ print h " message\t" $0 }'
  git log -1 --format='%an <%ae>%n%cn <%ce>' "$c" | awk -v h="$h" '{ print h " author or committer\t" $0 }'
  git show --format= --name-only --diff-merges=first-parent "$c" | awk -v h="$h" 'NF { print h " file name\t" $0 }'
  git show --format= --text --no-color --no-ext-diff --unified=0 --diff-merges=first-parent "$c" | awk -v h="$h" '
    /^diff --git / { head = 1; next }
    head && /^\+\+\+ / { f = substr($0, 5); sub(/^b\//, "", f); next }
    /^@@/ { head = 0; match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0; next }
    !head && /^\+/ { print h " " f ":" n "\t" substr($0, 2); n++ }'
done > "$CORPUS"

# Up to 5 places a pattern turns up in the text that goes out, with a short snippet of each.
scan(){
  grep -a -n -Ei -- "$1" "$CORPUS" 2>/dev/null | while IFS= read -r line; do
    rest="${line#*:}"; where="${rest%%"$TAB"*}"; text="${rest#*"$TAB"}"
    snip=$(printf '%s\n' "$text" | grep -a -Eio -- ".{0,30}($1).{0,30}" | head -n 1)
    [ -n "$snip" ] && printf '%s: %s\n' "$where" "$snip"
  done | head -n 5
}

# 6. Claude links
# Written so this file doesn't match itself ([u] and [-] match only u and -).
CLAUDE_RE='claude\.ai/|claude\.ai$|claude\.site|claude[u]sercontent|claude[-]session|claude\.com/(chat|code|share|public|project|artifact)'
hits=$(scan "$CLAUDE_RE")
if [ -z "$hits" ]; then pass "claude: no Claude links"
else
  fail "claude: a Claude link or Claude session line is going out"
  printf '%s\n' "$hits" | while IFS= read -r l; do detail "$l"; done
fi

# 7. the other side's words
found=0; i=0
while [ "$i" -lt "${#RES[@]}" ]; do
  hits=$(scan "${RES[$i]}")
  if [ -n "$hits" ]; then
    [ "$found" -eq 0 ] && fail "other side: the other side's words are going out"
    found=$((found + 1))
    detail "\"${OTHERS[$i]}\":"
    printf '%s\n' "$hits" | while IFS= read -r l; do detail "  $l"; done
  fi
  i=$((i + 1))
done
[ "$found" -eq 0 ] && pass "other side: none of the ${#RES[@]} words in the changes, file names or messages"

if [ "$FAILS" -gt 0 ] || [ "$PUSH" = "no" ]; then finish; fi

# Every check passed: push exactly what was checked.
TIP=$(git rev-parse HEAD)
echo "push-check: PASS, pushing to $REMOTE/$BRANCH"
if PUSH_CHECK_PASSED="$TIP" git push -q "$REMOTE" "$TIP:refs/heads/$BRANCH"; then
  echo "push-check: pushed"
  exit 0
fi
echo "push-check: the push itself didn't go through (see git's message above)"
exit 1
