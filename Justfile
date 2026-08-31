set shell := ["bash", "-cu"]

build:
    bluebuild build recipes/kinoite.yml

update-lock:
    python3 scripts/update-lock.py

rebase:
    rpm-ostree rebase ostree-unverified-registry:ghcr.io/redzrush101/kinoite:latest

rebase-signed:
    rpm-ostree rebase ostree-image-signed:docker://ghcr.io/redzrush101/kinoite:latest
