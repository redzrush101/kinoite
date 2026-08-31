#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "files" / "packages.lock.json"
TOKEN = os.environ.get("GITHUB_TOKEN")
UA = "redzrush101-kinoite-package-updater/1"

ASSETS = {
    "iloader": ("nab138/iloader", re.compile(r"^iloader-linux-x86_64\.rpm$")),
    "samloader": ("topjohnwu/samloader-rs", re.compile(r"^samloader-v.*-linux-x86_64\.tar\.xz$")),
    "uad-ng": (
        "Universal-Debloater-Alliance/universal-android-debloater-next-generation",
        re.compile(r"^uad-ng-noselfupdate-linux$"),
    ),
}


def request(url: str) -> urllib.request.Request:
    headers = {"User-Agent": UA, "Accept": "application/vnd.github+json"}
    if TOKEN and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {TOKEN}"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
    return urllib.request.Request(url, headers=headers)


def read_json(url: str):
    with urllib.request.urlopen(request(url), timeout=30) as r:
        return json.load(r)


def sha256_url(url: str) -> str:
    h = hashlib.sha256()
    with urllib.request.urlopen(request(url), timeout=60) as r:
        while chunk := r.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()


def validate_sha256(value: str, source: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise RuntimeError(f"{source}: invalid SHA-256 digest {value!r}")
    return value


def github_asset(repo: str, pattern: re.Pattern[str]) -> dict[str, str]:
    release = read_json(f"https://api.github.com/repos/{repo}/releases/latest")
    matches = [a for a in release["assets"] if pattern.fullmatch(a["name"])]
    if len(matches) != 1:
        raise RuntimeError(f"{repo}: expected exactly one matching asset, got {[a['name'] for a in matches]}")
    asset = matches[0]
    digest = asset.get("digest") or ""
    sha = digest.removeprefix("sha256:") if digest.startswith("sha256:") else sha256_url(asset["browser_download_url"])
    return {
        "asset": asset["name"],
        "repository": repo,
        "sha256": validate_sha256(sha, f"{repo}/{asset['name']}"),
        "tag": release["tag_name"],
        "url": asset["browser_download_url"],
    }


def github_release_commit(repo: str) -> dict[str, str]:
    release = read_json(f"https://api.github.com/repos/{repo}/releases/latest")
    tag = release["tag_name"]
    encoded = urllib.parse.quote(tag, safe="")
    ref = read_json(f"https://api.github.com/repos/{repo}/git/ref/tags/{encoded}")["object"]
    if ref["type"] == "tag":
        ref = read_json(ref["url"])["object"]
    if ref["type"] != "commit":
        raise RuntimeError(f"{repo}: latest tag does not resolve to a commit")
    return {"commit": ref["sha"], "repository": repo, "tag": tag}


def github_release_file(repo: str, path: str) -> dict[str, str]:
    release = github_release_commit(repo)
    url = f"https://raw.githubusercontent.com/{repo}/{release['commit']}/{path}"
    return {
        **release,
        "path": path,
        "sha256": validate_sha256(sha256_url(url), f"{repo}/{path}"),
        "url": url,
    }


def sp_flash(old: dict) -> dict[str, str]:
    page_url = "https://spflashtools.com/category/linux/"
    with urllib.request.urlopen(request(page_url), timeout=30) as r:
        html = r.read().decode("utf-8", "replace")
    versions = set(re.findall(r"SP Flash Tool v(5\.\d+) for Linux", html, flags=re.I))
    if not versions:
        raise RuntimeError("SP Flash Tool: no v5 Linux release found")
    version = max(versions, key=lambda v: tuple(int(x) for x in v.split(".")))
    url = f"https://cdn.spflashtools.com/wp-content/uploads/SP_Flash_Tool_v{version}_Linux.zip"
    previous = old.get("sp-flash-tool", {})
    sha = previous.get("sha256") if previous.get("url") == url else sha256_url(url)
    return {
        "channel": "v5-linux",
        "sha256": validate_sha256(sha, "SP Flash Tool"),
        "url": url,
        "version": version,
    }


def main() -> int:
    old = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    new = {name: github_asset(repo, pattern) for name, (repo, pattern) in ASSETS.items()}
    new["android-udev-rules"] = github_release_file("M0Rf30/android-udev-rules", "51-android.rules")
    new["mtkclient"] = github_release_commit("bkerler/mtkclient")
    new["sp-flash-tool"] = sp_flash(old)
    rendered = json.dumps(dict(sorted(new.items())), indent=2, sort_keys=True) + "\n"
    if LOCK.exists() and LOCK.read_text() == rendered:
        print("packages.lock.json is current")
        return 0
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=LOCK.parent, delete=False) as f:
        f.write(rendered)
        temporary = Path(f.name)
    temporary.replace(LOCK)
    print("updated packages.lock.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
