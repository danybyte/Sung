param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$env:SUNG_HELPER = Join-Path $Root 'helper\catalog.py'
$env:SUNG_PYTHON = Join-Path $Root 'runtime\Scripts\python.exe'
$Exe = Join-Path $Root 'build\sung.exe'
if (-not (Test-Path $Exe)) { $Exe = Join-Path $Root 'build\Release\sung.exe' }
if (-not (Test-Path $Exe)) { throw 'Sung is not built. Run scripts\build.ps1 first.' }
& $Exe @Arguments
exit $LASTEXITCODE
