param([string]$Generator = 'Ninja', [string]$Configuration = 'Release')
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Build = Join-Path $Root 'build'
if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'CMake was not found on PATH. Install CMake 3.24+ and reopen the terminal, or add its bin folder to PATH.'
}
if ($Generator -eq 'Ninja' -and -not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    throw 'Ninja was not found on PATH. Install Ninja or run this script with -Generator "Visual Studio 17 2022".'
}
$CMakeArgs = @('-S', $Root, '-B', $Build, ('-DCMAKE_BUILD_TYPE=' + $Configuration), '-DBUILD_TESTING=OFF', '-DSUNG_DIAGNOSTICS=OFF')
if ($Generator) { $CMakeArgs += @('-G', $Generator) }
cmake @CMakeArgs
cmake --build $Build --config $Configuration --parallel
