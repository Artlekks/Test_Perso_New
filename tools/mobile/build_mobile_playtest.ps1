<# Development-only Web rebuild. Does not start or stop the HTTPS server. #>
[CmdletBinding()]
param(
    [string]$GodotPath = (Join-Path $env:USERPROFILE 'Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe')
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exportDirectory = Join-Path $projectRoot 'export'
$outputPath = Join-Path $exportDirectory 'index.html'
$buildLog = Join-Path ([IO.Path]::GetTempPath()) 'FishingGame-mobile-web-build.log'
$presetName = 'Mobile Portrait Web Playtest'

if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw "Godot 4.7.2 was not found at '$GodotPath'. Supply -GodotPath with the installed executable."
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Project not found at '$projectRoot'."
}
New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null

# Wait explicitly: the Windows GUI Godot executable otherwise returns early.
# Quoting preserves spaces in the executable's project, preset and output paths.
$godotArguments = @(
    '--headless', '--path', ('"' + $projectRoot + '"'),
    '--export-debug', ('"' + $presetName + '"'), ('"' + $outputPath + '"'),
    '--log-file', ('"' + $buildLog + '"')
)
Write-Host "Building '$presetName' with Godot 4.7.2..."
$buildProcess = Start-Process -FilePath $GodotPath -ArgumentList $godotArguments -WindowStyle Hidden -Wait -PassThru
if ($buildProcess.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $buildLog) {
        Get-Content -LiteralPath $buildLog -Tail 40 | Out-Host
    }
    throw "Web export failed (exit $($buildProcess.ExitCode)). Log: $buildLog. Do not refresh until a build succeeds."
}
foreach ($filename in @('index.html', 'index.js', 'index.pck', 'index.wasm')) {
    if (-not (Test-Path -LiteralPath (Join-Path $exportDirectory $filename) -PathType Leaf)) {
        throw "Export is missing $filename. Log: $buildLog"
    }
}
Write-Host "Build complete: $outputPath"
Write-Host 'Refresh Safari at the existing HTTPS address. The server was not started or restarted.'
Write-Host "Build log: $buildLog"
