param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,

  [string]$OutPath = "D:\Codex\Image\heels_catalog\csv_tags.js"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (!(Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
  throw "CSV not found: $CsvPath"
}

# ASCII headers (Windows PowerShell 5.1 script encoding safe)
$headers = @(
  'code', 'shoe1', 'shoe2', 'shoe3',
  'style', 'toe', 'material', 'heelStyle',
  'color', 'decoration', 'rareStyle', 'note'
)

function Split-Color([string]$s) {
  # Keep CSV color rules: do NOT split by "/" or "," (readability only),
  # only split by line breaks.
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

  # Use char codepoints so the script stays ASCII-only.
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

  # Rough mapping to simplified categories:
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

$rows = Import-Csv -LiteralPath $CsvPath -Encoding utf8 -Header $headers |
  Where-Object { $_.code -and $_.code.Trim() -ne '2' }

$tagsByCode = @{}
foreach ($r in $rows) {
  $code = $r.code.ToString().Trim().ToUpperInvariant()
  if (!$code) { continue }

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

  if ($obj.Keys.Count -eq 0) { continue }
  $tagsByCode[$code] = $obj
}

$payload = @{
  generatedAt = (Get-Date).ToString("s")
  source = $CsvPath
  tagsByCode = $tagsByCode
}

$json = $payload | ConvertTo-Json -Depth 8 -Compress
$js = @"
// Auto-generated. Do not edit by hand.
window.CSV_TAGS = $json;
"@

Set-Content -LiteralPath $OutPath -Value $js -Encoding utf8
Write-Host "Wrote: $OutPath (codes=$($tagsByCode.Keys.Count))"
