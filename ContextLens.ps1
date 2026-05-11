#requires -version 7.0
[CmdletBinding()]
param(
    [switch]$NoUI
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RootPath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Path $MyInvocation.MyCommand.Path -Parent }
$script:AppMetadataPath = Join-Path $script:RootPath 'app-metadata.json'
$script:InstallerPath = Join-Path $script:RootPath 'Install.ps1'
$script:InstallerLogPath = Join-Path $script:RootPath 'logs\installer.log'
$script:StatePath = Join-Path $script:RootPath 'state'
$script:ExitApplicationHostRequested = $false
$script:E = [char]27
$script:C = @{
    H1      = "$($script:E)[38;2;90;180;240m"
    H2      = "$($script:E)[38;2;140;160;180m"
    OK      = "$($script:E)[38;2;46;204;113m"
    Warn    = "$($script:E)[38;2;241;196;15m"
    Fail    = "$($script:E)[38;2;231;76;60m"
    Info    = "$($script:E)[38;2;52;152;219m"
    Dim     = "$($script:E)[38;2;100;110;120m"
    White   = "$($script:E)[38;2;220;225;230m"
    SelBg   = "$($script:E)[48;2;40;80;120m"
    SelFg   = "$($script:E)[38;2;255;255;255m"
    Bold    = "$($script:E)[1m"
    Reset   = "$($script:E)[0m"
    EraseLn = "$($script:E)[K"
}

$script:AppName = 'ContextLens'
$script:AppVersion = '0.0.0'
$script:AppGitHubRepo = 'joty79/ContextLens'
$script:AppUpdateStatus = $null

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-OptionalObjectPropertyValue {
    param(
        [object]$InputObject,
        [string]$PropertyName,
        [AllowEmptyString()][string]$DefaultValue = ''
    )

    if ($null -eq $InputObject) { return $DefaultValue }
    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) { return $DefaultValue }
    return [string]$property.Value
}

function Initialize-AppMetadata {
    if (-not (Test-Path -LiteralPath $script:AppMetadataPath -PathType Leaf)) { return }

    $metadata = Read-JsonFile -Path $script:AppMetadataPath
    $name = Get-OptionalObjectPropertyValue -InputObject $metadata -PropertyName 'app_name'
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = Get-OptionalObjectPropertyValue -InputObject $metadata -PropertyName 'name'
    }
    if (-not [string]::IsNullOrWhiteSpace($name)) { $script:AppName = $name }

    $version = Get-OptionalObjectPropertyValue -InputObject $metadata -PropertyName 'version'
    if (-not [string]::IsNullOrWhiteSpace($version)) { $script:AppVersion = $version }

    $repo = Get-OptionalObjectPropertyValue -InputObject $metadata -PropertyName 'github_repo'
    if ([string]::IsNullOrWhiteSpace($repo)) {
        $repo = Get-OptionalObjectPropertyValue -InputObject $metadata -PropertyName 'repo'
    }
    if (-not [string]::IsNullOrWhiteSpace($repo)) { $script:AppGitHubRepo = $repo }
}

function Get-UiWidth {
    try { return [Math]::Min(100, $Host.UI.RawUI.WindowSize.Width - 2) }
    catch { return 80 }
}

function Begin-SyncRender { [Console]::Write("$($script:E)[?2026h") }
function End-SyncRender { [Console]::Write("$($script:E)[?2026l") }

function Set-CursorVisibleSafe {
    param([bool]$Visible)
    try { [Console]::CursorVisible = $Visible } catch {}
}

function Clear-ConsoleInputBuffer {
    try {
        while ([Console]::KeyAvailable) { [void][Console]::ReadKey($true) }
    } catch {}
}

