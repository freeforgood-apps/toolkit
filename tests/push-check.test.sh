#!/usr/bin/env bash
# Tests for push-check.sh: a clean push passes, and every planted mistake gets caught.
# Everything is made up and stays in a temp folder: no network, no real names or accounts.
# Run from the toolkit folder:  bash tests/push-check.test.sh
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PC="${PUSH_CHECK:-$TK/push-check.sh}"   # PUSH_CHECK lets a broken copy be tested, to prove the tests catch bugs
T="$(mktemp -d "${TMPDIR:-/tmp}/push-check-test.XXXXXX")"
trap 'cd /; rm -rf "$T"' EXIT

# A private git setup just for these tests: UTC, a made-up default committer, a stand-in signer,
# and https://github.com/ pointing at made-up repos in the temp folder.
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1 TZ=UTC
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_AUTHOR_DATE GIT_COMMITTER_DATE
cat > "$T/stand-in-signer" <<'EOF'
#!/bin/sh
# Writes a placeholder signature where git expects one (git passes the file to sign last).
for f; do :; done
printf -- '-----BEGIN SSH SIGNATURE-----\nc3RhbmQtaW4=\n-----END SSH SIGNATURE-----\n' > "$f.sig"
EOF
chmod +x "$T/stand-in-signer"; : > "$T/stand-in-key"
git config --global user.name "Default Committer"
git config --global user.email "committer@example.invalid"
git config --global gpg.format ssh
git config --global gpg.ssh.program "$T/stand-in-signer"
git config --global user.signingkey "$T/stand-in-key"
git config --global commit.gpgsign true
git config --global init.defaultBranch main
git config --global url."file://$T/remotes/".insteadOf "https://github.com/"

OWNER="owner <1234+owner@users.noreply.github.com>"
ORG="goodorg"
OTHER1="Zorblat Trust"   # stands in for the other side's org name
OTHER2="qwix-handle"     # stands in for the other side's account
# Claude links, split in two so this file never matches push-check itself
CS="Claude""-Session"; CA="claude"".ai"; CSITE="claude"".site"

new_remote(){ git init -q --bare "$T/remotes/$1.git"; }
seed(){ # seed ORG/REPO AUTHOR : one pushed commit by AUTHOR
  rm -rf "$T/seed"; git clone -q "https://github.com/$1.git" "$T/seed" 2>/dev/null
  (cd "$T/seed" && echo "# app" > README.md && git add -A && git commit -q --author="$2" -m "Add README" && git push -q origin main)
}
fresh(){ # fresh [ORG/REPO] [clone options] : a new clone to work in
  local r="${1:-$ORG/app}"; shift || true
  cd "$T" || exit 1; rm -rf "$T/w"; git clone -q "$@" "https://github.com/$r.git" "$T/w" 2>/dev/null; cd "$T/w" || exit 1
}
change(){ # change FILE TEXT [MESSAGE] : a commit by the owner
  printf '%s\n' "$2" >> "$1"; git add -A
  git commit -q --author="$OWNER" -m "${3:-Update $1}" -m "Co-Authored-By: Helper <noreply@example.invalid>"
}
run(){ bash "$PC" --org "$ORG" --other "$OTHER1" --other "$OTHER2" "$@" > "$T/out" 2>&1; echo $? > "$T/code"; }

OKS=0; BADS=0
expect(){ # expect NAME EXIT PATTERN : after run, check the exit code and that the output has PATTERN
  local got; got=$(cat "$T/code")
  if [ "$got" = "$2" ] && grep -Eq -- "$3" "$T/out"; then OKS=$((OKS + 1)); echo "ok    $1"
  else BADS=$((BADS + 1)); echo "WRONG $1 (exit $got, wanted $2 and /$3/)"; sed 's/^/      | /' "$T/out"; fi
}
assert(){ # assert NAME TEST... : passes when the test after the name succeeds
  local name="$1"; shift
  if "$@"; then OKS=$((OKS + 1)); echo "ok    $name"
  else BADS=$((BADS + 1)); echo "WRONG $name"; sed 's/^/      | /' "$T/out"; fi
}

new_remote "$ORG/app"; seed "$ORG/app" "$OWNER"

# --- a clean change -----------------------------------------------------------------------------
fresh; change a.txt "hello"; run
expect "clean change passes" 0 '^push-check: PASS$'
assert "clean change: all 7 checks pass" [ "$(grep -c '^PASS' "$T/out")" = 7 ]

fresh "$ORG/app" --depth 1; change a.txt "hello"; run
expect "works in a shallow clone" 0 '^push-check: PASS$'

fresh; run
expect "nothing to push is fine" 0 'nothing new to push'

fresh; git checkout -q -b feature; change b.txt "feature"; run
expect "a new branch is compared with main" 0 'new branch, compared with origin/main'

