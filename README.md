# kinoite

Personal signed Fedora Atomic KDE image based on Universal Blue Kinoite.

Includes virtualization and on-demand single-GPU VFIO, Android flashing tools, strict encrypted DNS, selected RPMs and Flatpaks, and Homebrew-managed development tools.

> [!WARNING]
> This image is configured for the `yassin` account and fixed PCI devices `07:00.0`, `07:00.1`, `09:00.3`, and `09:00.4`. Review the machine-specific settings before using it elsewhere.

## Updates

RPMs, Flatpaks, the base image, and Homebrew packages follow their upstream update channels. Custom downloads are checksum-locked for reproducible builds and refreshed automatically by GitHub Actions; no package versions require manual maintenance.

## Build

Set the repository `SIGNING_SECRET` to the private key matching `cosign.pub`. Pull requests validate the complete image without publishing; pushes and scheduled runs publish to GHCR.

```bash
just validate
just build
```

## Install

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/redzrush101/kinoite:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/redzrush101/kinoite:latest
systemctl reboot
```
