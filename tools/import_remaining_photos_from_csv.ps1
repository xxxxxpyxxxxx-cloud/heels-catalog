param(
  [string]$CsvPath = "",
  [string]$PicDir = "D:\Japan\Heels\pic",
  [string]$OriginalsDir = "D:\Codex\Image\heels_catalog\originals",
  [string]$DataJsPath = "D:\Codex\Image\heels_catalog\data.js",
  [string]$OutImportedJsPath = "D:\Codex\Image\heels_catalog\data_imported_csv.js"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (!$CsvPath) {
  $candidate = Get-ChildItem -LiteralPath "D:\Codex\Image" -Filter "hh av - *.csv" -File -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1
  if ($candidate) { $CsvPath = $candidate.FullName }
}
if (!(Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "CSV not found: $CsvPath" }
if (!(Test-Path -LiteralPath $PicDir -PathType Container)) { throw "PicDir not found: $PicDir" }
if (!(Test-Path -LiteralPath $OriginalsDir -PathType Container)) { New-Item -ItemType Directory -Path $OriginalsDir | Out-Null }
if (!(Test-Path -LiteralPath $DataJsPath -PathType Leaf)) { throw "data.js not found: $DataJsPath" }

# Read CSV with ASCII headers for Windows PowerShell 5.1 compatibility.
$headers = @(
  'code', 'shoe1', 'shoe2', 'shoe3',
  'style', 'toe', 'material', 'heelStyle',
  'color', 'decoration', 'rareStyle', 'note'
)
$rows = Import-Csv -LiteralPath $CsvPath -Encoding utf8 -Header $headers |
  Where-Object { $_.code -and $_.code.Trim() -ne '2' }

$codes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($r in $rows) {
  $c = $r.code.ToString().Trim()
  if ($c) { [void]$codes.Add($c) }
}

function Get-CodeFromName([string]$name) {
  if (!$name) { return '' }
  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  return $base.Split('.')[0]
}

function Get-ExistingFilenamesFromDataJs([string]$path) {
  $rx = 'filename\s*:\s*["'']([^"'']+)["'']'
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  $matches = Select-String -LiteralPath $path -Pattern $rx -AllMatches
  foreach ($m in $matches) {
    foreach ($hit in $m.Matches) {
      $fn = $hit.Groups[1].Value
      if ($fn) { [void]$set.Add($fn) }
    }
  }
  return $set
}

$known = Get-ExistingFilenamesFromDataJs $DataJsPath
$origExisting = Get-ChildItem -LiteralPath $OriginalsDir -File | Select-Object -ExpandProperty Name
$origSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($n in $origExisting) { [void]$origSet.Add($n) }

# Copy remaining photos (only those with matching CSV codes)
$picFiles = Get-ChildItem -LiteralPath $PicDir -File
$toCopy = @()
foreach ($f in $picFiles) {
  $code = Get-CodeFromName $f.Name
  if (!$code) { continue }
  if (!$codes.Contains($code)) { continue }
  if ($origSet.Contains($f.Name)) { continue }
  $toCopy += $f
}

Write-Host "CSV codes: $($codes.Count)"
Write-Host "Pic files: $($picFiles.Count)"
Write-Host "To copy :  $($toCopy.Count)"

$copied = 0
foreach ($f in $toCopy) {
  Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $OriginalsDir $f.Name) -Force
  $copied++
  if ($copied % 100 -eq 0) { Write-Host "Copied $copied / $($toCopy.Count)..." }
}
Write-Host "Copied total: $copied"

# Generate imported items file for those now in originals but missing from data.js
$allOrig = Get-ChildItem -LiteralPath $OriginalsDir -File | Select-Object -ExpandProperty Name
$items = New-Object System.Collections.Generic.List[object]
foreach ($name in $allOrig) {
  if ($known.Contains($name)) { continue }
  $code = Get-CodeFromName $name
  if (!$codes.Contains($code)) { continue }
  $id = [IO.Path]::GetFileNameWithoutExtension($name)
  $items.Add([ordered]@{
    id = $id
    filename = $name
    image = "originals/$name"
  })
}

$sorted = $items | Sort-Object -Property filename
$js = @"
// Auto-generated. Do not edit by hand.
// Source CSV: $CsvPath
window.SHOE_DATA_IMPORTED = $(($sorted | ConvertTo-Json -Depth 4 -Compress));
"@

Set-Content -LiteralPath $OutImportedJsPath -Value $js -Encoding utf8
Write-Host "Wrote: $OutImportedJsPath (items=$($sorted.Count))"
