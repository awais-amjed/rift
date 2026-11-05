# Builds windows/runner/echo_canceller.cpp with its test, outside Flutter, and
# runs it:
#   powershell -File windows\runner\test\echo_canceller.ps1
# Needs Visual Studio's C++ tools, found with vswhere.
$ErrorActionPreference = 'Stop'
$runner = Split-Path $PSScriptRoot -Parent
$out = Join-Path $runner '..\..\build\echo_canceller_test'
New-Item -ItemType Directory -Force $out | Out-Null
$out = (Resolve-Path $out).Path

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'no Visual Studio C++ tools found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

$build = @(
  "call `"$vcvars`" >nul",
  "cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /DNOMINMAX /I`"$runner`" /Fo`"$out\\`" /Fe`"$out\echo_canceller_test.exe`" `"$runner\test\echo_canceller_test.cpp`" `"$runner\echo_canceller.cpp`" ole32.lib wmcodecdspuuid.lib"
) -join ' && '
cmd /c $build
if ($LASTEXITCODE) { throw "build failed ($LASTEXITCODE)" }

& "$out\echo_canceller_test.exe"
if ($LASTEXITCODE) { throw 'echo_canceller_test failed' }
