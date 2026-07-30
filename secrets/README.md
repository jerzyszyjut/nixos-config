Encrypted secrets live here. The `.yaml` files in this directory are safe to
commit — sops encrypts every value, leaving the keys readable so diffs stay
reviewable.

Never commit anything named `*.dec`, `*.plain`, or `keys.txt`. The `.gitignore`
at the repo root covers those, but check before you push.

See ../docs/SECRETS.md.