function Read-ConsoleKey {
    Set-CursorVisibleSafe -Visible $false
    try {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } catch {
        $keyInfo = [Console]::ReadKey($true)
    }

    $keyName = ''
    $keyChar = [char]0
    $virtualKeyCode = 0

    if ($keyInfo.PSObject.Properties['Key']) {
        $keyName = [string]$keyInfo.Key
    }
    elseif ($keyInfo.PSObject.Properties['VirtualKeyCode']) {
        $virtualKeyCode = [int]$keyInfo.VirtualKeyCode
        try {
            $keyName = [string][System.Enum]::ToObject([System.ConsoleKey], $virtualKeyCode)
        } catch {
            $keyName = [string]$virtualKeyCode
        }
    }

    if ($keyInfo.PSObject.Properties['KeyChar']) {
        $keyChar = [char]$keyInfo.KeyChar
    }
    elseif ($keyInfo.PSObject.Properties['Character']) {
        $keyChar = [char]$keyInfo.Character
    }

    if ($virtualKeyCode -eq 27 -or [int]$keyChar -eq 27) { $keyName = 'Escape' }
    if ($virtualKeyCode -eq 13 -or [int]$keyChar -eq 13) { $keyName = 'Enter' }
    if ($keyName -eq 'Esc') { $keyName = 'Escape' }
    if ($keyName -eq 'Return') { $keyName = 'Enter' }
    return [pscustomobject]@{ Key = $keyName; KeyChar = $keyChar; VirtualKeyCode = $virtualKeyCode }
}

function Write-Section {
    param([string]$Title)
    $w = Get-UiWidth
    $prefix = " $Title "
    $line = [string]::new([char]0x2500, [Math]::Max(0, $w - $prefix.Length - 1))
    Write-Host ''
    Write-Host "$($script:C.H1)$prefix$($script:C.Dim)$line$($script:C.Reset)"
}

function Get-ShortGitCommitText {
    param([AllowEmptyString()][string]$Commit)
    if ([string]::IsNullOrWhiteSpace($Commit)) { return '' }
    $trimmed = $Commit.Trim()
    if ($trimmed.Length -le 7) { return $trimmed }
    return $trimmed.Substring(0, 7)
}

function New-AppUpdateStatusObject {
    param(
        [string]$LatestVersion = '',
        [string]$LocalCommit = '',
        [string]$LatestCommit = '',
        [string]$SourceKind = 'Unknown',
        [bool]$HasLocalChanges = $false,
        [string]$Branch = 'master',
        [ValidateSet('Unknown', 'UpToDate', 'UpdateAvailable', 'LocalAhead', 'WorkspaceModified', 'Error')]
        [string]$Status = 'Unknown',
        [string]$Message = 'Update status has not been checked yet.',
        [string]$CheckedAt = '',
        [string]$Error = ''
    )

    [pscustomobject]@{
        LocalVersion    = $script:AppVersion
        LatestVersion   = $LatestVersion
        LocalCommit     = $LocalCommit
        LatestCommit    = $LatestCommit
        SourceKind      = $SourceKind
        HasLocalChanges = $HasLocalChanges
        Repo            = $script:AppGitHubRepo
        Branch          = $Branch
        Status          = $Status
        Message         = $Message
        CheckedAt       = $CheckedAt
        Error           = $Error
    }
}

function Get-CurrentAppSourceInfo {
    $result = [ordered]@{ Commit = ''; SourceKind = 'Unknown'; HasLocalChanges = $false }
    $installMetaPath = Join-Path $script:RootPath 'state\install-meta.json'
    if (Test-Path -LiteralPath $installMetaPath -PathType Leaf) {
        try {
            $installMeta = Read-JsonFile -Path $installMetaPath
            $commit = Get-OptionalObjectPropertyValue -InputObject $installMeta -PropertyName 'github_commit'
            if (-not [string]::IsNullOrWhiteSpace($commit)) {
                $result.Commit = $commit
                $result.SourceKind = 'Installed'
                return [pscustomobject]$result
            }
        } catch {}
    }

    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        try {
            $inside = (& git.exe -C $script:RootPath rev-parse --is-inside-work-tree 2>$null | Out-String).Trim()
            if ($inside -eq 'true') {
                $result.Commit = (& git.exe -C $script:RootPath rev-parse HEAD 2>$null | Out-String).Trim()
                $dirty = (& git.exe -C $script:RootPath status --porcelain 2>$null | Out-String).Trim()
                $result.SourceKind = 'Workspace'
                $result.HasLocalChanges = -not [string]::IsNullOrWhiteSpace($dirty)
            }
        } catch {}
    }

    return [pscustomobject]$result
}