# --- --push and the guard hook ------------------------------------------------------------------
fresh; change a.txt "pushed"; run --push
expect "--push pushes when everything passes" 0 '^push-check: pushed$'
assert "--push: the remote has the checked commit" [ "$(git ls-remote -q origin main | cut -f1)" = "$(git rev-parse HEAD)" ]

change a.txt "plain push"; git push -q origin main > "$T/out" 2>&1; echo $? > "$T/code"
expect "a plain git push is blocked by the guard" 1 'Blocked: push with push-check.sh --push'

fresh; before=$(git ls-remote -q origin main | cut -f1)
change a.txt "x" "Fix" ; git commit -q --amend --author="$OWNER" -m "Fix" -m "$CS: https://$CA/code/session_0000"; run --push
expect "--push doesn't push when a check fails" 1 '^FAIL  claude'
assert "--push: the remote is unchanged after a FAIL" [ "$(git ls-remote -q origin main | cut -f1)" = "$before" ]

# --- org ----------------------------------------------------------------------------------------
git clone -q --bare "$T/remotes/$ORG/app.git" "$T/remotes/wrongorg/app.git"
fresh; git remote set-url origin "https://github.com/wrongorg/app.git"; git fetch -q origin; change a.txt "hi"; run
expect "planted: the repo is in the wrong org" 1 '^FAIL  org: wrongorg'

# --- remote -------------------------------------------------------------------------------------
fresh; change a.txt "mine"
(cd "$T/seed" && git pull -q origin main && echo "theirs" >> c.txt && git add -A && git commit -q --author="$OWNER" -m "Elsewhere" && git push -q origin main)
run
expect "planted: the remote changed underneath" 1 '^FAIL  remote'

# --- author -------------------------------------------------------------------------------------
fresh; echo x > a.txt; git add -A; git commit -q --author="owner <owner@example.invalid>" -m "Update"; run
expect "planted: a personal email as author" 1 '^FAIL  author'

fresh; echo x > a.txt; git add -A; git commit -q --author="someone <999+someone@users.noreply.github.com>" -m "Update"; run
expect "planted: the other account as author" 1 '^FAIL  author'

fresh; change a.txt "one"; echo y > b.txt; git add -A; git commit -q --author="Owner <1234+owner@users.noreply.github.com>" -m "Update"; run
expect "planted: author name spelled differently, in the second of two commits" 1 'is by Owner <1234'

new_remote "$ORG/empty"; fresh "$ORG/empty"; change a.txt "first"; run
expect "planted: nothing pushed yet, so no author to match" 1 "no pushed commit to match"

new_remote "$ORG/botrepo"; seed "$ORG/botrepo" "$OWNER"
(cd "$T/seed" && echo v > v.txt && git add -A && git commit -q --author="github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>" -m "Bot" && git push -q origin main)
fresh "$ORG/botrepo"; change a.txt "after the bot"; run
expect "a bot's latest commit is skipped when finding the author" 0 '^PASS  author: all 1 match owner'

new_remote "$ORG/leaky"; seed "$ORG/leaky" "owner <owner@example.invalid>"
fresh "$ORG/leaky"; echo x > a.txt; git add -A; git commit -q --author="owner <owner@example.invalid>" -m "Update"; run
expect "planted: the pushed author isn't a noreply address" 1 "isn't a private GitHub noreply address"

# --- committer ----------------------------------------------------------------------------------
fresh; echo x > a.txt; git add -A; GIT_COMMITTER_NAME="Someone Else" git commit -q --author="$OWNER" -m "Update"; run
expect "planted: the committer was changed" 1 'is committed by Someone Else'

fresh; echo x > a.txt; git add -A; git -c commit.gpgsign=false commit -q --author="$OWNER" -m "Update"; run
expect "planted: an unsigned commit" 1 "isn't signed"

fresh; change a.txt "hi"; run --committer "Expected Committer <expected@example.invalid>"
expect "--committer sets who the committer must be" 1 'is committed by Default Committer'

# --- dates --------------------------------------------------------------------------------------
fresh; echo x > a.txt; git add -A
GIT_AUTHOR_DATE="2026-01-05T08:00:00-1000" GIT_COMMITTER_DATE="2026-01-05T08:00:00-1000" git commit -q --author="$OWNER" -m "Update"; run
expect "planted: a local time zone in the dates" 1 '^FAIL  dates'

fresh; echo x > a.txt; git add -A
GIT_AUTHOR_DATE="2026-01-05T08:00:00+0900" git commit -q --author="$OWNER" -m "Update"; run
expect "planted: only the author date has a time zone" 1 'author date 2026-01-05 08:00:00 \+0900'

# --- Claude links -------------------------------------------------------------------------------
fresh; echo x > a.txt; git add -A; git commit -q --author="$OWNER" -m "Update" -m "$CS: https://$CA/code/session_0000"; run
expect "planted: a Claude session line in the message" 1 'message: .*Claude.Session'

fresh; change notes.md "See https://$CA/chat/0000-1111 for why"; run
expect "planted: a chat link in a file" 1 'notes.md:1: .*claude\.ai/chat'

