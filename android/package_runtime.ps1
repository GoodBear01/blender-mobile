# Copy Blender scripts, datafiles, and the Android CPython stdlib into APK assets.
param(
    [string]$VersionDir = "5.2"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Blender = Join-Path $Root "blender-5.2.0"
$Assets = Join-Path $PSScriptRoot "app\src\main\assets\blender\$VersionDir"
$LibPython = Join-Path $Blender "lib\android_arm64\python"

New-Item -ItemType Directory -Force -Path $Assets | Out-Null

function Copy-RuntimeTree([string]$From, [string]$To) {
    if (-not (Test-Path $From)) {
        Write-Warning "Missing $From"
        return
    }
    if (Test-Path $To) { Remove-Item -Recurse -Force $To }
    New-Item -ItemType Directory -Force -Path (Split-Path $To) | Out-Null
    Write-Host "Copy $From -> $To"
    Copy-Item -Recurse -Force $From $To
}

Copy-RuntimeTree (Join-Path $Blender "scripts") (Join-Path $Assets "scripts")

$cyclesAddonSrc = Join-Path $Blender "intern\cycles\blender\addon"
$cyclesAddonDst = Join-Path $Assets "scripts\addons_core\cycles"
if (Test-Path $cyclesAddonSrc) {
    New-Item -ItemType Directory -Force -Path $cyclesAddonDst | Out-Null
    Copy-Item -Force (Join-Path $cyclesAddonSrc "*") $cyclesAddonDst
    Write-Host "Copied Cycles addon -> $cyclesAddonDst"
}
$cyclesInstall = Join-Path $Root "build_android\bin\5.2\scripts\addons_core\cycles"
if (Test-Path $cyclesInstall) {
    Copy-Item -Recurse -Force (Join-Path $cyclesInstall "*") $cyclesAddonDst
    Write-Host "Merged Cycles install files -> $cyclesAddonDst"
}

$datafiles = Join-Path $Blender "release\datafiles"
Copy-RuntimeTree $datafiles (Join-Path $Assets "datafiles")

if (Test-Path $LibPython) {
    Copy-RuntimeTree $LibPython (Join-Path $Assets "python")
} else {
    Write-Warning "CPython Android prefix not found at $LibPython (run build_deps.ps1)"
}

# Locale / fonts that live next to scripts in a portable install.
$locale = Join-Path $Blender "locale"
if (Test-Path $locale) {
    Copy-RuntimeTree $locale (Join-Path $Assets "datafiles\locale")
}

Write-Host "Runtime assets staged under $Assets"
