Set-StrictMode -Version Latest

function Resolve-QAPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid QA path: $Path" }
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
}

function Assert-QAContained([string]$Path, [string]$Root) {
    $p = Resolve-QAPath $Path
    $r = Resolve-QAPath $Root
    if (-not $p.StartsWith($r + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "QA path outside disposable root: $p"
    }
    return $p
}

function Assert-QANoReparse([string]$Path) {
    $p = Resolve-QAPath $Path
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            $item = Get-Item -LiteralPath $p -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point in QA path: $p" }
        }
        $parent = [IO.Path]::GetDirectoryName($p)
        if (-not $parent -or $parent -eq $p) { break }
        $p = $parent
    }
}

function Assert-QAWritable([string]$Directory) {
    Assert-QANoReparse $Directory
    New-Item -ItemType Directory -Path $Directory -Force -ErrorAction Stop | Out-Null
    Assert-QANoReparse $Directory
    $probe = Join-Path $Directory ('.qa_write_' + [guid]::NewGuid().ToString('N'))
    $bytes = [byte[]](11, 22, 33, 44)
    try {
        [IO.File]::WriteAllBytes($probe, $bytes)
        $read = [IO.File]::ReadAllBytes($probe)
        if ($read.Length -ne 4 -or $read[0] -ne 11 -or $read[3] -ne 44) { throw "QA write verification failed: $Directory" }
    } finally {
        if (Test-Path -LiteralPath $probe) { Remove-Item -LiteralPath $probe -Force }
    }
}

function Assert-QAPersistencePath([string]$Path, [string]$UserDirectory) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid persistence path: $Path" }
    if ($Path.StartsWith('user://', [StringComparison]::OrdinalIgnoreCase)) {
        $suffix = $Path.Substring(7).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $resolved = Join-Path $UserDirectory $suffix
    } else {
        $resolved = $Path
    }
    $resolved = Assert-QAContained $resolved $UserDirectory
    Assert-QANoReparse $resolved
    return $resolved
}

Export-ModuleMember -Function Resolve-QAPath,Assert-QAContained,Assert-QANoReparse,Assert-QAWritable,Assert-QAPersistencePath
