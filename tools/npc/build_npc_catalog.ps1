<# Development-only source-sheet ingestion. Does not export or serve Web. #>
[CmdletBinding()]
param([string]$PythonPath = (Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PythonPath)) { throw 'Set -PythonPath to a Python installation with Pillow for new-sheet validation.' }
Push-Location (Join-Path $PSScriptRoot '..\..')
try {
    & $PythonPath (Join-Path $PSScriptRoot 'scan_source_batch.py')
    if ($LASTEXITCODE -ne 0) { throw 'Source guide scan failed; previous reviewed manifests were preserved.' }
    & $PythonPath (Join-Path $PSScriptRoot 'build_npc_catalog.py')
    if ($LASTEXITCODE -ne 0) { throw 'NPC ingestion failed. Review the source manifest; do not guess frame boundaries.' }
    & $PythonPath (Join-Path $PSScriptRoot 'inventory_npc_assets.py')
    if ($LASTEXITCODE -ne 0) { throw 'NPC source inventory failed.' }
} finally { Pop-Location }
