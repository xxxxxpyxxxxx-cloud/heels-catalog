param(
  [string]$CsvPath = "",
  [string]$SrcDir = "D:\Japan\Heels",
  [string]$OriginalsDir = "D:\Codex\Image\heels_catalog\originals",
  [string]$OutTagsJsPath = "D:\Codex\Image\heels_catalog\csv_tags_ptt.js",
  [string]$OutImportedJsPath = "D:\Codex\Image\heels_catalog\data_imported_ptt.js",
  [string]$DataJsPath = "D:\Codex\Image\heels_catalog\data.js",
  [string]$ImportedCsvJsPath = "D:\Codex\Image\heels_catalog\data_imported_csv.js"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (!$CsvPath) {
  $candidate = Get-ChildItem -LiteralPath "D:\Codex\Image" -Filter "hh av ptt - *.csv" -File -ErrorAction SilentlyContinue |
    Sort-Object -Property LastWriteTime -Descending |
    Select-Object -First 1
  if ($candidate) { $CsvPath = $candidate.FullName }
}
if (!(Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "CSV not found: $CsvPath" }
if (!(Test-Path -LiteralPath $SrcDir -PathType Container)) { throw "SrcDir not found: $SrcDir" }
if (!(Test-Path -LiteralPath $OriginalsDir -PathType Container)) { New-Item -ItemType Directory -Path $OriginalsDir | Out-Null }
if (!(Test-Path -LiteralPath $DataJsPath -PathType Leaf)) { throw "data.js not found: $DataJsPath" }
if (!(Test-Path -LiteralPath $ImportedCsvJsPath -PathType Leaf)) { Write-Host "WARN: missing $ImportedCsvJsPath (continuing)" }

function Get-CodeFromName([string]$name) {
  if (!$name) { return '' }
  $base = [IO.Path]::GetFileNameWithoutExtension($name)
  return $base.Split('.')[0]
}

function Get-ExistingFilenames([string[]]$paths) {
  $rx = 'filename\s*:\s*["'']([^"'']+)["'']'
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $paths) {
    if (!(Test-Path -LiteralPath $p -PathType Leaf)) { continue }
    $matches = Select-String -LiteralPath $p -Pattern $rx -AllMatches
    foreach ($m in $matches) {
      foreach ($hit in $m.Matches) {
        $fn = $hit.Groups[1].Value
        if ($fn) { [void]$set.Add($fn) }
      }
    }
  }
  return $set
}

function Split-Color([string]$s) {
  if ($null -eq $s) { return @() }
  $v = $s.ToString().Trim()
  if (!$v) { return @() }
  $parts = $v -split "(\r\n|\n|\r)" | Where-Object { $_ -and $_.Trim() }
  $out = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $parts) {
    $t = $p.Trim()
    if (!$t) { continue }
    if ($seen.Add($t)) { $out.Add($t) }
  }
  return ,$out.ToArray()
}

function Get-MaterialSimple([string]$material) {
  if ($null -eq $material) { return '' }
  $m = $material.ToString().Trim()
  if (!$m) { return '' }

  $c_mj = [char]0x9E82
  $c_pi = [char]0x76AE
  $c_rong = [char]0x7D68
  $c_mian = [char]0x9762
  $c_liang = [char]0x4EAE
  $c_fen = [char]0x7C89
  $c_qi = [char]0x6F06
  $c_wu = [char]0x9727
  $c_ren = [char]0x4EBA
  $c_zao = [char]0x9020

  if ($m.Contains($c_mj) -or $m.Contains($c_rong)) { return "$c_mj$c_pi" }         # suede
  if ($m.Contains($c_liang) -or $m.Contains($c_fen)) { return "$c_liang$c_fen" }   # glitter
  if ($m.Contains($c_qi)) { return "$c_qi$c_pi" }                                  # patent
  if ($m.Contains($c_wu)) { return "$c_wu$c_mian$c_pi" }                           # matte leather
  if ($m.Contains($c_pi) -or ($m.Contains($c_ren) -and $m.Contains($c_zao) -and $m.Contains($c_pi))) {
    return "$c_wu$c_mian$c_pi"
  }
  return ''
}

# Use char codepoints so the script stays ASCII-only (Windows PowerShell 5.1 safe).
$c_shao = [char]0x5C11
$c_jian = [char]0x898B
$c_kuan = [char]0x6B3E
$c_shi = [char]0x5F0F
$RARE_LABEL = "$c_shao$c_jian$c_kuan$c_shi"

