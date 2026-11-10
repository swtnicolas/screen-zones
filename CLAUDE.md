# screen-zones

ScreenZones, which splits displays into fixed zones that behave like independent monitors, as two apps that share no code:

- `linux/` — KWin script and tray widget for KDE Plasma 6 on Wayland. Installs and runs its tests on this machine.
- `macos/` — menu bar app in Swift. Builds only on the Mac that runs it: Gatekeeper blocks a downloaded build that Apple has not notarized, so it has no tag, workflow or release.

Each folder's `CLAUDE.md` covers that platform's engineering, and its scripts resolve paths from their own folder. Everything shared lives once at the root:

- `docs/decisiones.md` (Spanish) — the decisions for both apps. Shared parts are written once; a difference sits in the same section as "Solo en Linux" or "Solo en macOS" with its reason. Every newly approved decision goes there.
- `docs/images/` — the README screenshots.
- `assets/icon/AppIcon.svg` — the master icon. Linux installs it; macOS renders `macos/assets/icon/` from it.
- `README.md` (Spanish) — install and build for both.
- `.github/workflows/release.yml` — runs on `linux-v<version>` tags inside `linux/` and publishes the installer.

The display name is ScreenZones and the id is `local.screenzones` on both platforms. Both apps behave, read and are named the same; a difference is allowed only where the platform forces it. When the two disagree, the more correct version wins and is carried to the other platform. Compare the code, not only the docs, before calling them aligned.

The repo is public: no employer, work tool, machine identifier or personal data in files, screenshots or sample data.