function Get-RemoteAppMetadata {
    $branch = 'master'
    $latestCommit = ''
    if (Get-Command git.exe -ErrorAction SilentlyContinue) {
        try {
            $remoteLine = (& git.exe -C $script:RootPath ls-remote "https://github.com/$($script:AppGitHubRepo).git" "refs/heads/$branch" 2>$null | Select-Object -First 1 | Out-String).Trim()
            if (-not [string]::IsNullOrWhiteSpace($remoteLine)) {
                $latestCommit = ($remoteLine -split '\s+')[0]
            }
        } catch {}
    }

    $latestVersion = ''
    try {
        $rawUrl = "https://raw.githubusercontent.com/$($script:AppGitHubRepo)/$branch/app-metadata.json"
        $remoteMetadata = Invoke-RestMethod -Uri $rawUrl -TimeoutSec 8 -ErrorAction Stop
        $latestVersion = Get-OptionalObjectPropertyValue -InputObject $remoteMetadata -PropertyName 'version'
    } catch {}

    if ([string]::IsNullOrWhiteSpace($latestCommit) -and [string]::IsNullOrWhiteSpace($latestVersion)) {
        return $null
    }

    [pscustomobject]@{
        Branch = $branch
        Commit = $latestCommit
        LatestVersion = $latestVersion
    }
}

function Resolve-AppUpdateStatus {
    $source = Get-CurrentAppSourceInfo
    $remote = Get-RemoteAppMetadata
    if ($null -eq $remote) {
        $script:AppUpdateStatus = New-AppUpdateStatusObject -LocalCommit $source.Commit -SourceKind $source.SourceKind -HasLocalChanges $source.HasLocalChanges -Status 'Error' -Message 'Could not reach GitHub to check the latest version.' -CheckedAt ((Get-Date).ToString('s'))
        return $script:AppUpdateStatus
    }

    $statusName = 'UpToDate'
    $message = "ContextLens is up to date with GitHub $($remote.Branch)."
    if ($source.SourceKind -eq 'Workspace' -and $source.HasLocalChanges) {
        $statusName = 'WorkspaceModified'
        $message = 'This workspace has unpublished local changes.'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($remote.LatestVersion) -and [version]$script:AppVersion -lt [version]$remote.LatestVersion) {
        $statusName = 'UpdateAvailable'
        $message = "Update available from GitHub $($remote.Branch): v$($remote.LatestVersion)."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($source.Commit) -and -not [string]::IsNullOrWhiteSpace($remote.Commit) -and $source.Commit -ne $remote.Commit) {
        $statusName = 'UpdateAvailable'
        $message = "Update available from GitHub $($remote.Branch): newer commit $(Get-ShortGitCommitText -Commit $remote.Commit)."
    }

    $script:AppUpdateStatus = New-AppUpdateStatusObject -LatestVersion $remote.LatestVersion -LocalCommit $source.Commit -LatestCommit $remote.Commit -SourceKind $source.SourceKind -HasLocalChanges $source.HasLocalChanges -Branch $remote.Branch -Status $statusName -Message $message -CheckedAt ((Get-Date).ToString('s'))
    return $script:AppUpdateStatus
}

function Get-AppUpdateStatusPresentation {
    if ($null -eq $script:AppUpdateStatus) { [void](Resolve-AppUpdateStatus) }
    $status = $script:AppUpdateStatus
    $color = switch ($status.Status) {
        'UpToDate' { $script:C.OK }
        'UpdateAvailable' { $script:C.Warn }
        'WorkspaceModified' { $script:C.Info }
        'LocalAhead' { $script:C.Info }
        'Error' { $script:C.Fail }
        default { $script:C.Dim }
    }
    $label = switch ($status.Status) {
        'UpToDate' { "Up to date with GitHub $($status.Branch)" }
        'UpdateAvailable' { "Update available from GitHub $($status.Branch)" }
        'WorkspaceModified' { 'Workspace has unpublished local changes' }
        'Error' { 'Update check failed' }
        default { 'Status unknown' }
    }
    [pscustomobject]@{ Label = $label; Color = $color; Status = $status }
}

