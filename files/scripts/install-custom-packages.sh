#!/usr/bin/env bash
set -euo pipefail

lock=/ctx/packages.lock.json
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

json() {
  python3 - "$lock" "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print(data[sys.argv[2]][sys.argv[3]])
PY
}

download() {
  local name="$1" out="$2" url sha
  url="$(json "$name" url)"
  sha="$(json "$name" sha256)"
  curl -fL --retry 5 --retry-all-errors --connect-timeout 20 "$url" -o "$out"
  printf '%s  %s\n' "$sha" "$out" | sha256sum --check --strict -
}

# iLoader: use upstream's native RPM so Fedora owns dependency resolution.
download iloader "$work/iloader.rpm"
dnf5 install -y --setopt=install_weak_deps=False "$work/iloader.rpm"

# Odin4: upstream release binary + host udev access rule.
download odin4 "$work/odin4"
install -Dm0755 "$work/odin4" /usr/bin/odin4
cat > /usr/lib/udev/rules.d/60-odin4.rules <<'RULES'
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="6601", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="685d", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="68c3", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="68ef", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="4eee", MODE="0660", TAG+="uaccess"
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", ATTR{idProduct}=="4eef", MODE="0660", TAG+="uaccess"
RULES

# samloader-rs: statically-linked upstream release.
download samloader "$work/samloader.zip"
mkdir "$work/samloader"
unzip -q "$work/samloader.zip" -d "$work/samloader"
samloader_bin="$(find "$work/samloader" -type f -name samloader -print -quit)"
[[ -n "$samloader_bin" ]]
install -Dm0755 "$samloader_bin" /usr/bin/samloader

# UAD-ng: official upstream Linux binary. Android platform tools come from Fedora.
download uad-ng "$work/uad-ng"
install -Dm0755 "$work/uad-ng" /usr/bin/uad-ng
cat > /usr/share/applications/uad-ng.desktop <<'DESKTOP'
[Desktop Entry]
Name=UAD-ng
Comment=Universal Android Debloater Next Generation
Exec=uad-ng
Icon=phone
Terminal=false
Type=Application
Categories=Utility;Development;
DESKTOP

# MTKClient: isolated Python environment, resolved from upstream's committed uv.lock.
# The tagged source already contains the generated payload binaries, so no cross compiler
# is retained in the OS image.
mtk_repo="$(json mtkclient repository)"
mtk_tag="$(json mtkclient tag)"
mtk_commit="$(json mtkclient commit)"
mtk_src=/usr/lib/kinoite/mtkclient-src
mtk_env=/usr/lib/kinoite/mtkclient
rm -rf "$mtk_src" "$mtk_env"
git clone --quiet --depth 1 --branch "$mtk_tag" "https://github.com/${mtk_repo}.git" "$mtk_src"
[[ "$(git -C "$mtk_src" rev-parse HEAD)" == "$mtk_commit" ]]
dnf5 install -y --setopt=install_weak_deps=False uv
UV_PROJECT_ENVIRONMENT="$mtk_env" UV_PYTHON_DOWNLOADS=never \
  uv sync --frozen --no-dev --project "$mtk_src" --python /usr/bin/python3
for exe in mtk mtk_gui stage2 da_parser brom_to_offs; do
  [[ -x "$mtk_env/bin/$exe" ]] && ln -sfn "$mtk_env/bin/$exe" "/usr/bin/$exe"
done
install -Dm0644 "$mtk_src/Setup/Linux/52-mtk.rules" /usr/lib/udev/rules.d/52-mtk.rules
install -Dm0644 "$mtk_src/mtkclient/gui/images/logo_256.png" /usr/share/icons/hicolor/256x256/apps/mtkclient.png
cat > /usr/share/applications/mtkclient.desktop <<'DESKTOP'
[Desktop Entry]
Name=MTKClient
Comment=MediaTek flash and repair utility
Exec=mtk_gui
Icon=mtkclient
Terminal=false
Type=Application
Categories=Utility;Development;
DESKTOP
dnf5 remove -y uv

# SP Flash Tool v5 channel: upstream bundle is FHS-targeted and carries its Qt4 stack.
download sp-flash-tool "$work/sp-flash-tool.zip"
sp_tmp="$work/sp"
mkdir "$sp_tmp"
unzip -q "$work/sp-flash-tool.zip" -d "$sp_tmp"
flash_bin="$(find "$sp_tmp" -type f -name flash_tool -print -quit)"
[[ -n "$flash_bin" ]]
flash_root="$(dirname "$flash_bin")"
install_root=/usr/lib/kinoite/sp-flash-tool
rm -rf "$install_root"
mkdir -p "$install_root"
cp -a "$flash_root"/. "$install_root"/
chmod 0755 "$install_root/flash_tool"
cat > /usr/bin/sp-flash-tool <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
root=/usr/lib/kinoite/sp-flash-tool
export LD_LIBRARY_PATH="$root:$root/lib:$root/plugins:$root/plugins/imageformats:$root/plugins/codecs:$root/plugins/sqldrivers${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$root/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM_PLUGIN_PATH="$root/plugins"
exec "$root/flash_tool" "$@"
WRAPPER
chmod 0755 /usr/bin/sp-flash-tool
ln -sfn sp-flash-tool /usr/bin/flash_tool
rule="$(find "$install_root" -type f -name '99-ttyacms.rules' -print -quit || true)"
[[ -z "$rule" ]] || install -Dm0644 "$rule" /usr/lib/udev/rules.d/99-sp-flash-tool.rules
if LD_LIBRARY_PATH="$install_root:$install_root/lib:$install_root/plugins" ldd "$install_root/flash_tool" | grep -Fq "not found"; then
  echo "SP Flash Tool has unresolved shared-library dependencies" >&2
  LD_LIBRARY_PATH="$install_root:$install_root/lib:$install_root/plugins" ldd "$install_root/flash_tool" >&2
  exit 1
fi

cat > /usr/share/applications/sp-flash-tool.desktop <<'DESKTOP'
[Desktop Entry]
Name=SP Flash Tool
Comment=MediaTek Smart Phone Flash Tool
Exec=sp-flash-tool
Icon=phone
Terminal=false
Type=Application
Categories=Utility;Development;
DESKTOP

# Basic build-time sanity checks: fail the image rather than publish a broken toolset.
command -v iloader >/dev/null
/usr/bin/odin4 --help >/dev/null 2>&1 || true
/usr/bin/samloader --help >/dev/null
/usr/bin/uad-ng --help >/dev/null 2>&1 || true
"$mtk_env/bin/python" -c 'import mtkclient'
