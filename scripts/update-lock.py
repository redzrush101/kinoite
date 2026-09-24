#!/usr/bin/env python3
from __future__ import annotations

import fnmatch
import hashlib
import json
import os
import re
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "files" / "packages.lock.json"
API = "https://api.github.com/repos"
TOKEN = os.environ.get("GITHUB_TOKEN")
USER_AGENT = "redzrush101-kinoite-package-updater/2"

ASSETS = {
    "iloader": (
        "nab138/iloader",
        ("iloader-linux-amd64.rpm", "iloader-linux-x86_64.rpm"),
    ),
    "samloader": (
        "topjohnwu/samloader-rs",
        ("samloader-v*-linux-x86_64.zip", "samloader-v*-linux-x86_64.tar.xz"),
    ),
    "uad-ng": (
        "Universal-Debloater-Alliance/universal-android-debloater-next-generation",
        ("uad-ng-linux", "uad-ng-noselfupdate-linux"),
    ),
}


def request(url: str) -> urllib.request.Request:
    headers = {"User-Agent": USER_AGENT}
    if url.startswith("https://api.github.com/"):
        headers |= {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if TOKEN:
            headers["Authorization"] = f"Bearer {TOKEN}"
    return urllib.request.Request(url, headers=headers)


def read_json(url: str):
    with urllib.request.urlopen(request(url), timeout=30) as response:
        return json.load(response)


def sha256_url(url: str) -> str:
    digest = hashlib.sha256()
    with urllib.request.urlopen(request(url), timeout=180) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def latest_release(repo: str) -> dict:
    return read_json(f"{API}/{repo}/releases/latest")


def release_asset(repo: str, patterns: tuple[str, ...]) -> dict[str, str]:
    release = latest_release(repo)
    assets = release["assets"]

    for pattern in patterns:
        matches = [asset for asset in assets if fnmatch.fnmatchcase(asset["name"], pattern)]
        if len(matches) == 1:
            asset = matches[0]
            break
        if len(matches) > 1:
            raise RuntimeError(f"{repo}: {pattern!r} matched multiple assets")
    else:
        available = ", ".join(asset["name"] for asset in assets)
        raise RuntimeError(f"{repo}: no matching release asset; available: {available}")

    value = asset.get("digest") or ""
    sha256 = value.removeprefix("sha256:") if value.startswith("sha256:") else sha256_url(asset["browser_download_url"])
    if not re.fullmatch(r"[0-9a-f]{64}", sha256):
        raise RuntimeError(f"{repo}/{asset['name']}: invalid SHA-256 digest {sha256!r}")

    return {
        "asset": asset["name"],
        "repository": repo,
        "sha256": sha256,
        "tag": release["tag_name"],
        "url": asset["browser_download_url"],
    }


def release_commit(repo: str) -> dict[str, str]:
    tag = latest_release(repo)["tag_name"]
    ref = urllib.parse.quote(tag, safe="")
    commit = read_json(f"{API}/{repo}/commits/{ref}")["sha"]
    return {"commit": commit, "repository": repo, "tag": tag}


def release_file(repo: str, path: str) -> dict[str, str]:
    release = release_commit(repo)
    url = f"https://raw.githubusercontent.com/{repo}/{release['commit']}/{path}"
    return {**release, "path": path, "sha256": sha256_url(url), "url": url}


def sp_flash(old: dict) -> dict[str, str]:
    page = "https://spflashtools.com/category/linux/"
    with urllib.request.urlopen(request(page), timeout=30) as response:
        html = response.read().decode("utf-8", "replace")

    versions = set(re.findall(r"SP Flash Tool v(5\.\d+) for Linux", html, flags=re.I))
    if not versions:
        raise RuntimeError("SP Flash Tool: no v5 Linux release found")

    version = max(versions, key=lambda value: tuple(map(int, value.split("."))))
    url = f"https://cdn.spflashtools.com/wp-content/uploads/SP_Flash_Tool_v{version}_Linux.zip"
    previous = old.get("sp-flash-tool", {})
    sha256 = previous.get("sha256") if previous.get("url") == url else sha256_url(url)
    return {"channel": "v5-linux", "sha256": sha256, "url": url, "version": version}


def main() -> int:
    old = json.loads(LOCK.read_text()) if LOCK.exists() else {}
    new = {name: release_asset(repo, patterns) for name, (repo, patterns) in ASSETS.items()}
    new["android-udev-rules"] = release_file("M0Rf30/android-udev-rules", "51-android.rules")
    new["mtkclient"] = release_commit("bkerler/mtkclient")
    new["sp-flash-tool"] = sp_flash(old)

    rendered = json.dumps(new, indent=2, sort_keys=True) + "\n"
    if LOCK.exists() and LOCK.read_text() == rendered:
        print("packages.lock.json is current")
        return 0

    temporary = LOCK.with_suffix(".tmp")
    temporary.write_text(rendered)
    temporary.replace(LOCK)
    print("updated packages.lock.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
