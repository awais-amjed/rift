# Builds windows/runner/stream_draw.cpp with its test, outside Flutter, and runs
# it on each adapter given (DXGI's order; 0 is the one Flutter takes when Rift
# names no GPU):
#   powershell -File windows\runner\test\run.ps1 0 1
# Needs Visual Studio's C++ tools, found with vswhere. The shaders are compiled
# here with the Windows SDK's fxc, as the app's build has MSBuild do it.
$adapters = if ($args.Count) { $args | ForEach-Object { [int]$_ } } else { @(0) }
$ErrorActionPreference = 'Stop'
$runner = Split-Path $PSScriptRoot -Parent
$out = Join-Path $runner '..\..\build\stream_draw_test'
New-Item -ItemType Directory -Force $out | Out-Null
$out = (Resolve-Path $out).Path

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'no Visual Studio C++ tools found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'

$build = @(
  "set `"PATH=%PATH%;$(Split-Path $vswhere)`"",
  "call `"$vcvars`" >nul",
  "fxc /nologo /T vs_5_0 /E main /Vn kStreamDrawVs /Fh `"$out\stream_draw_vs.h`" `"$runner\stream_draw_vs.hlsl`" >nul",
  "fxc /nologo /T ps_5_0 /E main /Vn kStreamDrawPs /Fh `"$out\stream_draw_ps.h`" `"$runner\stream_draw_ps.hlsl`" >nul",
  "cl /nologo /std:c++17 /EHsc /W4 /WX /O2 /DNOMINMAX /I`"$runner`" /I`"$out`" /Fo`"$out\\`" /Fe`"$out\stream_draw_test.exe`" `"$runner\test\stream_draw_test.cpp`" `"$runner\stream_draw.cpp`" d3d11.lib dxgi.lib"
) -join ' && '
cmd /c $build
if ($LASTEXITCODE) { throw "build failed ($LASTEXITCODE)" }

$failed = 0
foreach ($a in $adapters) {
  & "$out\stream_draw_test.exe" $a
  if ($LASTEXITCODE) { $failed++ }
}
if ($failed) { throw "$failed adapter(s) failed" }
