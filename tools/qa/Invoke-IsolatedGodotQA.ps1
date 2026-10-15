param(
    [Parameter(Mandatory=$true)][string]$GodotExe,
    [string]$Project = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [string]$Runner = 'res://scripts/qa/fishing_save_recovery_runner.gd',
    [string]$SandboxRoot,
    [string[]]$PersistencePaths = @(),
    [switch]$Import,
    [switch]$ValidateOnly,
    [switch]$Recover
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'QaIsolation.psm1') -Force
$exitCode = 2
$lock = $null
$journalPath = $null
$configPath = $null
$journalWritten = $false
$process = $null
$environmentNames = @('APPDATA', 'LOCALAPPDATA', 'FISHING_QA_RUN_ID', 'FISHING_QA_SANDBOX', 'FISHING_QA_USER_DIR', 'FISHING_QA_PERSISTENCE_PATHS')
$originalEnvironment = @{}
$processEnvironment = [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::Process)
foreach ($name in $environmentNames) {
    $originalEnvironment[$name] = @{
        present = $processEnvironment.Contains($name)
        value = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
    }
}

function Set-QAProjectBytes([string]$Path, [byte[]]$Bytes) {
    $temporary = $Path + '.qa_swap_' + [guid]::NewGuid().ToString('N')
    $backup = $Path + '.qa_previous_' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Replace($temporary, $Path, $backup)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}

function Get-QABytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

function Restore-QAProject([string]$Path, [string]$JournalPath) {
    $record = Get-Content -LiteralPath $JournalPath -Raw | ConvertFrom-Json
    if ((Resolve-QAPath ([string]$record.project)) -ne (Resolve-QAPath $Path)) { throw 'Recovery journal project mismatch' }
    $bytes = [Convert]::FromBase64String([string]$record.original_base64)
    $hash = Get-QABytesHash $bytes
    if ($hash -ne [string]$record.sha256) { throw 'Recovery journal hash mismatch' }
    Set-QAProjectBytes $Path $bytes
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $hash) { throw 'Project restoration verification failed' }
    Remove-Item -LiteralPath $JournalPath -Force
}

