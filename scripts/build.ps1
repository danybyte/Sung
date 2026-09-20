param(
    [string]$Generator = 'Ninja',
    [string]$Configuration = 'Release',
    [switch]$NoDeploy
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

Add-SungToPath @('C:\Program Files\CMake\bin', 'C:\Tools\ninja')
Invoke-SungBuild -Configuration $Configuration -Generator $Generator -Deploy:(-not $NoDeploy)

Write-Host "`nSung built successfully." -ForegroundColor Green
Write-SungInfo 'Start it with: .\scripts\run.ps1'