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
| `selftest-runner.mjs` | Runs an app's self-test at three sizes (phone, small phone in dark mode, desktop) with fresh storage each time. Needs the standard hooks: a **Run self-test** button `#st-go` and a report box `#st-sum` whose first line says PASSED or FAILED. Exits 0 only when every run passes. | `node /tmp/toolkit/selftest-runner.mjs http://127.0.0.1:8770/selftest.html` |
| `a11y-check.mjs` | axe-core WCAG 2.2 AA and best-practice rules, plus 44px tap targets, 16px inputs, zoom allowed and no sideways scrolling, at 4 sizes in light and dark mode. Turns off the app's privacy lock only inside the test browser. Checks what's showing on load, so open other screens first or run it on the self-test. | `node /tmp/toolkit/a11y-check.mjs http://127.0.0.1:8770/index.html` |
| `lock.py` | Refreshes the privacy lock: puts the sha256 fingerprint of every inline `<script>` into the page's CSP `script-src`. Run after every script edit, or the app won't start. Updates files in place. | `python3 /tmp/toolkit/lock.py index.html selftest.html` |

## Templates (copy into an app)

| File | What it is |
|---|---|
| `templates/privacy-lock.html` | The CSP and referrer meta tags, for single-file apps and for apps with separate files. Goes in `<head>` before any script. |
| `templates/el.js` | `el()`: builds elements from data safely (text only, no event handlers, no `javascript:` links). |
| `templates/parse-backup.js` | `parseBackup()`: checks a backup before restoring. Throws a friendly message, never saves. |
| `templates/actions-header.yml` | GitHub Actions header with read-only permissions. Swap in each action's real commit SHA. |
| `templates/gitignore` | Baseline `.gitignore` (keys, env files, build output). |
| `templates/SECURITY.md` | Baseline `SECURITY.md` for an app repo. |

## Versions

Dependencies are pinned exactly (`puppeteer-core` 25.16.0, `axe-core` 4.14.0) and locked in `package-lock.json`. Update them on purpose, then re-run every tool on a real app before committing.

Tested on Till Payday 1.1.6: self-test passed at all three sizes (286 checks each), accessibility check found nothing, and `lock.py` left the live files unchanged.
