# PROJECT_RULES - ContextLens

## Scope

- Repo: `D:\Users\joty79\scripts\ContextLens`
- Purpose: Explorer context menu workspace for Lens OCR and clipboard image capture tools.

## Current Workflow

- Keep `Install.ps1` generated from `InstallerCore`; do not hand-maintain installer logic here.
- Keep actual context action behavior in `Invoke-ContextLens.ps1`.
- Keep Explorer launch behavior in `Launch-ContextLens.vbs` so context menu actions stay hidden.
- Use per-user registry keys under `HKCU\Software\Classes` unless a future requirement explicitly needs elevation.
- Keep icons and runtime assets repo-local under `assets`.

## Decision Log

### Entry - 2026-05-11 (Initial combined workspace)

- Date: 2026-05-11
- Problem: Lens OCR and SaveClipboardImage context menu actions were split across folders, duplicated launcher patterns, and mixed registry scopes.
- Root cause: The tools grew independently before there was a shared context menu workspace.
- Guardrail/rule: ContextLens is the shared workspace for OCR and clipboard image actions. Installer behavior belongs to `InstallerCore`; ContextLens owns action scripts, launcher scripts, metadata, assets, and project documentation.
- Files affected: `Invoke-ContextLens.ps1`, `Launch-ContextLens.vbs`, `Manage-ContextLens.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `assets\icons\*`.
- Validation/tests run: PowerShell parser validation for `Invoke-ContextLens.ps1`, `Manage-ContextLens.ps1`, generated `Install.ps1`, `InstallerCore\scripts\New-ToolInstaller.ps1`, and `InstallerCore\templates\Install.Template.ps1`; `profiles\ContextLens.json` parsed as JSON; generated `Install.ps1` from InstallerCore; non-admin local install smoke with `-NoExplorerRestart`; installed file readback; `reg.exe` readback for ContextLens file/background/desktop submenu keys; GitHub `UpdateGitHub` smoke from `joty79/ContextLens` `master`; `InstallerCore\scripts\Sync-InstallerCore.ps1 -VerifyOnly`.