fresh; change notes.md "Made with an artifact at $CSITE/artifacts/abc"; run
expect "planted: an artifact link in a file" 1 '^FAIL  claude'

# --- the other side's words ---------------------------------------------------------------------
fresh; change site.html "<p>Run by the Zorblat Trust</p>"; run
expect "planted: the other side's org name in a file" 1 'site.html:1: .*Zorblat Trust'

for v in "zorblat-trust.example" "ZorblatTrust" "ZORBLAT_TRUST" "zorblat  trust"; do
  fresh; change page.txt "contact $v"; run
  expect "planted: the org name spelled as \"$v\"" 1 '^FAIL  other side'
done

fresh; change a.txt "hi" "Add the qwix-handle footer"; run
expect "planted: the other account in the message" 1 'message: .*qwix-handle'

fresh; mkdir -p docs; echo hi > "docs/qwix_handle-notes.md"; git add -A; git commit -q --author="$OWNER" -m "Add notes"; run
expect "planted: the other account in a file name" 1 'file name: docs/qwix_handle-notes.md'

fresh; change a.txt "made by qwixhandle"; sed -i.bak '$d' a.txt && rm -f a.txt.bak; git add -A; git commit -q --author="$OWNER" -m "Remove it"; run
expect "planted: added then removed, still in the history" 1 'a.txt:[0-9]+: made by qwixhandle'

fresh; printf 'PNG\000\001binary Zorblat Trust\000\002' > logo.png; git add -A; git commit -q --author="$OWNER" -m "Add logo"; run
expect "planted: the org name inside a binary file" 1 'logo.png'

fresh; change about.txt "Built for the zorblat team"; run
expect "a part of a word alone isn't a match" 0 '^PASS  other side'

# --- several at once ----------------------------------------------------------------------------
fresh; echo "qwix-handle" > a.txt; git add -A
GIT_AUTHOR_DATE="2026-01-05T08:00:00-1000" git commit -q --author="owner <owner@example.invalid>" -m "Update" -m "$CS: x"; run
expect "planted: four mistakes at once" 1 '^push-check: FAIL'
assert "planted: four mistakes at once, four FAILs" [ "$(grep -c '^FAIL' "$T/out")" -ge 4 ]

# --- --all, for sweeps --------------------------------------------------------------------------
new_remote "$ORG/hist"; seed "$ORG/hist" "$OWNER"
(cd "$T/seed" && echo v > v.txt && git add -A && git commit -q --author="github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>" -m "Bot" && git push -q origin main)
fresh "$ORG/hist"; run --all
expect "--all: a clean history passes, bot commits included" 0 '^push-check: PASS$'
assert "--all: five checks (no committer or remote line)" [ "$(grep -c '^PASS' "$T/out")" = 5 ]
assert "--all: changes nothing (no hook added)" [ ! -e "$T/w/.git/hooks/pre-push" ]

(cd "$T/seed" && git pull -q origin main && echo "for Zorblat Trust" > old.txt && git add -A \
  && git commit -q --author="someone <999+someone@users.noreply.github.com>" -m "Old" \
  && git rm -q old.txt && GIT_AUTHOR_DATE="2026-01-05T08:00:00-1000" git commit -q --author="$OWNER" -m "Remove" \
  && echo w > w.txt && git add -A && git commit -q --author="$OWNER" -m "Later" && git push -q origin main)
fresh "$ORG/hist"; run --all
expect "--all, planted: an old commit by another account" 1 '^FAIL  author: 1 not by the repo'
expect "--all, planted: the other side's word in an old, removed file" 1 'old.txt:1: for Zorblat Trust'
expect "--all, planted: a local time zone in old history" 1 '^FAIL  dates'

# --- the command itself -------------------------------------------------------------------------
bash "$PC" --org "$ORG" --other "$OTHER1" --all --push > "$T/out" 2>&1; echo $? > "$T/code"
expect "usage: --all with --push" 2 "can't be used with --push"
fresh
bash "$PC" --other "$OTHER1" > "$T/out" 2>&1; echo $? > "$T/code"
expect "usage: no --org" 2 'at least one --org'
bash "$PC" --org "$ORG" > "$T/out" 2>&1; echo $? > "$T/code"
expect "usage: no --other" 2 'at least one --other'
bash "$PC" --org "$ORG" --other "ab" > "$T/out" 2>&1; echo $? > "$T/code"
expect "usage: a word too short to search for" 2 'too short'
bash "$PC" --org "zorblat-trust" --other "$OTHER1" > "$T/out" 2>&1; echo $? > "$T/code"
expect "usage: the sides mixed up" 2 'Check which side this is'
bash "$PC" --help > "$T/out" 2>&1; echo $? > "$T/code"
expect "--help shows how to use it" 0 'Usage:'

echo
echo "push-check tests: $OKS ok, $BADS wrong"
[ "$BADS" -eq 0 ]
