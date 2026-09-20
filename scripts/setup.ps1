$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PythonLauncher = Get-Command py -ErrorAction SilentlyContinue
$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $PythonLauncher -and -not $Python) { throw 'Python 3 is required. Install it from https://www.python.org/downloads/windows/ and enable the PATH option.' }
$VenvArgs = @('-m', 'venv', (Join-Path $Root 'runtime'))
if ($PythonLauncher) { & $PythonLauncher.Source -3 @VenvArgs }
else { & $Python.Source @VenvArgs }
if ($LASTEXITCODE -ne 0) { throw 'Could not create the Python virtual environment.' }
$RuntimePython = Join-Path $Root 'runtime\Scripts\python.exe'
$Requirements = Join-Path $Root 'helper\requirements-windows.txt'
& $RuntimePython -m pip install --disable-pip-version-check -r $Requirements
if ($LASTEXITCODE -ne 0) { throw 'Could not install the Sung helper dependencies. Check the network connection and try again.' }
Write-Host "Sung helper runtime is ready in $Root\runtime"
