set shell := ["bash", "-cu"]

build:
    bluebuild build recipes/kinoite.yml

update-lock:
    python3 scripts/update-lock.py

validate:
    python3 -m json.tool files/packages.lock.json >/dev/null
    python3 -c 'from pathlib import Path; p = Path("scripts/update-lock.py"); compile(p.read_text(), str(p), "exec")'
    find files -type f -perm -u+x -print0 | xargs -0 -n1 bash -n
    bluebuild validate recipes/kinoite.yml

rebase:
    rpm-ostree rebase ostree-unverified-registry:ghcr.io/redzrush101/kinoite:latest

rebase-signed:
    rpm-ostree rebase ostree-image-signed:docker://ghcr.io/redzrush101/kinoite:latest
