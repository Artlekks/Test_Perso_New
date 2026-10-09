<# Canonical portrait companion window. Fullscreen keeps the same composition. #>
[CmdletBinding()]
param(
    [string]$GodotPath = (Join-Path $env:USERPROFILE 'Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe'),
    [switch]$Fullscreen,
    [switch]$Companion,
    [string]$PythonPath = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot missing: $GodotPath" }
$gameArgs = @('--path', ('"' + $projectRoot + '"'), '--resolution', '640x864')
if ($Fullscreen) { $gameArgs += '--fullscreen' }
if ($Companion) {
    if ($Fullscreen) { throw 'Use Fullscreen for ordinary portrait play, or Companion for window modes.' }
    $gameArgs += 'res://actors/desktop/DesktopCompanion.tscn'
    if ($PythonPath) {
        if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw "Python missing: $PythonPath" }
        $env:FISHING_COMPANION_PYTHON = [IO.Path]::GetFullPath($PythonPath)
    }
}
Start-Process -FilePath $GodotPath -ArgumentList $gameArgs -WindowStyle Normal