try {
    $projectPath = Resolve-QAPath $Project
    $markerPath = Join-Path $projectPath '.qa_disposable_copy.json'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'Disposable-copy marker is missing' }
    $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
    if ($projectPath.Equals((Resolve-QAPath ([string]$marker.baseline)), [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to launch baseline project' }
    Assert-QANoReparse $projectPath
    $configPath = Join-Path $projectPath 'project.godot'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'project.godot missing' }
    $godotPath = Resolve-QAPath $GodotExe
    if (-not (Test-Path -LiteralPath $godotPath -PathType Leaf)) { throw "Godot executable missing: $godotPath" }
    if (-not $Runner.StartsWith('res://scripts/qa/', [StringComparison]::Ordinal) -or $Runner -match '\.\.' -or -not $Runner.EndsWith('.gd')) { throw 'Runner must be a scripts/qa GDScript' }
    $suiteId = [IO.Path]::GetFileNameWithoutExtension($Runner)
    $runnerFile = Join-Path $projectPath ($Runner.Substring(6).Replace('/', [IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $runnerFile -PathType Leaf)) { throw "Runner missing: $runnerFile" }

    $journalPath = Join-Path $projectPath 'project.godot.qa.original.json'
    $lockPath = Join-Path $projectPath 'project.godot.qa.lock'
    if ($Recover -and $ValidateOnly) { throw 'Recover and ValidateOnly cannot be combined' }
    if ($Recover) {
        $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        if (-not (Test-Path -LiteralPath $journalPath -PathType Leaf)) { throw 'No interrupted QA configuration to recover' }
        $active = @(Get-Process -Name 'Godot*' -ErrorAction SilentlyContinue)
        if ($active.Count -gt 0) { throw 'A Godot process is still running; recovery refused' }
        Restore-QAProject $configPath $journalPath
        Write-Output 'QA_PROJECT_RECOVERED: original project.godot bytes restored'
        $exitCode = 0
    } else {
        if (-not $SandboxRoot) { $SandboxRoot = Join-Path $projectPath 'qa_sandboxes' }
        $sandboxBase = Assert-QAContained $SandboxRoot $projectPath
        $runId = 'FishingQA_' + [guid]::NewGuid().ToString('N')
        $sandbox = Assert-QAContained (Join-Path $sandboxBase $runId) $projectPath
        $roaming = Assert-QAContained (Join-Path $sandbox 'roaming') $sandbox
        $local = Assert-QAContained (Join-Path $sandbox 'local') $sandbox
        $userDirectory = Assert-QAContained (Join-Path $roaming $runId) $sandbox
        foreach ($dir in @($sandboxBase,$sandbox,$roaming,$local,$userDirectory)) { Assert-QAWritable $dir }
        $paths = @('user://input_bindings.json','user://game_clock_v1.json','user://fishing_progress.json','user://fishing_inventory.json','user://fishing_catch_pending.json','user://player_item_inventory.json') + $PersistencePaths
        $resolvedPaths = @()
        foreach ($path in $paths) { $resolvedPaths += Assert-QAPersistencePath $path $userDirectory }
        if ($PersistencePaths -match '\|') { throw 'Invalid persistence path separator' }
        $manifestPath = Join-Path $sandbox 'isolation_manifest.json'
        $manifest = [ordered]@{ run_id=$runId; project=$projectPath; runner=$Runner; sandbox=$sandbox; APPDATA=$roaming; LOCALAPPDATA=$local; user_directory=$userDirectory; persistence_paths=$resolvedPaths; godot_started=$false }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
        Write-Output "QA_PREFLIGHT_PASS run_id=$runId user=$userDirectory manifest=$manifestPath"

        if ($ValidateOnly) {
            if (Test-Path -LiteralPath $journalPath) { throw 'Interrupted QA configuration exists; run -Recover' }
            $exitCode = 0
        } else {
            $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            if (Test-Path -LiteralPath $journalPath) { throw 'Interrupted QA configuration exists; run -Recover' }
            $originalBytes = [IO.File]::ReadAllBytes($configPath)
            $originalHash = Get-QABytesHash $originalBytes
            $config = [Text.Encoding]::UTF8.GetString($originalBytes)
            if ($config -notmatch '(?m)^config/name="[^"]*"$') { throw 'Project name setting missing' }
            $config = [regex]::Replace($config, '(?m)^config/name="[^"]*"$', ('config/name="' + $runId + '"'))
            $config = [regex]::Replace($config, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
            $config = $config.Replace('[application]', "[application]`r`nconfig/use_custom_user_dir=true`r`nconfig/custom_user_dir_name=`"$runId`"")
            if ($config -notmatch [regex]::Escape('config/custom_user_dir_name="' + $runId + '"')) { throw 'Custom user directory configuration failed' }

            $record = @{ project=$configPath; sha256=$originalHash; original_base64=[Convert]::ToBase64String($originalBytes); run_id=$runId }
            $journalTemp = $journalPath + '.tmp_' + [guid]::NewGuid().ToString('N')
            try {
                [IO.File]::WriteAllText($journalTemp, ($record | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
                [IO.File]::Move($journalTemp, $journalPath)
            } finally { if ([IO.File]::Exists($journalTemp)) { [IO.File]::Delete($journalTemp) } }
            $journalWritten = $true
            Set-QAProjectBytes $configPath ([Text.UTF8Encoding]::new($false).GetBytes($config))
            $savedConfig = Get-Content -LiteralPath $configPath -Raw
            if ($savedConfig -notmatch [regex]::Escape('config/name="' + $runId + '"') -or $savedConfig -notmatch 'config/use_custom_user_dir=true' -or $savedConfig -notmatch [regex]::Escape('config/custom_user_dir_name="' + $runId + '"')) { throw 'Project configuration read-back failed' }

            $env:APPDATA = $roaming
            $env:LOCALAPPDATA = $local
            $env:FISHING_QA_RUN_ID = $runId
            $env:FISHING_QA_SANDBOX = $sandbox
            $env:FISHING_QA_USER_DIR = $userDirectory
            $env:FISHING_QA_PERSISTENCE_PATHS = ($PersistencePaths -join '|')
            if ($env:APPDATA -ne $roaming -or $env:LOCALAPPDATA -ne $local -or $env:FISHING_QA_USER_DIR -ne $userDirectory) { throw 'Process environment read-back failed' }
            $stdout = Join-Path $sandbox 'godot.stdout.log'
            $stderr = Join-Path $sandbox 'godot.stderr.log'
            $manifest.godot_started = $true
            $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
            $arguments = if ($Import) { @('--headless','--editor','--path',('"' + $projectPath + '"'),'--import') } else { @('--headless','--path',('"' + $projectPath + '"'),'--script',$Runner) }
            $process = Start-Process -FilePath $godotPath -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            $process.Refresh()
            $godotExitCode = $null
            if ($process.HasExited) {
                try { $godotExitCode = [int]$process.ExitCode } catch { $godotExitCode = $null }
            }
            $exitText = if ($null -eq $godotExitCode) { 'UNKNOWN' } else { [string]$godotExitCode }
            Write-Output "QA_GODOT_EXIT=$exitText stdout=$stdout stderr=$stderr"
            $output = [string](Get-Content -LiteralPath $stdout -Raw)
            $diagnostics = [string](Get-Content -LiteralPath $stderr -Raw)
            $expectedWarnings = @([regex]::Matches($diagnostics, '(?m)^WARNING: (PlayerItemInventory: could not open save for writing\.|FishingInventory: could not open save file for writing\.|FishingProgress: Could not open save file for writing\.)')).Count
            $allWarnings = @([regex]::Matches($diagnostics, '(?m)^WARNING:')).Count
            $unexpectedErrors = @([regex]::Matches($diagnostics, '(?m)^ERROR: (?!Failed to read the root certificate store\.)')).Count
            Write-Output "QA_DIAGNOSTICS warnings=$allWarnings expected_negative_control=$expectedWarnings unexpected_errors=$unexpectedErrors"
            if ($null -eq $godotExitCode -or $godotExitCode -ne 0 -or $unexpectedErrors -gt 0 -or $diagnostics -match '(?m)^SCRIPT ERROR:' -or (-not $Import -and ($output -notmatch 'QA_ISOLATION_PASS' -or $output -notmatch 'QA_ROOT_CLOCK_PATH' -or $output -match 'QA_ISOLATION_REJECT'))) {
                $exitCode = 1
            } elseif ($Import) {
                $exitCode = 0
            } else {
                $matches = @([regex]::Matches($output, '(?m)^QA_SUITE_RESULT (\{[^\r\n]+\})\s*$'))
                $finalizers = @([regex]::Matches($output, '(?m)^QA_PROCESS_FINALIZED\s*$'))
                if ($finalizers.Count -ne 1 -or $matches.Count -ne 1 -or ($matches.Count -eq 1 -and $finalizers.Count -eq 1 -and $finalizers[0].Index -le $matches[0].Index)) {
                    $exitCode = 1
                    Write-Output "QA_RESULT_REJECT result_count=$($matches.Count) clean_shutdown_count=$($finalizers.Count)"
                }
                else {
                    $result = $matches[0].Groups[1].Value | ConvertFrom-Json
                    $required = @('suite', 'passed', 'total', 'failed', 'orphans')
                    $missing = @($required | Where-Object { $result.PSObject.Properties.Name -cnotcontains $_ })
                    $numbers = @('passed', 'total', 'failed', 'orphans')
                    $invalidTypes = @($numbers | Where-Object { $value = $result.$_; -not ($value -is [int] -or $value -is [long]) })
                    if ($missing.Count -gt 0 -or $result.suite -isnot [string] -or [string]::IsNullOrWhiteSpace($result.suite) -or $invalidTypes.Count -gt 0) {
                        $exitCode = 1; Write-Output "QA_RESULT_REJECT missing=$($missing -join ',') invalid_types=$($invalidTypes -join ',')"
                    } else {
                        $total = [long]$result.total; $passed = [long]$result.passed; $failed = [long]$result.failed; $orphans = [long]$result.orphans
                        if ($result.suite -ne $suiteId -or $total -le 0 -or $passed -lt 0 -or $failed -lt 0 -or $orphans -lt 0 -or $passed + $failed -ne $total -or $passed -ne $total -or $failed -ne 0 -or $orphans -ne 0) {
                            $exitCode = 1; Write-Output "QA_RESULT_REJECT suite=$($result.suite) passed=$passed total=$total failed=$failed orphans=$orphans"
                        } else { $exitCode = 0; Write-Output "QA_RESULT_PASS suite=$suiteId passed=$passed total=$total failed=0 orphans=0" }
                    }
                }
            }
        }
    }
} catch {
    [Console]::Error.WriteLine("QA_LAUNCH_REJECT: $($_.Exception.Message)")
    $exitCode = 2
} finally {
    if ($process -and -not $process.HasExited) {
        try { $process.WaitForExit() }
        catch { [Console]::Error.WriteLine("QA_GODOT_WAIT_FAILED: $($_.Exception.Message)"); $exitCode = 2 }
    }
    if ($journalWritten -and $journalPath -and (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
        if ($process -and -not $process.HasExited) {
            [Console]::Error.WriteLine('QA_RESTORE_DEFERRED: Godot is still running; do not start another run; use -Recover after it exits')
            $exitCode = 2
        } else {
            try {
                Restore-QAProject $configPath $journalPath
                Write-Output 'QA_PROJECT_RESTORED: original project.godot bytes restored'
            } catch {
                [Console]::Error.WriteLine("QA_RESTORE_FAILED: $($_.Exception.Message); do not start Godot; run -Recover")
                $exitCode = 2
            }
        }
    }
    if ($lock) { $lock.Dispose() }
    if (-not $process -or $process.HasExited) {
        foreach ($name in $environmentNames) {
            $snapshot = $originalEnvironment[$name]
            if ($snapshot.present) {
                [Environment]::SetEnvironmentVariable($name, [string]$snapshot.value, [EnvironmentVariableTarget]::Process)
            } else {
                Remove-Item -LiteralPath ("Env:" + $name) -ErrorAction SilentlyContinue
            }
        }
    }
}
exit $exitCode
