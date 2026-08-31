#!/usr/bin/env bash
set -euo pipefail

# These are machine defaults that are safe to bake into an ostree image.
ln -sfn /usr/share/zoneinfo/Europe/Berlin /etc/localtime
printf 'LANG=de_DE.UTF-8\n' > /etc/locale.conf

# Libvirt's Fedora default is modular daemons. Managed hostdev entries normally
# handle PCI detach and reattach; the hook also recovers devices left on VFIO,
# verifies that amdgpu and DRM are ready, and only then restores the desktop.
install -d -m 0755 /etc/libvirt/hooks
install -m 0755 /usr/share/kinoite/vfio-qemu-hook /etc/libvirt/hooks/qemu
