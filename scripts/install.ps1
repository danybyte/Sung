param(
    [switch]$Yes,
    [switch]$SkipBuild,
    [switch]$Launch,
    [string]$Configuration = 'Release',
    [string]$Generator = 'Ninja'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

if ($Yes) { $script:SungAssumeYes = $true }

$Root = Get-SungRoot
$Deps = Get-SungDeps

Write-Host "`nSung installer" -ForegroundColor Green
Write-SungInfo "Repository: $Root"
Write-SungInfo "Downloaded components are kept in $Deps"
if (-not $Yes) {
    Write-SungInfo 'You will be asked before anything is downloaded or installed.'
}

Add-SungToPath @('C:\Program Files\CMake\bin', 'C:\Tools\ninja')

# --- Check every prerequisite and report its state -------------------------
$python = Find-SungPython
$cmake = Get-SungCmake
$ninja = if ($Generator -eq 'Ninja') { Get-SungNinja } else { 'skipped' }
$qt = Get-SungQt
$mingw = Get-SungMingw
$ffmpeg = Get-SungFfmpeg
$node = Get-SungNode

Write-SungStep 'Checking prerequisites'
$report = @(
    [pscustomobject]@{ Name = 'Python 3.9+';    State = $(if ($python) { "found $($python.Version)" } else { 'missing' }) },
    [pscustomobject]@{ Name = 'CMake 3.24+';    State = $(if ($cmake) { 'found' } else { 'missing' }) },
    [pscustomobject]@{ Name = 'Ninja';          State = $(if ($ninja) { 'found' } else { 'missing' }) },
    [pscustomobject]@{ Name = 'Qt 6.8+';        State = $(if ($qt) { "found $($qt.Version) at $($qt.Prefix)" } else { 'missing' }) },
    [pscustomobject]@{ Name = 'MinGW compiler'; State = $(if ($mingw) { "found at $mingw" } else { 'missing' }) },
    [pscustomobject]@{ Name = 'FFmpeg';         State = $(if ($ffmpeg) { "found at $ffmpeg" } else { 'missing' }) },
    [pscustomobject]@{ Name = 'Node.js 20+';    State = $(if ($node) { "found $($node.Version)" } else { 'missing' }) }
)
$report | ForEach-Object {
    $color = if ($_.State -like 'missing' -or $_.State -eq 'skipped') { 'Yellow' } else { 'DarkGray' }
    Write-Host ("    {0,-16} {1}" -f $_.Name, $_.State) -ForegroundColor $color
}

# --- Python is needed first for the helper and for aqtinstall --------------
if (-not $python) {
    Write-SungWarn 'Python 3.9+ is required and was not found.'
    if (Confirm-SungAction 'Install Python with winget now?') {
        if (-not (Invoke-SungWinget -Id 'Python.Python.3.12')) {
            throw 'Could not install Python automatically. Install it from https://www.python.org/downloads/windows/ and enable "Add python.exe to PATH".'
        }
        Add-SungToPath @("$env:LOCALAPPDATA\Programs\Python\Python312", "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts")
        $python = Find-SungPython
        if (-not $python) { throw 'Python was installed but is not visible yet. Close and reopen the terminal, then run the installer again.' }
    } else {
        throw 'Python 3.9+ is required. Install it, then run the installer again.'
    }
}

# --- CMake and Ninja are needed to configure and build ---------------------
if (-not $cmake) {
    Write-SungWarn 'CMake was not found.'
    if (Confirm-SungAction 'Install CMake with winget now?') {
        if (-not (Invoke-SungWinget -Id 'Kitware.CMake')) { throw 'Could not install CMake automatically. See https://cmake.org/download/.' }
        Add-SungToPath @('C:\Program Files\CMake\bin')
        $cmake = Get-SungCmake
    }
    if (-not $cmake) { throw 'CMake is required. Install it, then run the installer again.' }
}
if ($Generator -eq 'Ninja' -and -not $ninja) {
    Write-SungWarn 'Ninja was not found.'
    if (Confirm-SungAction 'Install Ninja with winget now?') {
        if (-not (Invoke-SungWinget -Id 'Ninja-build.Ninja')) { throw 'Could not install Ninja automatically. See https://github.com/ninja-build/ninja/releases.' }
        $ninja = Get-SungNinja
    }
    if (-not $ninja) { throw 'Ninja is required for the default generator. Install it, or pass -Generator "Visual Studio 17 2022".' }
}

# --- Qt and MinGW can be fetched into .deps when absent --------------------
if (-not $qt -or -not $mingw) {
    Write-SungWarn 'Qt 6.8+ or the MinGW toolchain is missing.'
    Write-SungInfo "They can be downloaded into $Deps (about one gigabyte, one time)."
    if (Confirm-SungAction 'Download Qt and MinGW now?') {
        Install-SungBuildTools -Deps $Deps
        $qt = Get-SungQt
        $mingw = Get-SungMingw
    }
    if (-not $qt -or -not $mingw) {
        Write-SungWarn 'Qt and MinGW are still missing.'
        Write-SungInfo 'Install Qt 6.8+ with the MinGW kit and the matching compiler, then run the installer again.'
        throw 'Qt and the MinGW toolchain are required to build Sung.'
    }
} else {
    Write-SungStep 'Qt and MinGW are already installed'
    Write-SungInfo $qt.Prefix
}

# --- FFmpeg reads local metadata and artwork -------------------------------
if (-not $ffmpeg) {
    Write-SungWarn 'FFmpeg was not found. Local file metadata and artwork need it.'
    if (Confirm-SungAction 'Download FFmpeg into .deps now?') {
        Install-SungFfmpeg -Deps $Deps | Out-Null
    } else {
        Write-SungWarn 'Skipping FFmpeg. Local files may not load until it is installed.'
    }
} else {
    Write-SungStep 'FFmpeg is already available'
    Write-SungInfo $ffmpeg
}

# --- Node.js powers some yt-dlp resolver features --------------------------
if (-not $node) {
    Write-SungWarn 'Node.js 20+ was not found. Some YouTube playback may be limited.'
    if (Confirm-SungAction 'Install Node.js with winget now?') {
        Invoke-SungWinget -Id 'OpenJS.NodeJS.LTS' | Out-Null
    }
}

# --- Helper runtime and the build ------------------------------------------
Install-SungRuntime -Root $Root | Out-Null

if (-not $SkipBuild) {
    Invoke-SungBuild -Configuration $Configuration -Generator $Generator -Deploy
}

Write-Host "`nSung is ready." -ForegroundColor Green
Write-SungInfo 'Start it with: .\scripts\run.ps1'
if ($Launch) {
    & (Join-Path $PSScriptRoot 'run.ps1')
}