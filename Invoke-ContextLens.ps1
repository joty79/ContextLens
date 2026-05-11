#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('OcrFile', 'OcrClipboard', 'SaveClipboardImage', 'Manager')]
    [string]$Action,

    [AllowEmptyString()]
    [string]$TargetPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ContextLensRoot {
    if ($PSScriptRoot) {
        return $PSScriptRoot
    }
    return (Split-Path -Path $MyInvocation.MyCommand.Path -Parent)
}

function Get-LensExecutable {
    $configured = $env:CONTEXTLENS_LENS_SCAN
    if (-not [string]::IsNullOrWhiteSpace($configured) -and (Test-Path -LiteralPath $configured -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $configured).Path
    }

    $candidates = @(
        (Join-Path -Path (Get-ContextLensRoot) -ChildPath 'assets\bin\lens_scan.exe'),
        'E:\Compilers\miniconda\envs\lensocr\Scripts\lens_scan.exe'
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'lens_scan.exe was not found. Set CONTEXTLENS_LENS_SCAN or place lens_scan.exe under assets\bin.'
}

function Use-WideConsoleColumns {
    param([Parameter(Mandatory)][scriptblock]$ScriptBlock)

    $previousColumns = $env:COLUMNS
    try {
        $env:COLUMNS = '10000'
        & $ScriptBlock
    } finally {
        if ($null -eq $previousColumns) {
            Remove-Item Env:COLUMNS -ErrorAction SilentlyContinue
        } else {
            $env:COLUMNS = $previousColumns
        }
    }
}

function Resolve-TargetDirectory {
    param([AllowEmptyString()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return [Environment]::GetFolderPath('Desktop')
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent -PathType Container)) {
        return (Resolve-Path -LiteralPath $parent).Path
    }

    throw "Target directory not found: $Path"
}

function Save-ClipboardImageFile {
    param([Parameter(Mandatory)][string]$Directory)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $image = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $image) {
        throw 'No image found in clipboard.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $outputPath = Join-Path -Path $Directory -ChildPath ("clipboard_image_$timestamp.png")

    try {
        $image.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $image.Dispose()
    }

    return $outputPath
}

function Invoke-OcrFile {
    param([Parameter(Mandatory)][string]$ImagePath)

    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) {
        throw "Image not found: $ImagePath"
    }

    $lensExe = Get-LensExecutable
    $imageFullPath = (Resolve-Path -LiteralPath $ImagePath).Path
    $directory = Split-Path -Path $imageFullPath -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($imageFullPath)
    $outputPath = Join-Path -Path $directory -ChildPath ($baseName + '_OCR.txt')

    Use-WideConsoleColumns {
        & $lensExe $imageFullPath --quiet > $outputPath
        if ($LASTEXITCODE -ne 0) {
            throw "lens_scan failed with exit code $LASTEXITCODE"
        }
    }
}

function Invoke-OcrClipboard {
    param([Parameter(Mandatory)][string]$Directory)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $image = [System.Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $image) {
        throw 'No image found in clipboard.'
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $tempImagePath = Join-Path -Path $env:TEMP -ChildPath ("contextlens_clipboard_$timestamp.png")
    $outputPath = Join-Path -Path $Directory -ChildPath ("Clipboard_OCR_$timestamp.txt")
    $lensExe = Get-LensExecutable

    try {
        $image.Save($tempImagePath, [System.Drawing.Imaging.ImageFormat]::Png)
        Use-WideConsoleColumns {
            & $lensExe $tempImagePath --quiet > $outputPath
            if ($LASTEXITCODE -ne 0) {
                throw "lens_scan failed with exit code $LASTEXITCODE"
            }
        }
    } finally {
        if (Test-Path -LiteralPath $tempImagePath) {
            Remove-Item -LiteralPath $tempImagePath -Force -ErrorAction SilentlyContinue
        }
        $image.Dispose()
    }
}

switch ($Action) {
    'OcrFile' {
        Invoke-OcrFile -ImagePath $TargetPath
    }
    'OcrClipboard' {
        Invoke-OcrClipboard -Directory (Resolve-TargetDirectory -Path $TargetPath)
    }
    'SaveClipboardImage' {
        $null = Save-ClipboardImageFile -Directory (Resolve-TargetDirectory -Path $TargetPath)
    }
    'Manager' {
        & (Join-Path -Path (Get-ContextLensRoot) -ChildPath 'Manage-ContextLens.ps1')
    }
}
