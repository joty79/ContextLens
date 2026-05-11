# Changelog

# 0.2.2 - 2026-05-11

- Fixed update-status display when GitHub raw metadata is stale but the installed commit already matches `origin/master`.

# 0.2.1 - 2026-05-11

- Fixed the ContextLens app menu crash in hosts where `ReadKey()` does not expose a `KeyChar` property.

# 0.2.0 - 2026-05-11

- Added a real `ContextLens.ps1` app UI with a main menu and `Update app` submenu modeled after the WinAppManager in-app update pattern.
- Changed the context menu Manager action to open the ContextLens app UI in Windows Terminal instead of opening the generated installer UI directly.

## 0.1.0 - 2026-05-11

- Created the initial ContextLens workspace.
- Combined Lens OCR and clipboard image actions behind a shared context menu launcher.
- Added a small ContextLens Manager for update, repair, logs, and uninstall actions.
- Prepared the project for InstallerCore-generated installation.
- Changed the context menu Manager action to open the generated InstallerCore installer in Windows Terminal.
