# freeforgood-apps toolkit

Shared test and safety tools for the freeforgood-apps web apps, kept in one place so every app is checked the same way.

## Set up (once per session)

```
git clone -q --depth 1 https://github.com/freeforgood-apps/toolkit /tmp/toolkit
(cd /tmp/toolkit && npm ci --ignore-scripts --silent)
```

The tools need Chrome. Set `CHROME` if it isn't at `/usr/bin/google-chrome`. If there's no Chrome, say so rather than reporting results.

Serve the app's folder locally first (in the background):

```
python3 -m http.server 8770 --bind 127.0.0.1
```

## Tools

| File | What it does | Run it |
|---|---|---|
| `release-check.sh` | **Run this on every release.** One command for the automated checks, with one PASS / FAIL / REVIEW / SKIP line each: versions agree (`APP_VERSION`, `sw.js`, `selftest.html`, newest `CHANGELOG.md` entry), privacy lock up to date, self-test at three sizes, accessibility check, and the security search patterns on every line changed since the last tag. Starts and stops its own local server. Full output goes to a log folder it names. Each `--click "selector"` adds one more accessibility pass with that element pressed first (to open a sheet), so sheets get checked on release too. Exits 0 when nothing failed; REVIEW lines are leads someone still has to look at. | `bash /tmp/toolkit/release-check.sh <app folder> [more pages] [--click "selector" ...]` |
| `selftest-runner.mjs` | Runs an app's self-test at three sizes (phone, small phone in dark mode, desktop) with fresh storage each time. Needs the standard hooks: a **Run self-test** button `#st-go` and a report box `#st-sum` whose first line says PASSED or FAILED. Exits 0 only when every run passes. | `node /tmp/toolkit/selftest-runner.mjs http://127.0.0.1:8770/selftest.html` |
| `a11y-check.mjs` | axe-core WCAG 2.2 AA and best-practice rules, plus 44px tap targets (a checkbox, radio or file input counts by its label), 16px inputs, zoom allowed and no sideways scrolling, at 4 sizes in light and dark mode. Exits 0 only when every page is clean. Turns off the app's privacy lock only inside the test browser. Checks what's showing on load. To check a sheet or another screen, add `--click "selector"` (repeatable, pressed in order before the scan), or run it on the self-test. | `node /tmp/toolkit/a11y-check.mjs [--click "button.add[data-open=backup]"] http://127.0.0.1:8770/index.html` |
| `lock.py` | Refreshes the privacy lock: puts the sha256 fingerprint of every inline `<script>` into the page's CSP `script-src`. Run after every script edit, or the app won't start. Updates files in place. `--check` changes nothing and exits 1 if a lock is out of date. | `python3 /tmp/toolkit/lock.py index.html selftest.html` |
| `push-check.sh` | **Run it for every push, in every repo, with `--push`,** so the push happens only when everything passed. One PASS or FAIL line each, on every commit not on the remote yet: the remote's owner is one of this side's orgs; nothing new on the remote underneath; each author matches the latest pushed commit not made by a bot, and that's a private GitHub noreply address; the default committer, signed, so GitHub shows Verified; dates in UTC; no Claude links; and none of the other side's words in the added lines, file names, messages, authors or committers (each commit, so a word added and then removed still counts). The orgs and words come in as arguments every time and are never saved in a file. The first run in a folder adds a pre-push hook there (no words in it) that stops a plain `git push`. For sweeps, `--all` checks every commit in the history instead (org, author, dates, Claude links and the other side's words) and changes nothing. Exits 0 when everything passed, 1 on any FAIL, 2 when the command is wrong. Needs only bash 3.2+ and git 2.31+, so it runs on a Mac too. | `bash /tmp/toolkit/push-check.sh --org <org> [--org ...] --other "<word>" [--other ...] --push` |
| `patterns.txt` | The security search patterns (one per line, for `grep -E` and `rg`). A match is a lead, not a finding, until someone looks. | `grep -rnEf /tmp/toolkit/patterns.txt .` |

## Templates (copy into an app)

| File | What it is |
|---|---|
| `templates/privacy-lock.html` | The CSP and referrer meta tags, for single-file apps and for apps with separate files. Goes in `<head>` before any script. |
| `templates/el.js` | `el()`: builds elements from data safely (text only, no event handlers, no `javascript:` links). |
| `templates/parse-backup.js` | `parseBackup()`: checks a backup before restoring. Throws a friendly message, never saves. |
| `templates/actions-header.yml` | GitHub Actions header with read-only permissions. Swap in each action's real commit SHA. |
| `templates/gitignore` | Baseline `.gitignore` (keys, env files, build output). |
| `templates/SECURITY.md` | Baseline `SECURITY.md` for an app repo. |
| `templates/README-outline.md` | The shared `README.md` for an app repo: the same sections, in the same order, as Till Payday's and Study Coach's. Copy it in as `README.md`, fill each section from the app's own words and `CHANGELOG.md`, replace every `REPLACE-ME` until `grep -ni replace-me README.md` finds nothing, and delete the `<!-- -->` notes. |
| `templates/cloudflare-site/` | A starter for a site of mine on Cloudflare Workers (project type 10, cloudflare-basics): `wrangler.jsonc` (workers.dev on, `preview_urls` off, both written out), `package.json` and `package-lock.json` with wrangler pinned, `public/` with a locked `index.html`, `404.html`, `accessibility.html`, `style.css` and `_headers`, a `gitignore`, and the Tag new versions workflow reading `public/index.html`. To use it, copy the folder's contents (dot folders too) into the new repo, rename `gitignore` to `.gitignore`, replace every `REPLACE-ME` until `grep -rni replace-me . --exclude-dir=node_modules` finds nothing (the `-i` matters: the names in `wrangler.jsonc`, `package.json` and `package-lock.json` have to be lowercase, so they read `replace-me`), and run `lock.py` on any page whose script changes. |

## Versions

Dependencies are pinned exactly (`puppeteer-core` 25.16.0, `axe-core` 4.14.0) and locked in `package-lock.json`. Update them on purpose, then re-run every tool on a real app before committing.

The Cloudflare site starter pins `wrangler` 4.160.1 in its own `package.json` and lock (not the toolkit's), with `compatibility_date` 2026-11-10, the newest its runtime supports. Update them together on purpose, then rerun `bash tests/cloudflare-site.test.sh` and the starter checks below.

`release-check.sh` was tested on Till Payday 1.1.6: all five checks passed (about 26 seconds). On a copy with problems planted on purpose (an out-of-date lock, a wrong `sw.js` version, an unlabeled 12px input, a fake key and an `insertAdjacentHTML` call), it failed versions, lock and accessibility and listed the planted line as a lead.

`push-check.sh` has its own tests: `bash tests/push-check.test.sh` makes made-up repos in a temp folder (no network) and runs a clean change, `--push` and the guard hook, `--all`, and 28 planted-mistake checks (wrong org, a remote that moved, wrong or non-noreply authors, a changed or unsigned committer, local time zones, Claude links, and the other side's words in files, names, messages, binary files, other spellings and removed lines). With bugs planted in copies of the script (the dates check, binary files, bot authors), the tests caught each one. Its word matching is loose on purpose (any case, with or without spaces, dots, hyphens or underscores), so a lookalike can FAIL: reword it, or make sure it isn't the other side. It can't see inside compressed files like zips.

The other tools were tested on Till Payday 1.1.6: self-test passed at all three sizes (286 checks each), accessibility check found nothing, and `lock.py` left the live files unchanged.

`templates/cloudflare-site/` has its own test: `bash tests/cloudflare-site.test.sh` (no network) checks its settings, pinned versions, lock, headers and pages, and that it stays in step with the other templates. Nine mistakes planted on purpose (preview URLs on, a loose wrangler version, a stale lock, a missing ignore line, the wrong tag path, versions out of step, zoom blocked, broad workflow permissions, a page allowed to fetch) were each caught. The starter itself was tested with wrangler 4.160.1: `wrangler deploy --dry-run` read its 5 files with no bindings, `wrangler dev` served every page (a missing page got `404.html` with a 404 status, and all four headers were on every response), and `release-check.sh public` passed, with the accessibility checker clean on all three pages at 4 sizes in light and dark.