# CSV columns: code, style, toe, material, heelStyle, color, decoration, rareStyle
$headers = @('code', 'style', 'toe', 'material', 'heelStyle', 'color', 'decoration', 'rareStyle')
$rows = Import-Csv -LiteralPath $CsvPath -Encoding utf8 -Header $headers |
  Select-Object -Skip 1 |
  Where-Object { $_.code -and $_.code.ToString().Trim() }

$codes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$tagsByCode = @{}
foreach ($r in $rows) {
  $code = $r.code.ToString().Trim()
  if (!$code) { continue }
  [void]$codes.Add($code)

  $style = if ($r.style) { $r.style.ToString().Trim() } else { '' }
  $toe = if ($r.toe) { $r.toe.ToString().Trim() } else { '' }
  $heelStyle = if ($r.heelStyle) { $r.heelStyle.ToString().Trim() } else { '' }
  $material = if ($r.material) { $r.material.ToString().Trim() } else { '' }
  $materialSimple = Get-MaterialSimple $material
  $colorParts = Split-Color $r.color
  $decoration = if ($r.decoration) { $r.decoration.ToString().Trim() } else { '' }
  $rareStyle = if ($r.rareStyle) { $r.rareStyle.ToString().Trim() } else { '' }
  $isRare = $false
  if ($rareStyle -match '\*') { $isRare = $true }

  $obj = @{}
  if ($style) { $obj.style = $style }
  if ($toe) { $obj.toe = $toe }
  if ($heelStyle) { $obj.heelStyle = $heelStyle }
  if ($materialSimple) { $obj.materialSimple = $materialSimple }
  if ($colorParts.Count -eq 1) { $obj.color = $colorParts[0] }
  elseif ($colorParts.Count -gt 1) { $obj.color = $colorParts }
  if ($decoration) { $obj.decoration = $decoration }
  if ($isRare) { $obj.rare = $RARE_LABEL }

  if ($obj.Keys.Count -gt 0) {
    $tagsByCode[$code.ToUpperInvariant()] = $obj
  }
}

$payload = @{
  generatedAt = (Get-Date).ToString("s")
  source = $CsvPath
  tagsByCode = $tagsByCode
}

$json = $payload | ConvertTo-Json -Depth 8 -Compress
$js = @"
// Auto-generated. Do not edit by hand.
window.CSV_TAGS_PTT = $json;
"@
Set-Content -LiteralPath $OutTagsJsPath -Value $js -Encoding utf8
Write-Host "Wrote tags: $OutTagsJsPath (codes=$($tagsByCode.Keys.Count))"

# Import images
$origExisting = Get-ChildItem -LiteralPath $OriginalsDir -File | Select-Object -ExpandProperty Name
$origSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($n in $origExisting) { [void]$origSet.Add($n) }

$imgExt = @('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif')
$allImgs = Get-ChildItem -LiteralPath $SrcDir -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $imgExt -contains $_.Extension.ToLowerInvariant() }

$copied = 0
$matched = 0
foreach ($code in $codes) {
  $hits = $allImgs | Where-Object { $_.BaseName -like "$code*" }
  foreach ($f in $hits) {
    $matched++
    if ($origSet.Contains($f.Name)) { continue }
    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $OriginalsDir $f.Name) -Force
    [void]$origSet.Add($f.Name)
    $copied++
  }
}
Write-Host "Images scanned: $($allImgs.Count)"
Write-Host "Images matched: $matched"
Write-Host "Images copied : $copied"

# Generate imported items file (only items not already in data.js/data_imported_csv.js)
$known = Get-ExistingFilenames @($DataJsPath, $ImportedCsvJsPath)
$items = New-Object System.Collections.Generic.List[object]
foreach ($name in $origSet) {
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
$outJs = @"
// Auto-generated. Do not edit by hand.
// Source CSV: $CsvPath
window.SHOE_DATA_IMPORTED_PTT = $(($sorted | ConvertTo-Json -Depth 4 -Compress));
"@
Set-Content -LiteralPath $OutImportedJsPath -Value $outJs -Encoding utf8
Write-Host "Wrote items: $OutImportedJsPath (items=$($sorted.Count))"
