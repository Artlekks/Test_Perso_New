<# Development-only Web rebuild. Does not start or stop the HTTPS server. #>
[CmdletBinding()]
param(
    [string]$GodotPath = (Join-Path $env:USERPROFILE 'Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe'),
    [ValidateSet('Linux', 'Windows')][string]$Builder = 'Linux',
    [string]$WslDistribution = 'FishingGameMobileBuild'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$exportDirectory = Join-Path $projectRoot 'export'
$stagingDirectory = Join-Path $projectRoot 'build\mobile-web\staging'
$buildLog = Join-Path ([IO.Path]::GetTempPath()) 'FishingGame-mobile-web-build.log'
$presetName = 'Mobile Portrait Web Playtest'

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project.godot') -PathType Leaf)) {
    throw "Project not found at '$projectRoot'."
}
New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
# Only clear staged artifacts; the running server keeps the last served build.
Get-ChildItem -LiteralPath $stagingDirectory -File -Filter 'index.*' | Remove-Item
Write-Host "Building '$presetName' with Godot 4.7.2 ($Builder)..."
if ($Builder -eq 'Linux') {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw 'WSL is required for the Linux Web builder.' }
    function Get-LinuxPath([string]$WindowsPath) {
        $result = & wsl.exe -d $WslDistribution --exec wslpath -u $WindowsPath
        if ($LASTEXITCODE -ne 0) { throw "Could not access WSL distribution '$WslDistribution'. See docs/mobile/web_export_integrity.md for setup." }
        return ($result -join '').Trim()
    }
    $linuxProject = Get-LinuxPath $projectRoot
    $linuxOutput = Get-LinuxPath $stagingDirectory
    $linuxScript = Get-LinuxPath (Join-Path $PSScriptRoot 'build_mobile_playtest_linux.sh')
    $linuxTemplates = Get-LinuxPath (Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable')
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $key = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($projectRoot))).Replace('-', '').Substring(0, 16) }
    finally { $hasher.Dispose() }
    & wsl.exe -d $WslDistribution --exec bash $linuxScript $linuxProject $linuxOutput $linuxTemplates $key
    if ($LASTEXITCODE -ne 0) { throw 'Linux Web export failed; current served build was not replaced.' }
} else {
    if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) { throw "Godot 4.7.2 was not found at '$GodotPath'." }
    $godotArguments = @('--headless', '--path', ('"' + $projectRoot + '"'), '--export-debug',
        ('"' + $presetName + '"'), ('"' + (Join-Path $stagingDirectory 'index.html') + '"'), '--log-file', ('"' + $buildLog + '"'))
    $process = Start-Process -FilePath $GodotPath -ArgumentList $godotArguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Windows Web export failed (exit $($process.ExitCode)). Log: $buildLog." }
}
$validation = & (Join-Path $PSScriptRoot 'validate_web_export.ps1') -Directory $stagingDirectory
Write-Host "Validated PCK: $($validation.PckBytes) bytes; project.binary: $($validation.ProjectBinaryBytes) bytes, $($validation.Header)."
New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null
# Publish HTML last; refresh only when the command completes.
Get-ChildItem -LiteralPath $stagingDirectory -File -Filter 'index.*' |
    Where-Object Name -ne 'index.html' | Copy-Item -Destination $exportDirectory -Force
Copy-Item -LiteralPath (Join-Path $stagingDirectory 'index.html') -Destination $exportDirectory -Force
$null = & (Join-Path $PSScriptRoot 'validate_web_export.ps1') -Directory $exportDirectory
Write-Host "Build complete: $(Join-Path $exportDirectory 'index.html')"
Write-Host 'Refresh Safari at the existing HTTPS address. The server was not started or restarted.'