function Show-Banner {
    try { Clear-Host } catch {}
    $w = Get-UiWidth
    $border = [string]::new([char]0x2550, ($w - 2))
    $titleText = " $script:AppName v$script:AppVersion"
    $subText = ' OCR + Clipboard Image Tools'
    $update = Get-AppUpdateStatusPresentation
    $updateText = " Update: $($update.Label)"

    Write-Host ''
    Write-Host "$($script:C.H1)$([char]0x2554)$border$([char]0x2557)$($script:C.Reset)"
    foreach ($row in $rows = @(
        @{ Text = $titleText; Color = "$($script:C.Bold)$($script:C.White)" },
        @{ Text = $subText; Color = $script:C.Dim },
        @{ Text = $updateText; Color = $update.Color }
    )) {
        $pad = [Math]::Max(0, $w - 2 - $row.Text.Length)
        Write-Host "$($script:C.H1)$([char]0x2551)$($row.Color)$($row.Text)$($script:C.Reset)$(' ' * $pad)$($script:C.H1)$([char]0x2551)$($script:C.Reset)"
    }
    Write-Host "$($script:C.H1)$([char]0x255A)$border$([char]0x255D)$($script:C.Reset)"
}

function Show-MenuOptions {
    param([string]$Title, [string[]]$Options, [int]$SelectedIndex = 0)
    Write-Section $Title
    for ($i = 0; $i -lt $Options.Count; $i++) {
        if ($i -eq $SelectedIndex) {
            Write-Host "$($script:C.SelBg)$($script:C.SelFg)$($script:C.Bold)  > $($Options[$i]) $($script:C.Reset)$($script:C.EraseLn)"
        } else {
            Write-Host "    $($script:C.White)$($Options[$i])$($script:C.Reset)$($script:C.EraseLn)"
        }
    }
}

function Get-AppInstallerAction {
    $source = Get-CurrentAppSourceInfo
    if ($source.SourceKind -eq 'Installed') { return 'UpdateGitHub' }
    if ($source.SourceKind -eq 'Workspace') { return 'WorkspaceGitPull' }
    return 'DownloadLatest'
}

