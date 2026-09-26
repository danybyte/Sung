param(
    [string]$Generator = 'Ninja',
    [string]$Configuration = 'Release',
    [switch]$NoDeploy
)
$ErrorActionPreference = 'Stop'

# CMake/Ninja do not support two writers sharing the same build directory. A
# second build otherwise corrupts build.ninja's recompaction and reports the
# misleading "failed recompaction: Permission denied" error on Windows.
$buildMutex = [Threading.Mutex]::new($false, 'Local\Sung.Build')
$ownsBuildMutex = $false
try {
    try {
        $ownsBuildMutex = $buildMutex.WaitOne(0)
    } catch [Threading.AbandonedMutexException] {
        # The previous build process exited without releasing the mutex. The
        # mutex is acquired by this process after the exception.
        $ownsBuildMutex = $true
    }
    if (-not $ownsBuildMutex) {
        throw 'Another Sung build is already running. Wait for it to finish before starting another build.'
    }

    . (Join-Path $PSScriptRoot 'common.ps1')
    Add-SungToPath @('C:\Program Files\CMake\bin', 'C:\Tools\ninja')
    Invoke-SungBuild -Configuration $Configuration -Generator $Generator -Deploy:(-not $NoDeploy)

    Write-Host "`nSung built successfully." -ForegroundColor Green
    Write-SungInfo 'Start it with: .\scripts\run.ps1'
} finally {
    if ($ownsBuildMutex) {
        $buildMutex.ReleaseMutex()
    }
    $buildMutex.Dispose()
}
