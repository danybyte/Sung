# Shared helpers for the Windows setup, build and run scripts.
# Dot-source this file: . (Join-Path $PSScriptRoot 'common.ps1')

$script:SungQtVersion = '6.8.3'
$script:SungMingwTool = 'tools_mingw1310'
$script:SungMingwPackage = 'qt.tools.win64_mingw1310'
$script:SungFfmpegUrl = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
$script:SungAssumeYes = $false

function Get-SungRoot {
    (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-SungDeps {
    if ($env:SUNG_DEPS) { return $env:SUNG_DEPS }
    Join-Path (Get-SungRoot) '.deps'
}

function Write-SungStep {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-SungInfo {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor DarkGray
}

function Write-SungWarn {
    param([string]$Message)
    Write-Host "    $Message" -ForegroundColor Yellow
}

function Confirm-SungAction {
    param([string]$Question, [switch]$Force)
    if ($script:SungAssumeYes -or $Force) { return $true }
    $answer = Read-Host "$Question [Y/n]"
    return ($answer -eq '' -or $answer -match '^[Yy]')
}

function Find-SungWinget {
    $command = Get-Command winget -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Invoke-SungWinget {
    param([string]$Id)
    $winget = Find-SungWinget
    if (-not $winget) { return $false }
    Write-SungStep "Installing $Id with winget"
    & $winget install --id $Id -e --accept-source-agreements --accept-package-agreements --silent
    return ($LASTEXITCODE -eq 0)
}

function Test-SungStableVersion {
    param([string]$Path)
    try {
        $level = & $Path -c "import sys;print(sys.version_info.releaselevel)" 2>$null
        if ($LASTEXITCODE -ne 0 -or $level -ne 'final') { return $null }
        $version = & $Path -c "import sys;print('%d.%d'%sys.version_info[:2])" 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return [version]$version
    } catch {
        return $null
    }
}

function Find-SungPython {
    $candidates = @()
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        $lines = & $py.Source -0p 2>$null
        foreach ($line in $lines) {
            if ($line -match 'python\.exe') {
                $path = ($line -replace '^\s*-V:[^\s]+\s*\*?\s*', '').Trim()
                if (Test-Path $path) { $candidates += $path }
            }
        }
    }
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) { $candidates += $python.Source }

    $best = $null
    foreach ($candidate in $candidates) {
        $version = Test-SungStableVersion -Path $candidate
        if ($version -and $version -ge [version]'3.9') {
            if (-not $best -or $version -gt $best.Version) {
                $best = [pscustomobject]@{ Version = $version; Path = $candidate }
            }
        }
    }
    if ($best) { return $best }
    return $null
}

function Get-SungQt {
    $roots = @()
    if ($env:SUNG_QT_ROOT) { $roots += $env:SUNG_QT_ROOT }
    $deps = Get-SungDeps
    $roots += (Join-Path $deps 'Qt')
    $roots += $deps
    $roots += 'C:\Qt'
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $versions = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' } |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending
        foreach ($version in $versions) {
            $prefix = Join-Path $version.FullName 'mingw_64'
            if (Test-Path (Join-Path $prefix 'lib\cmake\Qt6\Qt6Config.cmake')) {
                return [pscustomobject]@{ Prefix = $prefix; Version = $version.Name }
            }
        }
    }
    return $null
}

function Get-SungMingw {
    $roots = @()
    if ($env:SUNG_QT_ROOT) { $roots += (Join-Path $env:SUNG_QT_ROOT 'Tools') }
    $deps = Get-SungDeps
    $roots += (Join-Path $deps 'Qt\Tools')
    $roots += (Join-Path $deps 'Tools')
    $roots += 'C:\Qt\Tools'
    foreach ($root in $roots) {
        if (-not $root -or -not (Test-Path $root)) { continue }
        $dirs = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^mingw' } |
            Sort-Object Name -Descending
        foreach ($dir in $dirs) {
            if (Test-Path (Join-Path $dir.FullName 'bin\g++.exe')) { return $dir.FullName }
        }
    }
    return $null
}

function Get-SungFfmpeg {
    if ($env:SUNG_FFMPEG -and (Test-Path (Join-Path $env:SUNG_FFMPEG 'ffprobe.exe'))) {
        return $env:SUNG_FFMPEG
    }
    foreach ($name in @('ffprobe', 'ffmpeg')) {
        $found = Get-Command $name -ErrorAction SilentlyContinue
        if ($found) { return (Split-Path $found.Source -Parent) }
    }
    $deps = Get-SungDeps
    $bases = @((Join-Path $deps 'ffmpeg'), 'C:\ffmpeg', 'C:\tools\ffmpeg',
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'))
    foreach ($base in $bases) {
        if (-not $base -or -not (Test-Path $base)) { continue }
        if (Test-Path (Join-Path $base 'ffprobe.exe')) { return $base }
        $probe = Get-ChildItem $base -Recurse -Filter 'ffprobe.exe' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($probe) { return $probe.DirectoryName }
    }
    return $null
}

function Get-SungNode {
    $found = Get-Command node -ErrorAction SilentlyContinue
    if (-not $found) { return $null }
    try {
        $raw = & $found.Source --version 2>$null
        $version = [version]($raw -replace '^v', '')
        return [pscustomobject]@{ Version = $version; Path = $found.Source }
    } catch {
        return [pscustomobject]@{ Version = [version]'0.0'; Path = $found.Source }
    }
}

function Get-SungCmake {
    $found = Get-Command cmake -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $candidate = 'C:\Program Files\CMake\bin\cmake.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Get-SungNinja {
    $found = Get-Command ninja -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $candidate = 'C:\Tools\ninja\ninja.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Add-SungToPath {
    param([string[]]$Directories)
    foreach ($directory in $Directories) {
        if ($directory -and (Test-Path $directory) -and (($env:PATH -split ';') -notcontains $directory)) {
            $env:PATH = $directory + ';' + $env:PATH
        }
    }
}

function Install-SungBuildTools {
    param([string]$Deps)
    $aqtPython = Join-Path $Deps 'aqt\Scripts\python.exe'
    if (-not (Test-Path $aqtPython)) {
        Write-SungStep 'Setting up the Qt downloader (aqtinstall)'
        $system = Find-SungPython
        if (-not $system) { throw 'Python 3.9+ is required before Qt can be downloaded.' }
        & $system.Path -m venv (Join-Path $Deps 'aqt')
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the tooling environment.' }
        & $aqtPython -m pip install --disable-pip-version-check --quiet --upgrade pip aqtinstall
        if ($LASTEXITCODE -ne 0) { throw 'Could not install aqtinstall. Check the network connection and try again.' }
    }
    $qtOut = Join-Path $Deps 'Qt'
    Write-SungStep "Downloading Qt $script:SungQtVersion (Qt Quick, Multimedia, Svg, ImageFormats)"
    Write-SungInfo 'This is a one-time download of roughly one gigabyte.'
    & $aqtPython -m aqt install-qt windows desktop $script:SungQtVersion win64_mingw -O $qtOut -m qtmultimedia qtimageformats
    if ($LASTEXITCODE -ne 0) { throw 'Could not download Qt. Check the network connection and try again.' }
    Write-SungStep 'Downloading the matching MinGW toolchain'
    & $aqtPython -m aqt install-tool windows desktop $script:SungMingwTool $script:SungMingwPackage -O $qtOut
    if ($LASTEXITCODE -ne 0) { throw 'Could not download the MinGW toolchain. Check the network connection and try again.' }
}

function Install-SungFfmpeg {
    param([string]$Deps)
    $existing = Get-SungFfmpeg
    if ($existing) { return $existing }
    $target = Join-Path $Deps 'ffmpeg'
    if (Test-Path $target) { Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $zip = Join-Path $Deps 'ffmpeg.zip'
    Write-SungStep 'Downloading FFmpeg for local file metadata'
    Write-SungInfo $script:SungFfmpegUrl
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $script:SungFfmpegUrl -OutFile $zip -UseBasicParsing
    if (-not (Test-Path $zip)) { throw 'Could not download FFmpeg. Check the network connection and try again.' }
    Write-SungStep 'Extracting FFmpeg'
    Expand-Archive -Path $zip -DestinationPath $target -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    $probe = Get-ChildItem $target -Recurse -Filter 'ffprobe.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $probe) { throw 'The FFmpeg archive did not contain ffprobe.exe.' }
    return $probe.DirectoryName
}

function Install-SungRuntime {
    param([string]$Root)
    $runtime = Join-Path $Root 'runtime'
    $runtimePython = Join-Path $runtime 'Scripts\python.exe'
    if (-not (Test-Path $runtimePython)) {
        Write-SungStep 'Creating the isolated Python helper environment'
        $system = Find-SungPython
        if (-not $system) { throw 'Python 3.9+ is required for the helper runtime.' }
        & $system.Path -m venv $runtime
        if ($LASTEXITCODE -ne 0) { throw 'Could not create the Python virtual environment.' }
        & $runtimePython -m pip install --disable-pip-version-check --quiet --upgrade pip
    }
    Write-SungStep 'Installing the helper dependencies'
    $requirements = Join-Path $Root 'helper\requirements-windows.txt'
    & $runtimePython -m pip install --disable-pip-version-check --quiet -r $requirements
    if ($LASTEXITCODE -ne 0) { throw 'Could not install the Sung helper dependencies. Check the network connection and try again.' }
    return $runtime
}

function Invoke-SungDeploy {
    param([string]$QtPrefix, [string]$Build)
    $exe = Join-Path $Build 'sung.exe'
    if (-not (Test-Path $exe)) { $exe = Join-Path $Build 'Release\sung.exe' }
    if (-not (Test-Path $exe)) { return }
    $windeploy = Join-Path $QtPrefix 'bin\windeployqt.exe'
    if (-not (Test-Path $windeploy)) { return }
    Write-SungStep 'Copying the Qt libraries next to sung.exe'
    # windeployqt writes progress and non-fatal warnings to stderr. Native
    # command stderr becomes an error record under ErrorActionPreference=Stop,
    # so relax it for the duration of the call.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $windeploy --release --no-translations --no-system-d3d-compiler --no-opengl-sw $exe 2>&1 |
            Where-Object { $_ -notmatch 'Warning:' } | Out-Null
    } finally {
        $ErrorActionPreference = $previous
    }
    $core = Join-Path $Build 'Qt6Core.dll'
    if (-not (Test-Path $core)) {
        Write-SungWarn 'windeployqt did not copy the Qt libraries. Run scripts\build.ps1 again or start with scripts\run.ps1.'
    }
}

function Invoke-SungBuild {
    param(
        [string]$Configuration = 'Release',
        [string]$Generator = 'Ninja',
        [switch]$Deploy
    )
    $root = Get-SungRoot
    $build = Join-Path $root 'build'
    $qt = Get-SungQt
    if (-not $qt) { throw 'Qt 6.8+ was not found. Run scripts\setup.ps1 first.' }
    $cmake = Get-SungCmake
    if (-not $cmake) { throw 'CMake was not found. Install CMake 3.24+ and reopen the terminal.' }
    $configureArgs = @('-S', $root, '-B', $build,
        ('-DCMAKE_BUILD_TYPE=' + $Configuration),
        ('-DCMAKE_PREFIX_PATH=' + $qt.Prefix),
        '-DBUILD_TESTING=OFF', '-DSUNG_DIAGNOSTICS=OFF')
    if ($Generator) { $configureArgs += @('-G', $Generator) }
    if ($Generator -eq 'Ninja') {
        if (-not (Get-SungNinja)) {
            throw 'Ninja was not found. Install Ninja or run with -Generator "Visual Studio 17 2022".'
        }
        $mingw = Get-SungMingw
        if (-not $mingw) { throw 'MinGW was not found. Run scripts\setup.ps1 first.' }
        Add-SungToPath @((Join-Path $mingw 'bin'))
        $configureArgs += @('-DCMAKE_CXX_COMPILER=' + (Join-Path $mingw 'bin\g++.exe'))
    }
    Write-SungStep "Configuring Sung with Qt $($qt.Version)"
    & $cmake @configureArgs
    if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed.' }
    Write-SungStep 'Building Sung'
    & $cmake --build $build --config $Configuration --parallel
    if ($LASTEXITCODE -ne 0) { throw 'The build failed.' }
    if ($Deploy) { Invoke-SungDeploy -QtPrefix $qt.Prefix -Build $build }
}