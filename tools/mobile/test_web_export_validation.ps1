<# Synthetic fixtures only; never alters a generated game PCK. #>
$ErrorActionPreference = 'Stop'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('FishingWebPckQA-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$validator = Join-Path $PSScriptRoot 'validate_web_export.ps1'
$passed = 0
function Write-Fixture([string]$Name, [byte[]]$Data, [string]$Entry = 'project.binary', [bool]$BadOffset = $false) {
    $directory = Join-Path $fixtureRoot $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $stream = [IO.File]::Create((Join-Path $directory 'index.pck'))
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        foreach ($number in @(0x43504447, 4, 4, 7, 2, 2)) { $writer.Write([uint32]$number) }
        $writer.Write([uint64]112)
        $writer.Write([uint64](112 + $Data.Length))
        $writer.Write([byte[]]::new(72))
        $writer.Write($Data)
        $writer.Write([uint32]1)
        $pathBytes = [Text.Encoding]::UTF8.GetBytes($Entry)
        $writer.Write([uint32]$pathBytes.Length)
        $writer.Write($pathBytes)
        $writer.Write([uint64]$(if ($BadOffset) { 999999 } else { 0 }))
        $writer.Write([uint64]$Data.Length)
        $md5 = [Security.Cryptography.MD5]::Create()
        try { $writer.Write($md5.ComputeHash($Data)) } finally { $md5.Dispose() }
        $writer.Write([uint32]0)
    } finally { $writer.Dispose() }
    [IO.File]::WriteAllText((Join-Path $directory 'index.js'), 'test')
    [IO.File]::WriteAllText((Join-Path $directory 'index.wasm'), 'test')
    $size = (Get-Item (Join-Path $directory 'index.pck')).Length
    [IO.File]::WriteAllText((Join-Path $directory 'index.html'), ('<script src="index.js"></script><script>const GODOT_CONFIG = {"executable":"index","fileSizes":{"index.pck":' + $size + ',"index.wasm":4}};</script>'))
    return $directory
}
function Expect-Rejection([string]$Directory, [string]$Message) {
    try { $null = & $validator -Directory $Directory }
    catch {
        if ($_.Exception.Message -notlike "*$Message*") { throw }
        $script:passed += 1
        return
    }
    throw "Validator accepted invalid fixture $Directory."
}
# One ECFG setting named 'a', encoded nil value. All fixtures are independent.
$ecfg = [byte[]](69,67,70,71,1,0,0,0,1,0,0,0,97,4,0,0,0,0,0,0,0)
$good = Write-Fixture 'healthy' $ecfg
$result = & $validator -Directory $good
if ($result.Header -ne 'ECFG' -or $result.ProjectBinaryBytes -ne $ecfg.Length) { throw 'Healthy fixture failed.' }
$passed += 1
Expect-Rejection (Write-Fixture 'empty' ([byte[]]::new(0))) 'project.binary is 0 bytes'
Expect-Rejection (Write-Fixture 'bad-header' ([byte[]](66,65,68,33,1,0,0,0,0,0,0,0))) 'expected ECFG'
Expect-Rejection (Write-Fixture 'missing' $ecfg 'another.file') 'project.binary is missing'
Expect-Rejection (Write-Fixture 'out-of-bounds' $ecfg 'project.binary' $true) 'outside file'
[IO.File]::WriteAllText((Join-Path $good 'index.wasm'), 'stale')
Expect-Rejection $good 'HTML size for index.wasm'
Write-Host "WEB EXPORT VALIDATION QA: $passed/6"
Write-Host "Synthetic fixtures: $fixtureRoot"
