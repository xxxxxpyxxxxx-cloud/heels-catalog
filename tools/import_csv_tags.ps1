param(
  [string]$CsvPath = "D:\Codex\Image\hh av - 有碼.csv",
  [string]$OutPath = "D:\Codex\Image\heels_catalog\csv_tags.js"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Normalize-Style([string]$s) {
  $v = ''
  if ($null -ne $s) { $v = $s.ToString() }
  $v = $v.Trim()
  if (!$v) { return '' }
  if ($v -match '包鞋') { return '包鞋' }
  if ($v -match '涼鞋|涼拖|拖鞋') { return '涼鞋' }
  if ($v -match '長靴|靴') { return '長靴' }
  return $v
}

function Normalize-Toe([string]$s) {
  $v = ''
  if ($null -ne $s) { $v = $s.ToString() }
  $v = $v.Trim()
  if (!$v) { return '' }
  if ($v -match '尖') { return '尖頭' }
  if ($v -match '圓') { return '圓頭' }
  if ($v -match '露趾') { return '露趾' }
  if ($v -match '魚口') { return '魚口' }
  return $v
}

function Normalize-MaterialSimple([string]$s) {
  $v = ''
  if ($null -ne $s) { $v = $s.ToString() }
  $v = $v.Trim()
  if (!$v) { return '' }
  if ($v -match '麂|麂皮') { return '麂皮' }
  if ($v -match '漆') { return '漆皮' }
  if ($v -match '亮粉|亮片|閃|glitter') { return '亮粉' }
  if ($v -match '霧') { return '霧面皮' }
  return ''
}

function Split-Multi([string]$s) {
  $v = ''
  if ($null -ne $s) { $v = $s.ToString() }
  $v = $v.Trim()
  if (!$v) { return @() }

  # Cells may contain newline-separated values.
  $parts = $v -split "(\r\n|\n|\r|/|／|,|，|、|;|；)" | Where-Object { $_ -and $_.Trim() }
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

$rows = Import-Csv -LiteralPath $CsvPath -Encoding utf8

# Column names in this CSV:
# 2, 鞋一, 鞋二, 鞋三, 分類, 鞋頭, 材質, 鞋跟, 顏色, 裝飾, 少見款式, 補充
$map = @{}

foreach ($r in $rows) {
  $code = ''
  if ($r.PSObject.Properties.Name -contains '2') { $code = ($r.'2' | ForEach-Object { $_.ToString().Trim() }) }
  if (!$code) { continue }

  $style = Normalize-Style ($r.'分類')
  $toe = Normalize-Toe ($r.'鞋頭')
  $heelStyle = ''
  if ($null -ne $r.'鞋跟') { $heelStyle = $r.'鞋跟'.ToString() }
  $heelStyle = $heelStyle.Trim()
  $materialSimple = Normalize-MaterialSimple ($r.'材質')
  $colorParts = Split-Multi ($r.'顏色')
  $decParts = Split-Multi ($r.'裝飾')

  $obj = @{}
  if ($style) { $obj.style = $style }
  if ($toe) { $obj.toe = $toe }
  if ($heelStyle) { $obj.heelStyle = $heelStyle }
  if ($materialSimple) { $obj.materialSimple = $materialSimple }
  if ($colorParts.Count -eq 1) { $obj.color = $colorParts[0] }
  elseif ($colorParts.Count -gt 1) { $obj.color = $colorParts }
  if ($decParts.Count -eq 1) { $obj.decoration = @($decParts[0]) }
  elseif ($decParts.Count -gt 1) { $obj.decoration = $decParts }

  if ($obj.Keys.Count -eq 0) { continue }
  $map[$code.ToUpperInvariant()] = $obj
}

$payload = @{
  generatedAt = (Get-Date).ToString("s")
  source = $CsvPath
  tagsByCode = $map
}

$json = $payload | ConvertTo-Json -Depth 8 -Compress
$js = @"
// Auto-generated. Do not edit by hand.
// Source: $CsvPath
window.CSV_TAGS = $json;
"@

Set-Content -LiteralPath $OutPath -Value $js -Encoding utf8
Write-Host "Wrote: $OutPath (codes=$($map.Keys.Count))"
