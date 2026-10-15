[CmdletBinding()]
param(
    [string]$GodotExe = (Join-Path $env:USERPROFILE 'Desktop\_Projects\Fishing Game\Godot_v4.7.2-stable_win64.exe'),
    [string]$ResumeSessionId = '',
    [string]$PythonPath = '',
    [ValidateRange(0,100000)][int]$SmokeFrames = 0,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../qa/QaIsolation.psm1') -Force
$project = Resolve-QAPath (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$configPath = Join-Path $project 'project.godot'
$journalPath = Join-Path $project 'project.godot.qa.original.json'
$lockPath = Join-Path $project 'project.godot.qa.lock'
$sandboxBase = Assert-QAContained (Join-Path $project 'qa_sandboxes') $project
$scene = 'res://actors/desktop/DesktopCompanion.tscn'
$environmentNames = @('APPDATA','LOCALAPPDATA','FISHING_COMPANION_IPC','FISHING_COMPANION_PYTHON')
$savedEnvironment = @{}
foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
}
$lock = $null
$process = $null
$journalWritten = $false
$exitCode = 2

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}
function Set-ProjectBytes([byte[]]$Bytes) {
    $temporary = $configPath + '.qa_swap_' + [guid]::NewGuid().ToString('N')
    $backup = $configPath + '.qa_previous_' + [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, $Bytes)
        [IO.File]::Replace($temporary, $configPath, $backup)
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}
function Restore-Project {
    $record = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
    if (-not (Resolve-QAPath ([string]$record.project)).Equals($configPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Project restoration journal path mismatch' }
    $bytes = [Convert]::FromBase64String([string]$record.original_base64)
    $hash = Get-BytesHash $bytes
    if ($hash -ne [string]$record.sha256) { throw 'Project restoration journal hash mismatch' }
    Set-ProjectBytes $bytes
    if ((Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash -ne $hash) { throw 'Project restoration verification failed' }
    Remove-Item -LiteralPath $journalPath -Force
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $project '.qa_disposable_copy.json') -PathType Leaf)) { throw 'Disposable-copy marker missing' }
    $marker = Get-Content -LiteralPath (Join-Path $project '.qa_disposable_copy.json') -Raw | ConvertFrom-Json
    if ($project.Equals((Resolve-QAPath ([string]$marker.baseline)), [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to run the frozen baseline' }
    Assert-QANoReparse $project
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'project.godot missing' }
    if (-not (Test-Path -LiteralPath (Join-Path $project 'actors/desktop/DesktopCompanion.tscn') -PathType Leaf)) { throw 'Desktop companion scene missing' }
    $godotPath = Resolve-QAPath $GodotExe
    if (-not (Test-Path -LiteralPath $godotPath -PathType Leaf)) { throw "Godot executable missing: $godotPath" }
    if ($PythonPath) {
        $PythonPath = Resolve-QAPath $PythonPath
        if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw "Python executable missing: $PythonPath" }
    }
    if ($ResumeSessionId -and $ResumeSessionId -notmatch '^DesktopAcceptance_[0-9a-f]{32}$') { throw 'Invalid desktop acceptance session ID' }
    $sessionId = if ($ResumeSessionId) { $ResumeSessionId } else { 'DesktopAcceptance_' + [guid]::NewGuid().ToString('N') }
    $sandbox = Assert-QAContained (Join-Path $sandboxBase $sessionId) $project
    $roaming = Assert-QAContained (Join-Path $sandbox 'roaming') $sandbox
    $local = Assert-QAContained (Join-Path $sandbox 'local') $sandbox
    $userDirectory = Assert-QAContained (Join-Path $roaming $sessionId) $sandbox
    $ipc = Assert-QAContained (Join-Path $sandbox 'ipc') $sandbox
    $manifestPath = Join-Path $sandbox 'desktop_session.json'
    if ($ResumeSessionId) {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Desktop acceptance session manifest missing' }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.kind -ne 'desktop_acceptance_v1' -or $manifest.session_id -ne $sessionId -or
            -not ([string]$manifest.project).Equals($project, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([string]$manifest.user_directory).Equals($userDirectory, [StringComparison]::OrdinalIgnoreCase)) { throw 'Desktop acceptance session manifest mismatch' }
    } else {
        if (Test-Path -LiteralPath $sandbox) { throw 'New desktop session already exists' }
    }
    foreach ($dir in @($sandboxBase,$sandbox,$roaming,$local,$userDirectory,$ipc)) { Assert-QAWritable $dir }
    $paths = @('input_bindings.json','game_clock_v1.json','fishing_progress.json','fishing_inventory.json','fishing_catch_pending.json','player_item_inventory.json','beach_gathering_inventory.json','beach_crafted_lures.json')
    foreach ($path in $paths) { [void](Assert-QAPersistencePath ('user://' + $path) $userDirectory) }
    if (-not $ResumeSessionId) {
        $manifest = [ordered]@{kind='desktop_acceptance_v1';session_id=$sessionId;project=$project;scene=$scene;sandbox=$sandbox;APPDATA=$roaming;LOCALAPPDATA=$local;user_directory=$userDirectory;created_utc=[DateTime]::UtcNow.ToString('o')}
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    }
    Write-Output "DESKTOP_PREFLIGHT_PASS session_id=$sessionId user=$userDirectory manifest=$manifestPath"
    $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if (Test-Path -LiteralPath $journalPath) { throw 'Interrupted QA project configuration exists; recover it before launching' }
    if ($ValidateOnly) { $exitCode = 0 }
    else {
        $originalBytes = [IO.File]::ReadAllBytes($configPath)
        $originalHash = Get-BytesHash $originalBytes
        $config = [Text.Encoding]::UTF8.GetString($originalBytes)
        if ($config -notmatch '(?m)^config/name="[^"]*"$') { throw 'Project name setting missing' }
        $config = [regex]::Replace($config, '(?m)^config/name="[^"]*"$', ('config/name="' + $sessionId + '"'))
        $config = [regex]::Replace($config, '(?m)^config/(use_custom_user_dir|custom_user_dir_name)=.*\r?\n', '')
        $config = $config.Replace('[application]', "[application]`r`nconfig/use_custom_user_dir=true`r`nconfig/custom_user_dir_name=`"$sessionId`"")
        $record = @{project=$configPath;sha256=$originalHash;original_base64=[Convert]::ToBase64String($originalBytes);run_id=$sessionId}
        $journalTemp = $journalPath + '.tmp_' + [guid]::NewGuid().ToString('N')
        try {
            [IO.File]::WriteAllText($journalTemp,($record | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
            [IO.File]::Move($journalTemp,$journalPath)
        } finally { if ([IO.File]::Exists($journalTemp)) { [IO.File]::Delete($journalTemp) } }
        $journalWritten = $true
        Set-ProjectBytes ([Text.UTF8Encoding]::new($false).GetBytes($config))
        if ((Get-Content -LiteralPath $configPath -Raw) -notmatch [regex]::Escape('config/custom_user_dir_name="' + $sessionId + '"')) { throw 'Project configuration read-back failed' }
        $env:APPDATA = $roaming
        $env:LOCALAPPDATA = $local
        $env:FISHING_COMPANION_IPC = $ipc
        if ($PythonPath) { $env:FISHING_COMPANION_PYTHON = $PythonPath }
        $launchId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff')
        $stdout = Join-Path $sandbox "godot.$launchId.stdout.log"
        $stderr = Join-Path $sandbox "godot.$launchId.stderr.log"
        $args = @('--path',('"' + $project + '"'),'--scene',$scene)
        if ($SmokeFrames -gt 0) { $args += @('--quit-after',[string]$SmokeFrames) }
        $process = Start-Process -FilePath $godotPath -ArgumentList $args -PassThru -Wait -WindowStyle Normal -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $process.Refresh()
        $godotExit = [int]$process.ExitCode
        Write-Output "DESKTOP_GODOT_EXIT=$godotExit stdout=$stdout stderr=$stderr"
        $diagnostics = (Get-Content -LiteralPath $stdout -Raw) + "`n" + (Get-Content -LiteralPath $stderr -Raw)
        $errors = @([regex]::Matches($diagnostics, '(?m)^(?:SCRIPT )?ERROR:')).Count
        Write-Output "DESKTOP_DIAGNOSTICS errors=$errors"
        if ($godotExit -eq 0 -and $errors -eq 0) { $exitCode = 0 } else { $exitCode = 1 }
    }
} catch {
    [Console]::Error.WriteLine("DESKTOP_LAUNCH_REJECT: $($_.Exception.Message)")
    $exitCode = 2
} finally {
    if ($process -and -not $process.HasExited) { try { $process.WaitForExit() } catch { $exitCode = 2 } }
    if ($journalWritten -and (Test-Path -LiteralPath $journalPath -PathType Leaf)) {
        if ($process -and -not $process.HasExited) { [Console]::Error.WriteLine('DESKTOP_RESTORE_DEFERRED: Godot still running'); $exitCode = 2 }
        else { try { Restore-Project; Write-Output 'DESKTOP_PROJECT_RESTORED: original project.godot bytes restored' } catch { [Console]::Error.WriteLine("DESKTOP_RESTORE_FAILED: $($_.Exception.Message)"); $exitCode = 2 } }
    }
    if ($lock) { $lock.Dispose() }
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],[EnvironmentVariableTarget]::Process) }
}
exit $exitCode
