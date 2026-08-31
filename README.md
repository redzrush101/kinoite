# kinoite

Personal, signed Fedora Atomic KDE image based on `ghcr.io/ublue-os/kinoite-main:latest`.

The image layers host-integrated virtualization, Android/device tooling, encrypted DNS defaults, and a small set of system packages onto Universal Blue Kinoite. Desktop applications are installed from Flathub. Homebrew manages the user-facing Node and AI command-line tools after boot.

This image is intentionally machine-specific: it enables AMD IOMMU/VFIO settings, configures GPU passthrough for fixed PCI addresses, uses the `yassin` account, and enables SDDM autologin. Review those settings before installing it on another computer.

## Automated updates

No package versions need to be maintained manually:

- Fedora RPMs and the base image follow the current `latest` Universal Blue build.
- Flatpaks and Homebrew packages use their upstream update mechanisms.
- Custom release binaries are recorded in `files/packages.lock.json` with exact SHA-256 checksums or Git commits. The scheduled `update packages` workflow discovers upstream releases and commits lock-file updates automatically.
- GitHub Actions are commit-pinned for supply-chain safety and updated by Dependabot.

The lock file is deliberate: it makes each build verifiable without turning package updates into a manual task.

## Repository setup

GitHub Actions needs the `SIGNING_SECRET` repository secret matching the committed `cosign.pub`.

The existing `ghcr.io/redzrush101/kinoite` package must also grant this repository write access. Open the package's **Package settings**, then under **Manage Actions access** add `redzrush101/kinoite` with the **Write** role. The recipe includes the OCI source label so future package versions remain associated with this repository.

## Build and validate

On a Fedora/Universal Blue host with BlueBuild installed:

```bash
just validate
just build
```

Pull requests build the complete image without publishing it. Pushes to `main` and the daily schedule build, sign, and publish the image.

## Install

The first rebase establishes trust in the image; the second switches to signature verification:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/redzrush101/kinoite:latest
systemctl reboot
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/redzrush101/kinoite:latest
systemctl reboot
```
