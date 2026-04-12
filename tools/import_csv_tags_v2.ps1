param(
  [Parameter(Mandatory = $true)]
  [string]$CsvPath,

  [string]$OutPath = "D:\Codex\Image\heels_catalog\csv_tags.js"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Split-Multi([string]$s) {
  if ($null -eq $s) { return @() }
  $v = $s.ToString().Trim()
  if (!$v) { return @() }
  # Keep this script ASCII-only (Windows PowerShell 5.1 reads UTF-8 scripts poorly without BOM).
  $fullWidthSlash = [char]0xFF0F  # ／
  $fullWidthComma = [char]0xFF0C  # ，
  $ideographicComma = [char]0x3001 # 、
  $fullWidthSemicolon = [char]0xFF1B # ；

  $pattern = "(\r\n|\n|\r|/|,|;|{0}|{1}|{2}|{3})" -f `
    [Regex]::Escape($fullWidthSlash), `
    [Regex]::Escape($fullWidthComma), `
    [Regex]::Escape($ideographicComma), `
    [Regex]::Escape($fullWidthSemicolon)

  $parts = $v -split $pattern | Where-Object { $_ -and $_.Trim() }
  $out = New-Object System.Collections.Generic.List[string]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($p in $parts) {
    $t = $p.Trim()
    if (!$t) { continue }
    if ($seen.Add($t)) { $out.Add($t) }
  }
  return ,$out.ToArray()
}

function Split-Color([string]$s) {
  # Keep CSV "color" rules: do NOT split by "/" or "," (those are readability),
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

if (!(Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
  throw "CSV not found: $CsvPath"
}

# Use ASCII headers so this script works in Windows PowerShell 5.1 without UTF-8 BOM.
$headers = @(
  'code', 'shoe1', 'shoe2', 'shoe3',
  'style', 'toe', 'material', 'heelStyle',
  'color', 'decoration', 'rareStyle', 'note'
)

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
  $materialSimple = ''
  if ($material) {
    if ($material -match '麂|麂皮|絨|绒') { $materialSimple = '麂皮' }
    elseif ($material -match '亮粉|亮片|閃|闪|金屬|金属|glitter') { $materialSimple = '亮粉' }
    elseif ($material -match '漆|鏡|镜|亮面|镜面') { $materialSimple = '漆皮' }
    elseif ($material -match '霧|雾|皮|皮革|人造皮') { $materialSimple = '霧面皮' }
  }

  $colorParts = Split-Color $r.color
  $decoration = if ($r.decoration) { $r.decoration.ToString().Trim() } else { '' }

  $obj = @{}
  if ($style) { $obj.style = $style }
  if ($toe) { $obj.toe = $toe }
  if ($heelStyle) { $obj.heelStyle = $heelStyle }
  if ($materialSimple) { $obj.materialSimple = $materialSimple }
  if ($colorParts.Count -eq 1) { $obj.color = $colorParts[0] }
  elseif ($colorParts.Count -gt 1) { $obj.color = $colorParts }
  if ($decoration) { $obj.decoration = $decoration }

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
