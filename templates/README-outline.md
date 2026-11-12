# REPLACE-ME app name

<!--
The shared README for an app repo: the same sections, in the same order, as Till Payday's and Study Coach's.
Copy this file into the app repo as README.md, fill in every section from the app's own words, replace every
REPLACE-ME until `grep -ni replace-me README.md` finds nothing, and delete these notes (everything between the
comment marks). Every claim must match the app and CHANGELOG.md: no feature, setting or test result goes in
unless the app or CHANGELOG.md shows it. A section that doesn't fit the app gets dropped, not filled with guesses.
An app outside freeforgood-apps never names freeforgood-apps anywhere in its README.
-->

REPLACE-ME one-line pitch: what it is, "free", "works on any phone or computer", and "No account, no ads, no tracking."

**Open the app:** https://REPLACE-ME.github.io/REPLACE-ME/

**Run the self-test:** https://REPLACE-ME.github.io/REPLACE-ME/selftest.html

## Who it's for

<!-- Two to four warm sentences: who opens it, and when. -->
REPLACE-ME

## What's inside

<!-- One bullet per feature, a bold name first. Say where saving and backups live. -->
- **REPLACE-ME:** REPLACE-ME

## Add it to your home screen

- **iPhone or iPad:** open the link in Safari → tap **Share** → **Add to Home Screen**
- **Android:** open the link in Chrome → tap **⋮** → **Install app** (or **Add to Home screen**)
- **Computer:** in Chrome or Edge, click the install icon at the right end of the address bar

<!-- Then the app's own "keep it safe" tips: the Home Screen app keeps its own data, Safari's 7-day clearing,
     backups and where they are in the app. Copy the wording from the app's About screen. -->
REPLACE-ME

## Tested on

Results are tied to the version and date they were run. When the app changes, these results only describe the version listed.

<!-- Newest first. One row per real iPhone run and one per headless Chrome run, copied from CHANGELOG.md's
     "Tested:" lines. Keep at least the latest release's rows; older rows can move out once they're in
     CHANGELOG.md, with a line saying so under the table. -->
| Version | Date | Browser and device | Result |
|---|---|---|---|
| REPLACE-ME | REPLACE-ME | The published GitHub Pages site, Safari engine (WebKit) on a real iPhone (iOS REPLACE-ME), in a Safari tab | ✓ Passed, REPLACE-ME automated checks |
| REPLACE-ME | REPLACE-ME | Chrome (Blink engine) on Linux, headless: full check at phone size, small phone size in dark mode and desktop size | ✓ Passed, REPLACE-ME automated checks at each size |

**What the automated checks cover:** REPLACE-ME <!-- list the self-test's steps in plain words -->

Chrome's engine also powers Microsoft Edge, Chromebooks, Android phones, Samsung Internet, Brave and Opera. Safari's engine powers Safari and nearly every other browser on iPhone and iPad.

### Run the self-test yourself

Open **selftest.html** in any browser (the app's About screen links to it) and tap **Run self-test**. It taps through the whole app and shows a pass/fail report you can copy, with the version it checked on the first line. It saves to its own separate storage, so it never touches anyone's real REPLACE-ME. If you run it on a browser that isn't listed above, please share the report by email or in this repository's **Issues** tab (see Feedback below).

## Privacy

<!-- The app's own privacy list from About, plus the honest promise (app-new-project Part 6). A live-data app
     says exactly what the phone asks its data source for, credits the source the way its terms ask, and adds
     a "not affiliated" note. Keep the GitHub Pages line. -->
- No accounts, ads, analytics or tracking.
- REPLACE-ME
- Like any site, GitHub Pages logs visitors' IP addresses for security; see the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Accessibility

<!-- Only what the app really has: tap targets, screen-reader labels, text size, light and dark, WCAG 2.2 AA
     contrast, keyboard keys, and any real-iPhone VoiceOver check (with its version). -->
REPLACE-ME If anything is hard to use, please let us know (see Feedback below).

## REPLACE-ME honest limits

<!-- Title it for the app: "Not financial advice", "Not an official REPLACE-ME product" (with the trademark
     notice), or both. Copy the app's own wording. -->
REPLACE-ME

## About the REPLACE-ME content

<!-- "About the content", "About the numbers" or "About the forecasts": built with help from AI (Claude, made by
     Anthropic), how it's checked, and how to report a mistake. -->
REPLACE-ME

## Feedback

<!-- An app with no feedback address (like one shared among friends and family) drops the Email and GitHub lines,
     says who to tell instead, and points to the self-test report. -->
Spotted a mistake, got stuck or have an idea? You don't need an account to reach us.

- **Email:** REPLACE-ME (private, no account needed)
- **GitHub:** open an issue in this repository's **Issues** tab (public, needs a free GitHub account)
- **In the app:** REPLACE-ME

REPLACE-ME app name is a one-person volunteer project, so replies can take a while. Every message still helps, even if you don't hear back right away. Please don't include personal details you don't want to share.

## Terms of use

<!-- Copy the app's own terms. An app with no terms yet drops this section until its About screen has them. -->
Free to use. Provided "as is," without warranties of any kind. REPLACE-ME <!-- the app's own "not advice" or "not a guarantee" line -->

## Files

<!-- Every file at the top of the repo, one row each (icons, and tests, can share a row). A live-data app also lists
     its fetch script and publish steps, and says its data file lives only on the website. -->
| File | What it does |
|---|---|
| `index.html` | The whole app in one file (about REPLACE-ME KB) |
| `selftest.html` | The automated self-test. Uses separate storage, so it's safe to share |
| `sw.js` | Lets the app work offline after the first visit. Keep it next to `index.html` |
| `manifest.webmanifest` | The app's install details: name, icons and how it opens |
| REPLACE-ME icons | The app icons |
| `README.md` | This page |
| `CHANGELOG.md` | What changed in each version, and how it was tested |
| `PROGRESS.md` | Where the project stands, and the rules for working on it |
| `how-to-update.md` | The steps for any change and release, and what must not break |
| `SECURITY.md` | How to report a security problem privately |
| `.gitignore` | Keeps private files, like keys, from being uploaded by mistake |

## Updating the app

<!-- A live-data app is published by its Publish workflow, not from the branch: say so here, and drop the
     "within a minute or two" line. -->
Follow [`how-to-update.md`](how-to-update.md), then upload the new files to this repository and commit. GitHub Pages updates the site within a minute or two, and everyone's saved REPLACE-ME carries over. After an update, run the self-test again and add new rows to **Tested on**.

© REPLACE-ME year REPLACE-ME app name
