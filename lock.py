"""Refresh the privacy lock: list the sha256 fingerprint of every inline script in the page's CSP.
Usage: python3 lock.py index.html [more.html]   (updates the files in place; run after every script edit)
       python3 lock.py --check index.html [more.html]   (changes nothing; exits 1 if any lock is out of date)"""
import base64, hashlib, re, sys

SCRIPT = re.compile(r"<script>(.*?)</script>", re.S)  # inline scripts are written as a plain <script>
CSP_SCRIPTS = re.compile(r"(script-src )[^;\"]*")

def lock(html):
    prints = ["'sha256-%s'" % base64.b64encode(hashlib.sha256(m.group(1).encode("utf-8")).digest()).decode()
              for m in SCRIPT.finditer(html)]
    new, n = CSP_SCRIPTS.subn(lambda m: m.group(1) + (" ".join(prints) or "'none'"), html, count=1)
    if n != 1:
        sys.exit("No script-src found in the privacy lock.")
    return new, len(prints)

check = "--check" in sys.argv[1:]
stale = []
for path in [a for a in sys.argv[1:] if a != "--check"]:
    with open(path, encoding="utf-8") as f:
        old = f.read()
    text, count = lock(old)
    if check:
        if text != old:
            stale.append(path)
        print(f"{path}: {count} script(s), lock {'OUT OF DATE' if text != old else 'up to date'}")
        continue
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"{path}: locked {count} script(s)")
if stale:
    sys.exit(1)
