param([switch]$Yes)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Yes) { $script:SungAssumeYes = $true }

$Root = Get-SungRoot
$Deps = Get-SungDeps

Write-Host 'Sung setup' -ForegroundColor Green
Add-SungToPath @('C:\Program Files\CMake\bin', 'C:\Tools\ninja')

if (-not (Find-SungPython)) {
    throw 'Python 3.9+ is required. Install it from https://www.python.org/downloads/windows/ and enable "Add python.exe to PATH".'
}

if (-not (Get-SungQt) -or -not (Get-SungMingw)) {
    Write-SungWarn 'Qt 6.8+ or MinGW is missing.'
    if (Confirm-SungAction "Download Qt $script:SungQtVersion and MinGW into $Deps now?") {
        Install-SungBuildTools -Deps $Deps
    }
} else {
    Write-SungStep 'Qt and MinGW are already installed'
}

if (-not (Get-SungFfmpeg)) {
    Write-SungWarn 'FFmpeg was not found. Local file metadata and artwork need it.'
    if (Confirm-SungAction 'Download FFmpeg into .deps now?') {
        Install-SungFfmpeg -Deps $Deps | Out-Null
    }
} else {
    Write-SungStep 'FFmpeg is already available'
}

Install-SungRuntime -Root $Root | Out-Null

Write-Host "`nSung setup is complete." -ForegroundColor Green
Write-SungInfo 'Build with: .\scripts\build.ps1'