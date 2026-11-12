#!/usr/bin/env bash
# Checks the Cloudflare site starter (templates/cloudflare-site) still fits the rules, with no network.
# Run from the toolkit folder: bash tests/cloudflare-site.test.sh
# One PASS or FAIL line each. Exits 0 only when every check passed.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
S=templates/cloudflare-site
fails=0
# Each check runs in a subshell, so one can never end the whole test early.
check() { if ( eval "$2" ) >/dev/null 2>&1; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails+1)); fi; }

# The settings that keep the site at one address (comments stripped from wrangler.jsonc first)
json='python3 -I -c "import json,re,sys; print(json.dumps(json.loads(re.sub(r\"^\s*//.*$\", \"\", open(sys.argv[1]).read(), flags=re.M))))" '"$S/wrangler.jsonc"
check "wrangler.jsonc parses"                        "$json"
check "preview_urls written out as false"            "$json | grep -q '\"preview_urls\": false'"
check "workers_dev written out"                      "$json | grep -qE '\"workers_dev\": (true|false)'"
check "assets from ./public with the 404 page"       "$json | grep -q '\"directory\": \"./public\"' && $json | grep -q '\"not_found_handling\": \"404-page\"'"
check "compatibility_date is a real date"            "$json | grep -qE '\"compatibility_date\": \"20[0-9]{2}-[01][0-9]-[0-3][0-9]\"'"

# Versions pinned exactly and in step
wv=$(python3 -I -c "import json; print(json.load(open('$S/package.json'))['devDependencies']['wrangler'])")
lv=$(python3 -I -c "import json; print(json.load(open('$S/package-lock.json'))['packages']['node_modules/wrangler']['version'])")
pv=$(python3 -I -c "import json; print(json.load(open('$S/package.json'))['version'])")
av=$(grep -oE 'APP_VERSION = "[0-9]+\.[0-9]+\.[0-9]+"' "$S/public/index.html" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
check "wrangler pinned exactly ($wv)"               "[[ '$wv' =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]"
check "package-lock.json has the same wrangler"      "[ '$wv' = '$lv' ]"
check "APP_VERSION matches package.json ($pv)"       "[ -n '$av' ] && [ '$av' = '$pv' ]"

# The privacy lock and headers
check "privacy lock up to date on every page"        "python3 -I lock.py --check $S/public/*.html"
check "every page has a CSP, a title and lang"       "for f in $S/public/*.html; do grep -q Content-Security-Policy \$f && grep -q '<title>' \$f && grep -q '<html lang=' \$f || exit 1; done"
check "no page blocks zoom"                          "! grep -lE 'user-scalable=no|maximum-scale=1[^0-9]' $S/public/*.html"
check "no page fetches anything (connect-src none)"  "for f in $S/public/*.html; do grep -q \"connect-src 'none'\" \$f || exit 1; done"
check "_headers sets the four headers"               "grep -q \"frame-ancestors 'none'\" $S/public/_headers && grep -q nosniff $S/public/_headers && grep -q Referrer-Policy $S/public/_headers && grep -q Permissions-Policy $S/public/_headers"
check "404.html and accessibility.html are there"    "[ -f $S/public/404.html ] && [ -f $S/public/accessibility.html ]"

# Kept in step with the other templates
check "gitignore has every baseline line"            "grep -vxFf $S/gitignore templates/gitignore | grep -q . && exit 1 || exit 0"
check "gitignore adds .dev.vars and .wrangler/"      "grep -qx '.dev.vars' $S/gitignore && grep -qx '.wrangler/' $S/gitignore"
check "tag workflow reads public/index.html"         "grep -q 'contents/public/index.html?ref=' $S/.github/workflows/tag-new-versions.yml"
check "tag workflow starts with no permissions"      "grep -qx 'permissions: {}' $S/.github/workflows/tag-new-versions.yml"

echo
if [ "$fails" -eq 0 ]; then echo "RESULT: ALL PASSED"; else echo "RESULT: $fails FAILED"; fi
[ "$fails" -eq 0 ]
