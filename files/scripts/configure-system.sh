#!/usr/bin/env bash
set -euo pipefail

ln -sfn /usr/share/zoneinfo/Europe/Berlin /etc/localtime
printf 'LANG=de_DE.UTF-8\n' > /etc/locale.conf

install -d -m 0755 /etc/libvirt/hooks
install -m 0755 /usr/share/kinoite/vfio-qemu-hook /etc/libvirt/hooks/qemu
