<#
.SYNOPSIS
    Build Desktop Gremlin and launch it, without opening Visual Studio.

.DESCRIPTION
    This is a .NET Framework project with a legacy (non-SDK) csproj, so
    'dotnet build' cannot build it regardless of which .NET SDK is installed -
    it needs the MSBuild that ships with Visual Studio. This script locates
    that MSBuild through vswhere, so it works from an ordinary PowerShell
    prompt rather than a Developer Command Prompt.

.EXAMPLE
    .\Tools\run.ps1
    Build Debug and launch.

.EXAMPLE
    .\Tools\run.ps1 -Configuration Release -NoRun
    Build Release and stop.
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Debug',

    # Build without launching.
    [switch]$NoRun,

    # Force a full rebuild instead of an incremental one.
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $root 'Desktop_Gremlin.sln'
$exe = Join-Path $root "Desktop_Gremlin\bin\$Configuration\DesktopGremlin.exe"

if (-not (Test-Path $solution)) {
    throw "Solution not found at $solution"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found at $vswhere - Visual Studio 2017 or newer is required."
}

$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
    -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1

if (-not $msbuild) {
    throw "MSBuild not found. Install the '.NET desktop development' workload."
}

# A running instance keeps a lock on the exe, which makes the build fail with a
# file-in-use error rather than anything that explains itself.
Get-Process -Name 'DesktopGremlin' -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Stopping running instance (PID $($_.Id))" -ForegroundColor DarkGray
    $_.Kill()
    $null = $_.WaitForExit(5000)
}

$targets = if ($Clean) { 'Clean;Build' } else { 'Build' }

Write-Host "Building $Configuration..." -ForegroundColor Cyan
& $msbuild $solution /t:$targets /p:Configuration=$Configuration /v:minimal /nologo

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path $exe)) {
    throw "Build succeeded but $exe is missing."
}

if ($NoRun) {
    Write-Host "Built $exe" -ForegroundColor Green
    return
}

# The tray icon is loaded through a path relative to the working directory
# rather than the assembly location, so launch from the output folder.
Write-Host "Launching $exe" -ForegroundColor Green
Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe)
