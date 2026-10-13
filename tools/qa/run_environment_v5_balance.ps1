# Read-only environmental v5 balance matrix. Windows PowerShell 5.1 / PowerShell 7.
# Outputs Godot logs, scenario CSV and review-only design notes under build/.
param(
    [string]$GodotExe = $env:GODOT_EXE,
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like '*Godot*' } | Select-Object -First 1
    if ($null -ne $running) { try { $GodotExe = $running.Path } catch {} }
}
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
    foreach ($name in @('godot', 'godot4')) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) { $GodotExe = $command.Source; break }
    }
}
if ([string]::IsNullOrWhiteSpace($GodotExe) -or -not (Test-Path -LiteralPath $GodotExe -PathType Leaf)) {
    Write-Host 'Godot not found. Pass -GodotExe with the full executable path, or open the Godot editor first.' -ForegroundColor Red
    exit 2
}
$GodotExe = (Resolve-Path -LiteralPath $GodotExe).Path
if ($GodotExe -match '(?i)\.exe$' -and $GodotExe -notmatch '(?i)_console\.exe$') {
    $consoleExe = $GodotExe -replace '(?i)\.exe$', '_console.exe'
    if (Test-Path -LiteralPath $consoleExe -PathType Leaf) { $GodotExe = $consoleExe }
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'project.godot') -PathType Leaf)) {
    Write-Host "Missing project.godot in $ProjectRoot" -ForegroundColor Red
    exit 2
}
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$suite = 'scripts/qa/environment_combined_balance_v5_qa.gd'
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot ($suite -replace '/', '\')) -PathType Leaf)) {
    Write-Host "Missing $suite - extract this ZIP into your project root." -ForegroundColor Red
    exit 2
}
$reportDir = Join-Path $ProjectRoot ('build\environment-v5-balance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$stdout = Join-Path $reportDir 'environment-v5-balance.log'
$stderr = Join-Path $reportDir 'environment-v5-balance.stderr.log'
$quotedProject = '"' + $ProjectRoot + '"'
$arguments = "--headless --path $quotedProject --script res://$suite"
Write-Host "Testing actual project resources: $ProjectRoot"
Write-Host "Godot: $GodotExe"
try {
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments `
        -WorkingDirectory $ProjectRoot -Wait -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($null -eq $process -or $null -eq $process.ExitCode) {
        Write-Host 'Godot did not provide an exit code. Inspect the logs.' -ForegroundColor Red
        exit 2
    }
    $exitCode = [int]$process.ExitCode
} catch {
    Write-Host ('Failed to launch Godot: ' + $_.Exception.Message) -ForegroundColor Red
    exit 2
}
$lines = @(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)
$rows = @()
foreach ($line in $lines) {
    if (-not $line.StartsWith('BALANCE|')) { continue }
    $p = $line.Split('|')
    if ($p.Length -ne 13) { continue }
    $rows += [PSCustomObject]@{
        Scenario = $p[1]; Weather = $p[2]; GameMinute = $p[3]; TidePhase = $p[4]
        WindMps = $p[5]; AuthoredCurrentSpeed = $p[6]; BiteMid = $p[7]
        SpeciesSelectionMin = $p[8]; SpeciesSelectionMax = $p[9]
        LurePresentationMin = $p[10]; LurePresentationMax = $p[11]; AvailableFish = $p[12]
    }
}
$reportCsv = Join-Path $reportDir 'scenario_balance.csv'
if ($rows.Count -gt 0) { $rows | Export-Csv -LiteralPath $reportCsv -NoTypeInformation -Encoding UTF8 }
$notes = @($lines | Where-Object { $_.StartsWith('REVIEW_ONLY|') })
$notesPath = Join-Path $reportDir 'review_notes.txt'
$notes | Set-Content -LiteralPath $notesPath -Encoding UTF8
$summary = @($lines | Where-Object { $_ -match '^BALANCE_SUMMARY\|' -or $_ -match '^Environmental v5 combined balance QA:' })
foreach ($item in $summary) { Write-Host $item }
Write-Host "Scenario report: $reportCsv"
Write-Host "Design review notes: $notesPath"
Write-Host "Full logs: $stdout"
if ($exitCode -ne 0 -or $rows.Count -ne 14 -or $summary.Count -lt 2) {
    Write-Host ("FAIL: Godot exit={0}; scenarios parsed={1}/14; summary lines={2}/2" -f $exitCode, $rows.Count, $summary.Count) -ForegroundColor Red
    foreach ($file in @($stderr, $stdout)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Write-Host ("--- " + $file + " ---") -ForegroundColor Yellow
            Get-Content -LiteralPath $file -Tail 25 | ForEach-Object { Write-Host $_ }
        }
    }
    exit 1
}
Write-Host 'PASS: 14 scenario rows and Godot exit 0.' -ForegroundColor Green
exit 0
