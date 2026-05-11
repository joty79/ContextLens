#requires -version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
$installer = Join-Path -Path $root -ChildPath 'Install.ps1'
$logPath = Join-Path -Path $root -ChildPath 'logs\installer.log'

function Invoke-Installer {
    param([Parameter(Mandatory)][string[]]$InstallerArgs)

    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
        throw "Install.ps1 not found: $installer"
    }

    & $installer @InstallerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Installer exited with code $LASTEXITCODE"
    }
}

function Open-Log {
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Start-Process notepad.exe -ArgumentList @($logPath)
        return
    }
    Write-Host "No installer log found yet: $logPath" -ForegroundColor Yellow
}

while ($true) {
    Clear-Host
    Write-Host 'ContextLens Manager' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '[1] Update from GitHub'
    Write-Host '[2] Repair/install from this folder'
    Write-Host '[3] Open install logs'
    Write-Host '[4] Uninstall'
    Write-Host '[Q] Quit'
    Write-Host ''

    $choice = Read-Host 'Choose an action'
    switch (($choice ?? '').Trim().ToUpperInvariant()) {
        '1' {
            Invoke-Installer -InstallerArgs @('-Action', 'UpdateGitHub', '-Force', '-NoExplorerRestart')
            Read-Host 'Done. Press Enter to continue'
        }
        '2' {
            Invoke-Installer -InstallerArgs @('-Action', 'Install', '-PackageSource', 'Local', '-Force', '-NoExplorerRestart')
            Read-Host 'Done. Press Enter to continue'
        }
        '3' {
            Open-Log
            Start-Sleep -Seconds 1
        }
        '4' {
            Invoke-Installer -InstallerArgs @('-Action', 'Uninstall', '-Force', '-NoExplorerRestart')
            Read-Host 'Done. Press Enter to continue'
        }
        'Q' {
            return
        }
        default {
            Write-Host 'Unknown choice.' -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