function Get-RecentTextFileLines {
    param([string]$Path, [int]$TailCount = 10)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    return @(Get-Content -LiteralPath $Path -Tail $TailCount -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
}

function Show-AppUpdateResultPanel {
    param([string]$ResultMessage, [string]$Level = 'Info', [string[]]$RecentLines = @(), [switch]$AutoRestart)
    $color = switch ($Level) { 'Good' { $script:C.OK } 'Warn' { $script:C.Warn } 'Error' { $script:C.Fail } default { $script:C.Info } }
    Begin-SyncRender
    Show-Banner
    Write-Section 'Update App'
    Write-Host "  $color$ResultMessage$($script:C.Reset)$($script:C.EraseLn)"
    if ($RecentLines.Count -gt 0) {
        Write-Section 'Recent Output'
        foreach ($line in @($RecentLines | Select-Object -Last 10)) {
            if ($line.Length -gt 110) { $line = $line.Substring(0, 107) + '...' }
            Write-Host "  $($script:C.Dim)$line$($script:C.Reset)$($script:C.EraseLn)"
        }
    }
    Write-Section 'Commands'
    if ($AutoRestart) {
        Write-Host "  $($script:C.OK)Restarting ContextLens...$($script:C.Reset)$($script:C.EraseLn)"
    } else {
        Write-Host "  $($script:C.Fail)$($script:C.Bold)ESC$($script:C.Reset) $($script:C.Dim)back$($script:C.Reset)$($script:C.EraseLn)"
    }
    Write-Host "$($script:E)[J" -NoNewline
    End-SyncRender
}

function Start-UpdatedAppHost {
    $appPath = Join-Path $script:RootPath 'ContextLens.ps1'
    if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) { return $false }
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($null -ne $wt) {
        Start-Process -FilePath $wt.Source -ArgumentList @('-w', 'new', 'nt', '--title', 'ContextLens', 'pwsh.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $appPath) | Out-Null
        return $true
    }
    Start-Process -FilePath 'pwsh.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $appPath) | Out-Null
    return $true
}

function Invoke-InPlaceAppUpdate {
    param([ValidateSet('UpdateGitHub', 'DownloadLatest', 'WorkspaceGitPull')][string]$Action)
    if ($Action -eq 'WorkspaceGitPull') {
        Show-AppUpdateResultPanel -ResultMessage 'Updating this git workspace with fetch + fast-forward pull...' -Level 'Info'
        & git.exe -C $script:RootPath fetch origin master
        if ($LASTEXITCODE -ne 0) { Show-AppUpdateResultPanel -ResultMessage 'git fetch failed.' -Level 'Error'; [void](Read-ConsoleKey); return $false }
        & git.exe -C $script:RootPath pull --ff-only origin master
        if ($LASTEXITCODE -ne 0) { Show-AppUpdateResultPanel -ResultMessage 'git pull --ff-only failed.' -Level 'Error'; [void](Read-ConsoleKey); return $false }
        Show-AppUpdateResultPanel -ResultMessage 'Update finished. Restarting the updated app host and closing this window...' -Level 'Good' -AutoRestart
        Start-Sleep -Milliseconds 700
        if (Start-UpdatedAppHost) { $script:ExitApplicationHostRequested = $true; return $true }
        return $false
    }

    if (-not (Test-Path -LiteralPath $script:InstallerPath -PathType Leaf)) {
        Show-AppUpdateResultPanel -ResultMessage 'Install.ps1 was not found next to the app.' -Level 'Error'
        [void](Read-ConsoleKey)
        return $false
    }

    $stdoutPath = Join-Path $env:TEMP ("ContextLens_updater_out_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $stderrPath = Join-Path $env:TEMP ("ContextLens_updater_err_{0}.log" -f [guid]::NewGuid().ToString('N'))
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:InstallerPath, '-Action', $Action, '-Force')
    if ($Action -eq 'UpdateGitHub') { $args += '-NoExplorerRestart' }
    if ($Action -eq 'DownloadLatest') { $args += '-NoSelfRelaunch' }

    $process = Start-Process -FilePath 'pwsh.exe' -ArgumentList $args -WorkingDirectory $script:RootPath -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
    while (-not $process.HasExited) {
        $recent = @((Get-RecentTextFileLines -Path $script:InstallerLogPath -TailCount 8) + (Get-RecentTextFileLines -Path $stderrPath -TailCount 3))
        Show-AppUpdateResultPanel -ResultMessage 'Updating inside the current app session...' -Level 'Info' -RecentLines $recent
        Start-Sleep -Milliseconds 250
    }
    $process.Refresh()
    $recentLines = @((Get-RecentTextFileLines -Path $script:InstallerLogPath -TailCount 8) + (Get-RecentTextFileLines -Path $stderrPath -TailCount 5))
    if ([int]$process.ExitCode -le 2) {
        Show-AppUpdateResultPanel -ResultMessage 'Update finished. Restarting the updated app host and closing this window...' -Level 'Good' -RecentLines $recentLines -AutoRestart
        Start-Sleep -Milliseconds 700
        if (Start-UpdatedAppHost) { $script:ExitApplicationHostRequested = $true; return $true }
        return $false
    }
    Show-AppUpdateResultPanel -ResultMessage ("Update failed with exit code {0}." -f [int]$process.ExitCode) -Level 'Error' -RecentLines $recentLines
    [void](Read-ConsoleKey)
    return $false
}

function Show-AppUpdateMenu {
    $selectedIndex = 0
    $options = @('Run update now', 'Refresh update status', 'Back')
    while ($true) {
        $statusPresentation = Get-AppUpdateStatusPresentation
        $status = $statusPresentation.Status
        $action = Get-AppInstallerAction
        $target = switch ($action) { 'UpdateGitHub' { 'Installed app copy' } 'WorkspaceGitPull' { 'Git workspace copy' } default { 'Downloaded working copy' } }
        $method = switch ($action) { 'UpdateGitHub' { 'Installer/GitHub in-place update' } 'WorkspaceGitPull' { 'git fetch + fast-forward pull' } default { 'InstallerCore DownloadLatest' } }
        $latestVersion = if ([string]::IsNullOrWhiteSpace($status.LatestVersion)) { '--' } else { $status.LatestVersion }
        $localCommit = Get-ShortGitCommitText -Commit $status.LocalCommit
        if ([string]::IsNullOrWhiteSpace($localCommit)) { $localCommit = '--' }
        $latestCommit = Get-ShortGitCommitText -Commit $status.LatestCommit
        if ([string]::IsNullOrWhiteSpace($latestCommit)) { $latestCommit = '--' }
        $checkedAt = if ([string]::IsNullOrWhiteSpace($status.CheckedAt)) { '--' } else { $status.CheckedAt.Replace('T', ' ') }

        Begin-SyncRender
        Show-Banner
        Write-Section 'Update App'
        Write-Host "  $($script:C.H2)Current version:$($script:C.Reset) $($script:C.White)$script:AppVersion$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Latest version:$($script:C.Reset) $($script:C.White)$latestVersion$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Current commit:$($script:C.Reset) $($script:C.White)$localCommit$($script:C.Reset) $($script:C.Dim)|$($script:C.Reset) $($script:C.H2)Latest commit:$($script:C.Reset) $($script:C.White)$latestCommit$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Current source:$($script:C.Reset) $($script:C.White)$($status.SourceKind)$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Status:$($script:C.Reset) $($statusPresentation.Color)$($statusPresentation.Label)$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Repo:$($script:C.Reset) $($script:C.White)$($status.Repo)$($script:C.Reset) $($script:C.Dim)|$($script:C.Reset) $($script:C.H2)Branch:$($script:C.Reset) $($script:C.White)$($status.Branch)$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Update target:$($script:C.Reset) $($script:C.White)$target$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Method:$($script:C.Reset) $($script:C.White)$method$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Last check:$($script:C.Reset) $($script:C.White)$checkedAt$($script:C.Reset)$($script:C.EraseLn)"
        if (-not [string]::IsNullOrWhiteSpace($status.Message)) { Write-Host "  $($script:C.Dim)$($status.Message)$($script:C.Reset)$($script:C.EraseLn)" }
        Show-MenuOptions -Title 'Actions' -Options $options -SelectedIndex $selectedIndex
        Write-Host ''
        Write-Host "  $($script:C.Dim)Up/Down navigate   Enter = select   Esc = back$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "$($script:E)[J" -NoNewline
        End-SyncRender

        $key = Read-ConsoleKey
        switch ($key.Key) {
            'UpArrow' { $selectedIndex = [Math]::Max(0, $selectedIndex - 1) }
            'DownArrow' { $selectedIndex = [Math]::Min($options.Count - 1, $selectedIndex + 1) }
            'Escape' { return $false }
            'Enter' {
                switch ($selectedIndex) {
                    0 { if (Invoke-InPlaceAppUpdate -Action $action) { return $true } }
                    1 { [void](Resolve-AppUpdateStatus) }
                    2 { return $false }
                }
            }
        }
    }
}

function Show-MainMenu {
    $selectedIndex = 0
    $options = @('Update app', 'Open install logs', 'Open install folder', 'Exit')
    while ($true) {
        Begin-SyncRender
        Show-Banner
        Write-Section 'Current Context Menu'
        Write-Host "  $($script:C.H2)Image files:$($script:C.Reset) $($script:C.White)ContextLens > OCR image to TXT$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "  $($script:C.H2)Folder background:$($script:C.Reset) $($script:C.White)ContextLens > Save clipboard image / OCR clipboard to TXT$($script:C.Reset)$($script:C.EraseLn)"
        Show-MenuOptions -Title 'Main Menu' -Options $options -SelectedIndex $selectedIndex
        Write-Host ''
        Write-Host "  $($script:C.Dim)Up/Down navigate   Enter = select   Esc = exit$($script:C.Reset)$($script:C.EraseLn)"
        Write-Host "$($script:E)[J" -NoNewline
        End-SyncRender

        $key = Read-ConsoleKey
        switch ($key.Key) {
            'UpArrow' { $selectedIndex = [Math]::Max(0, $selectedIndex - 1) }
            'DownArrow' { $selectedIndex = [Math]::Min($options.Count - 1, $selectedIndex + 1) }
            'Escape' { return }
            'Enter' {
                switch ($selectedIndex) {
                    0 { if (Show-AppUpdateMenu) { return } }
                    1 { if (Test-Path -LiteralPath $script:InstallerLogPath) { Start-Process notepad.exe -ArgumentList @($script:InstallerLogPath) } }
                    2 { Start-Process explorer.exe -ArgumentList @($script:RootPath) }
                    3 { return }
                }
            }
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $script:StatePath -PathType Container)) {
        New-Item -ItemType Directory -Path $script:StatePath -Force | Out-Null
    }
    Initialize-AppMetadata
    [void](Resolve-AppUpdateStatus)
    if ($NoUI) {
        Show-Banner
        Write-Section 'Headless Smoke'
        Write-Host "  $($script:C.OK)Initialization completed.$($script:C.Reset)$($script:C.EraseLn)"
    } else {
        Show-MainMenu
    }
}
finally {
    Set-CursorVisibleSafe -Visible $true
    try { Write-Host "$($script:E)[?7h$($script:E)[?25h" -NoNewline } catch {}
}

if ($script:ExitApplicationHostRequested) {
    exit 0
}
