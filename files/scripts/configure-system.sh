#!/usr/bin/env bash
set -euo pipefail

# These are machine defaults that are safe to bake into an ostree image.
ln -sfn /usr/share/zoneinfo/Europe/Berlin /etc/localtime
printf 'LANG=de_DE.UTF-8\n' > /etc/locale.conf

# Libvirt's Fedora default is modular daemons. The hook only releases the host
# desktop; managed hostdev entries leave PCI detach and reattach to libvirt.
install -d -m 0755 /etc/libvirt/hooks
install -m 0755 /usr/share/kinoite/vfio-qemu-hook /etc/libvirt/hooks/qemu
