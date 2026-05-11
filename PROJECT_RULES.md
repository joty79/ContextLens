# PROJECT_RULES - ContextLens

## Scope

- Repo: `D:\Users\joty79\scripts\ContextLens`
- Purpose: Explorer context menu workspace for Lens OCR and clipboard image capture tools.

## Current Workflow

- Keep `Install.ps1` generated from `InstallerCore`; do not hand-maintain installer logic here.
- Keep actual context action behavior in `Invoke-ContextLens.ps1`.
- Keep Explorer launch behavior in `Launch-ContextLens.vbs` so context menu actions stay hidden.
- The `Manager` action must open the generated InstallerCore `Install.ps1` in Windows Terminal, not a bespoke plain PowerShell menu.
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

### Entry - 2026-05-11 (Manager opens InstallerCore in Windows Terminal)

- Date: 2026-05-11
- Problem: The first ContextLens Manager opened a plain custom PowerShell menu, so it did not look or behave like the normal InstallerCore workflow.
- Root cause: The initial manager was implemented as a repo-local maintenance wrapper instead of launching the generated `Install.ps1`.
- Guardrail/rule: The context menu Manager action opens `Install.ps1` through `wt.exe`. Keep bespoke UI out of ContextLens until a real downstream UI contract is intentionally designed.
- Files affected: `Launch-ContextLens.vbs`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: PowerShell parser validation for `Invoke-ContextLens.ps1`, `Manage-ContextLens.ps1`, and generated `Install.ps1`; elevated legacy registry cleanup via direct `gsudo.exe reg.exe delete` for HKCR keys; non-admin local install with `-NoExplorerRestart`; `reg.exe` readback for Manager commands under file, folder-background, and desktop-background branches; GitHub update smoke planned after commit/push.
