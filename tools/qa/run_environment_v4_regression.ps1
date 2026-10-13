# Windows Godot 4.x environmental regression runner.
# This version uses Start-Process -Wait -PassThru (not $LASTEXITCODE)
# because Godot's GUI .exe can leave $LASTEXITCODE unset in PowerShell.
# It prefers the accompanying _console.exe when one is available.
# No gameplay scripts are modified by this runner.
param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch]$SkipImport,
    [switch]$IncludePresentation
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $GodotExe = $command.Source
            break
        }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    Write-Host 'Godot executable not found. Pass -GodotExe "C:\full\path\to\Godot.exe".' -ForegroundColor Red
    exit 2
}

# Resolve a full path or a command name; keep all paths quoted in launch args.
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    $command = Get-Command $GodotExe -ErrorAction SilentlyContinue
    if ($null -ne $command) { $GodotExe = $command.Source }
}
if (-not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    Write-Host "Godot executable not found: $GodotExe" -ForegroundColor Red
    exit 2
}
$GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
if ($GodotExe -match '(?i)\.exe$' -and $GodotExe -notmatch '(?i)_console\.exe$') {
    $consoleExe = $GodotExe -replace '(?i)\.exe$', '_console.exe'
    if (Test-Path -LiteralPath $consoleExe -PathType Leaf) {
        $GodotExe = $consoleExe
        Write-Host "Using Godot console executable: $GodotExe"
    } else {
        Write-Host 'No paired Godot _console.exe found; using GUI executable with process waiting.' -ForegroundColor Yellow
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'project.godot') -PathType Leaf)) {
    Write-Host "project.godot not found in: $ProjectRoot" -ForegroundColor Red
    exit 2
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$reportDir = Join-Path $ProjectRoot ('build\environment-v4-regression-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
Write-Host "Project: $ProjectRoot"
Write-Host "Godot: $GodotExe"
Write-Host "Logs: $reportDir"

function Invoke-GodotProcess {
    param(
        [string]$Arguments,
        [string]$StdoutLog,
        [string]$StderrLog
    )
    try {
        $process = Start-Process -FilePath $GodotExe -ArgumentList $Arguments `
            -WorkingDirectory $ProjectRoot -Wait -PassThru `
            -RedirectStandardOutput $StdoutLog -RedirectStandardError $StderrLog `
            -ErrorAction Stop
        if ($null -eq $process -or $null -eq $process.ExitCode) {
            Write-Host 'Godot finished without an accessible exit code. Check the logs.' -ForegroundColor Red
            return -98
        }
        return [int]$process.ExitCode
    } catch {
        Write-Host ("Failed to launch Godot: " + $_.Exception.Message) -ForegroundColor Red
        return -99
    }
}

function Show-LogTail {
    param([string]$StdoutLog, [string]$StderrLog)
    foreach ($logFile in @($StderrLog, $StdoutLog)) {
        if (Test-Path -LiteralPath $logFile -PathType Leaf) {
            Write-Host "--- Last 25 lines of $logFile ---" -ForegroundColor Yellow
            Get-Content -LiteralPath $logFile -Tail 25 | ForEach-Object { Write-Host $_ }
        }
    }
}

# Quoted absolute path works when the project lives in a folder containing spaces.
$quotedProject = '"' + $ProjectRoot + '"'
if (-not $SkipImport) {
    $importStdout = Join-Path $reportDir '00-initial-import.log'
    $importStderr = Join-Path $reportDir '00-initial-import.stderr.log'
    Write-Host 'Importing project assets (one-time preparation)...'
    $importExit = Invoke-GodotProcess -Arguments ("--headless --editor --path $quotedProject --import") `
        -StdoutLog $importStdout -StderrLog $importStderr
    if ($importExit -ne 0) {
        Write-Host "Import failed (exit $importExit)." -ForegroundColor Red
        Show-LogTail -StdoutLog $importStdout -StderrLog $importStderr
        Write-Host "Full logs: $importStdout and $importStderr" -ForegroundColor Red
        exit 1
    }
    Write-Host 'Import completed (exit 0).' -ForegroundColor Green
} else {
    Write-Host 'Skipping project import as requested.' -ForegroundColor Yellow
}

$suites = @(
    'scripts/qa/game_clock_service_qa.gd',
    'scripts/qa/game_wind_service_qa.gd',
    'scripts/qa/wind_cast_path_qa.gd',
    'scripts/qa/current_tide_clock_integration_qa.gd',
    'scripts/qa/environment_startup_regression_qa.gd',
    'scripts/qa/environment_ecology_integration_qa.gd',
    'scripts/qa/environment_species_profiles_qa.gd',
    'scripts/qa/environment_habitat_presentation_v3_qa.gd'
)
if ($IncludePresentation) {
    $suites += 'scripts/qa/fishing_presentation_current_polish_qa.gd'
}

$results = @()
$index = 0
foreach ($suite in $suites) {
    $index++
    $file = Join-Path $ProjectRoot ($suite -replace '/', '\')
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Write-Host "MISSING SUITE: $suite" -ForegroundColor Red
        $results += [PSCustomObject]@{ Suite = $suite; ExitCode = -1; Log = '' ; StderrLog = '' }
        continue
    }
    $shortName = [System.IO.Path]::GetFileNameWithoutExtension($suite)
    $stdout = Join-Path $reportDir ('{0:D2}-{1}.log' -f $index, $shortName)
    $stderr = Join-Path $reportDir ('{0:D2}-{1}.stderr.log' -f $index, $shortName)
    Write-Host ('[{0}/{1}] {2}' -f $index, $suites.Count, $shortName)
    $argLine = "--headless --path $quotedProject --script res://$suite"
    $exitCode = Invoke-GodotProcess -Arguments $argLine -StdoutLog $stdout -StderrLog $stderr
    $results += [PSCustomObject]@{ Suite = $suite; ExitCode = $exitCode; Log = $stdout; StderrLog = $stderr }
    if ($exitCode -eq 0) {
        Write-Host '  PASS (exit 0)' -ForegroundColor Green
    } else {
        Write-Host "  FAIL (exit $exitCode)." -ForegroundColor Red
        Show-LogTail -StdoutLog $stdout -StderrLog $stderr
    }
}
$summaryPath = Join-Path $reportDir 'summary.csv'
$results | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding UTF8
$failures = @($results | Where-Object { $_.ExitCode -ne 0 })
$passCount = $results.Count - $failures.Count
Write-Host ("Finished: {0} passed, {1} failed. Summary: {2}" -f $passCount, $failures.Count, $summaryPath)
if ($failures.Count -gt 0) { exit 1 }
exit 0
