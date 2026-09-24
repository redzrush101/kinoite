#!/usr/bin/env bash
set -euo pipefail

lock="${CONFIG_DIRECTORY:-/tmp/files}/packages.lock.json"
[[ -r "$lock" ]]
[[ "$(uname -m)" == x86_64 ]]

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

field() {
  python3 - "$lock" "$1" "$2" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    print(json.load(f)[sys.argv[2]][sys.argv[3]])
PY
}

download() {
  local name="$1" out="$2" url sha256
  url="$(field "$name" url)"
  sha256="$(field "$name" sha256)"
  curl --fail --location --retry 5 --retry-all-errors --connect-timeout 20 "$url" --output "$out"
  printf '%s  %s\n' "$sha256" "$out" | sha256sum --check --strict -
}

find_one() {
  local root="$1" name="$2" path
  path="$(find "$root" -type f -name "$name" -print -quit)"
  [[ -n "$path" ]] || { echo "missing $name in $root" >&2; return 1; }
  printf '%s\n' "$path"
}

# Android udev rules.
download android-udev-rules "$work/51-android.rules"
install -Dm0644 "$work/51-android.rules" /usr/lib/udev/rules.d/51-android.rules

# iLoader.
download iloader "$work/iloader.rpm"
dnf5 install -y --setopt=install_weak_deps=False "$work/iloader.rpm"

# samloader-rs. Accept the current ZIP format and the previous tar.xz format.
samloader_asset="$(field samloader asset)"
samloader_archive="$work/$samloader_asset"
samloader_dir="$work/samloader"
download samloader "$samloader_archive"
mkdir "$samloader_dir"
case "$samloader_asset" in
  *.zip) unzip -q "$samloader_archive" -d "$samloader_dir" ;;
  *.tar.xz) tar -xJf "$samloader_archive" -C "$samloader_dir" ;;
  *) echo "unsupported samloader archive: $samloader_asset" >&2; exit 1 ;;
esac
install -Dm0755 "$(find_one "$samloader_dir" samloader)" /usr/bin/samloader
cat > /usr/lib/udev/rules.d/60-samloader.rules <<'EOF'
SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", TAG+="uaccess"
EOF

# UAD-ng. The immutable image owns /usr/bin/uad-ng; updates arrive with rebuilds.
download uad-ng "$work/uad-ng"
install -Dm0755 "$work/uad-ng" /usr/bin/uad-ng
cat > /usr/share/applications/uad-ng.desktop <<'EOF'
[Desktop Entry]
Name=UAD-ng
Comment=Universal Android Debloater Next Generation
Exec=uad-ng
Icon=phone
Terminal=false
Type=Application
Categories=Utility;Development;
EOF

# MTKClient in a locked uv environment.
mtk_repo="$(field mtkclient repository)"
mtk_tag="$(field mtkclient tag)"
mtk_commit="$(field mtkclient commit)"
mtk_src=/usr/lib/kinoite/mtkclient-src
mtk_env=/usr/lib/kinoite/mtkclient
rm -rf "$mtk_src" "$mtk_env"
git clone --quiet --depth 1 --branch "$mtk_tag" "https://github.com/$mtk_repo.git" "$mtk_src"
[[ "$(git -C "$mtk_src" rev-parse HEAD)" == "$mtk_commit" ]]
rm -rf "$mtk_src/.git"

ln -s ../mtk.py ../mtk_gui.py ../stage2.py "$mtk_src/mtkclient/"
ln -s ../Tools "$mtk_src/mtkclient/Tools"

dnf5 install -y --setopt=install_weak_deps=False uv
UV_PROJECT_ENVIRONMENT="$mtk_env" UV_PYTHON_DOWNLOADS=never \
  uv sync --frozen --no-dev --project "$mtk_src" --python /usr/bin/python3
dnf5 remove -y uv

cat > /usr/libexec/kinoite-mtkclient <<'EOF'
#!/usr/bin/env bash
export FUSE_LIBRARY_PATH=/usr/lib64/libfuse3.so.4
exec "/usr/lib/kinoite/mtkclient/bin/$(basename "$0")" "$@"
EOF
chmod 0755 /usr/libexec/kinoite-mtkclient
for exe in mtk mtk_gui stage2 da_parser brom_to_offs; do
  [[ -x "$mtk_env/bin/$exe" ]] && ln -sfn /usr/libexec/kinoite-mtkclient "/usr/bin/$exe"
done
install -Dm0644 "$mtk_src/Setup/Linux/52-mtk.rules" /usr/lib/udev/rules.d/52-mtk.rules
install -Dm0644 "$mtk_src/mtkclient/gui/images/logo_256.png" /usr/share/icons/hicolor/256x256/apps/mtkclient.png
cat > /usr/share/applications/mtkclient.desktop <<'EOF'
[Desktop Entry]
Name=MTKClient
Comment=MediaTek flash and repair utility
Exec=mtk_gui
Icon=mtkclient
Terminal=false
Type=Application
Categories=Utility;Development;
EOF

# SP Flash Tool.
download sp-flash-tool "$work/sp-flash-tool.zip"
sp_dir="$work/sp"
mkdir "$sp_dir"
unzip -q "$work/sp-flash-tool.zip" -d "$sp_dir"
flash_bin="$(find_one "$sp_dir" flash_tool)"
flash_root="$(dirname "$flash_bin")"
install_root=/usr/lib/kinoite/sp-flash-tool
rm -rf "$install_root"
mkdir -p "$install_root"
cp -a "$flash_root"/. "$install_root"/
chmod 0755 "$install_root/flash_tool"

cat > /usr/bin/sp-flash-tool <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root=/usr/lib/kinoite/sp-flash-tool
export LD_LIBRARY_PATH="$root:$root/lib:$root/plugins:$root/plugins/imageformats:$root/plugins/codecs:$root/plugins/sqldrivers${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$root/plugins${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
export QT_QPA_PLATFORM_PLUGIN_PATH="$root/plugins"
exec "$root/flash_tool" "$@"
EOF
chmod 0755 /usr/bin/sp-flash-tool
ln -sfn sp-flash-tool /usr/bin/flash_tool

rule="$(find "$install_root" -type f -name '99-ttyacms.rules' -print -quit || true)"
[[ -z "$rule" ]] || install -Dm0644 "$rule" /usr/lib/udev/rules.d/99-sp-flash-tool.rules

ld_path="$install_root:$install_root/lib:$install_root/plugins"
if LD_LIBRARY_PATH="$ld_path" ldd "$install_root/flash_tool" | grep -Fq "not found"; then
  echo "SP Flash Tool has unresolved shared-library dependencies" >&2
  LD_LIBRARY_PATH="$ld_path" ldd "$install_root/flash_tool" >&2
  exit 1
fi

cat > /usr/share/applications/sp-flash-tool.desktop <<'EOF'
[Desktop Entry]
Name=SP Flash Tool
Comment=MediaTek Smart Phone Flash Tool
Exec=sp-flash-tool
Icon=phone
Terminal=false
Type=Application
Categories=Utility;Development;
EOF

# Build-time smoke tests.
command -v iloader >/dev/null
/usr/bin/samloader --help >/dev/null
/usr/bin/uad-ng --help >/dev/null 2>&1 || true
FUSE_LIBRARY_PATH=/usr/lib64/libfuse3.so.4 "$mtk_env/bin/python" \
  -c 'from mtkclient.mtk import main; from mtkclient.mtk_gui import main as gui_main'
