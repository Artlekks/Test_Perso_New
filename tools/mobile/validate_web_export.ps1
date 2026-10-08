<# Read-only validation of a standalone, unencrypted Godot Web export. #>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Directory)

$ErrorActionPreference = 'Stop'
$directoryPath = (Resolve-Path -LiteralPath $Directory).Path
foreach ($filename in @('index.html', 'index.js', 'index.wasm', 'index.pck')) {
    $file = Get-Item -LiteralPath (Join-Path $directoryPath $filename)
    if ($file.Length -eq 0) { throw "Invalid Web export: $filename is empty." }
}
$html = [IO.File]::ReadAllText((Join-Path $directoryPath 'index.html'))
$configMatch = [regex]::Match($html, 'GODOT_CONFIG\s*=\s*(\{[^\r\n]+\})\s*;')
if (-not $configMatch.Success) { throw 'Invalid Web export: GODOT_CONFIG is missing.' }
$config = $configMatch.Groups[1].Value | ConvertFrom-Json
if ($config.executable -ne 'index' -or $html -notmatch 'src=["'']index\.js["'']') {
    throw 'Invalid Web export: HTML executable/script basename is not index.'
}
foreach ($filename in @('index.pck', 'index.wasm')) {
    $actualSize = (Get-Item -LiteralPath (Join-Path $directoryPath $filename)).Length
    if ($config.fileSizes.$filename -ne $actualSize) {
        throw "Invalid Web export: HTML size for $filename does not match the file ($actualSize bytes)."
    }
}

$stream = [IO.File]::OpenRead((Join-Path $directoryPath 'index.pck'))
$reader = [IO.BinaryReader]::new($stream)
try {
    if ($stream.Length -lt 100 -or $reader.ReadUInt32() -ne 0x43504447) { throw 'Invalid PCK magic/header.' }
    $version = $reader.ReadUInt32()
    if ($version -notin @(2, 3, 4)) { throw "Unsupported PCK format $version." }
    $engineVersion = @($reader.ReadUInt32(), $reader.ReadUInt32(), $reader.ReadUInt32()) -join '.'
    $packFlags = $reader.ReadUInt32()
    if (($packFlags -band 1) -or ($packFlags -band 4)) { throw 'Encrypted/sparse PCK is unsupported by this playtest validator.' }
    $fileBase = $reader.ReadUInt64()
    if ($version -ge 3) { $directoryOffset = $reader.ReadUInt64() }
    else { $directoryOffset = 96 }
    if ($directoryOffset -gt $stream.Length - 4) { throw 'PCK directory is outside the file.' }
    $stream.Position = $directoryOffset
    $count = $reader.ReadUInt32()
    if ($count -eq 0 -or $count -gt ($stream.Length / 40)) { throw 'Invalid PCK directory count.' }
    $project = $null
    for ($entry = 0; $entry -lt $count; $entry++) {
        $pathSize = $reader.ReadUInt32()
        if ($pathSize -eq 0 -or $pathSize -gt 65536 -or $pathSize + 36 -gt $stream.Length - $stream.Position) {
            throw 'Truncated/invalid PCK directory entry.'
        }
        $path = [Text.Encoding]::UTF8.GetString($reader.ReadBytes($pathSize)).TrimEnd([char]0)
        $offset = $reader.ReadUInt64()
        $size = $reader.ReadUInt64()
        $md5 = $reader.ReadBytes(16)
        $flags = $reader.ReadUInt32()
        $absoluteOffset = $fileBase + $offset
        if ($absoluteOffset -gt $stream.Length -or $size -gt $stream.Length - $absoluteOffset) {
            throw "PCK entry outside file: $path."
        }
        if ($path -eq 'project.binary' -or $path -eq 'res://project.binary') {
            if ($null -ne $project) { throw 'Duplicate project.binary entries.' }
            $project = @{ Offset = $absoluteOffset; Size = $size; MD5 = $md5; Flags = $flags }
        }
    }
    if ($null -eq $project) { throw 'Invalid Web PCK: project.binary is missing.' }
    if ($project.Size -lt 8 -or $project.Size -gt 16777216 -or $project.Flags -ne 0) {
        throw "Invalid Web PCK: project.binary is $($project.Size) bytes (flags $($project.Flags)). A zero-byte entry matches the reported Godot 4.7.2 Windows Web-export failure; rebuild on Linux. Do not patch the PCK."
    }
    $stream.Position = $project.Offset
    $data = $reader.ReadBytes([int]$project.Size)
    $header = [Text.Encoding]::ASCII.GetString($data, 0, 4)
    if ($header -ne 'ECFG') { throw "Invalid project.binary header: expected ECFG, got $header." }
    $settingsCount = [BitConverter]::ToUInt32($data, 4)
    if ($settingsCount -eq 0 -or $settingsCount -gt ($data.Length / 8)) { throw 'Invalid project.binary settings count.' }
    $hasher = [Security.Cryptography.MD5]::Create()
    try { $digest = $hasher.ComputeHash($data) } finally { $hasher.Dispose() }
    if ([BitConverter]::ToString($digest) -ne [BitConverter]::ToString($project.MD5)) { throw 'project.binary checksum mismatch.' }
    [pscustomobject]@{ PckBytes = $stream.Length; ProjectBinaryBytes = $project.Size; Header = $header; Settings = $settingsCount; Entries = $count; Engine = $engineVersion }
} finally {
    $reader.Dispose()
}
