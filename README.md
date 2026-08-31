# kinoite

Personal Fedora Atomic KDE image based on `ghcr.io/ublue-os/kinoite-main:latest`.

Host-integrated services and hardware tools are layered into the image; desktop apps use Flathub; Node/AI CLIs use Homebrew; upstream-only device tools are checksum-locked and refreshed automatically before the daily signed build.

## Install

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/redzrush101/kinoite:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/redzrush101/kinoite:latest
systemctl reboot
```

GitHub Actions requires the `SIGNING_SECRET` repository secret matching the committed `cosign.pub`.
