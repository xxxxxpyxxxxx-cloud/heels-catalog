param(
  [string]$CatalogDir = "D:\Codex\Image\heels_catalog",
  [string]$OutCsvPath = "D:\Codex\Image\heels_catalog\export_notion.csv"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function U([string]$u) {
  # Example: U '\u5305\u978b'
  return [regex]::Unescape($u)
}

# Canonical values (generated at runtime so this script stays ASCII-only; PS 5.1 safe)
$S_PUMP      = U '\u5305\u978b'
$S_SLIPPER   = U '\u62d6\u978b'
$S_SANDAL    = U '\u6dbc\u978b'
$S_LONGBOOT  = U '\u9577\u9774'
$S_SHORTBOOT = U '\u77ed\u9774'
$S_ANKLEBOOT = U '\u8e1d\u9774'

$T_POINT  = U '\u5c16\u982d'
$T_OPEN   = U '\u9732\u8dbe'
$T_PEEP   = U '\u9b5a\u982d'
$T_ROUND  = U '\u5713\u982d'
$T_SQUARE = U '\u65b9\u982d'

$H_FLAT     = U '\u5e73\u5e95'
$H_WEDGE    = U '\u5761\u8ddf'
$H_PLATFORM = U '\u539a\u5e95'
$H_STILETTO = U '\u7d30\u8ddf'
$H_BLOCK    = U '\u7c97\u8ddf'

$M_SUEDE   = U '\u9e82\u76ae'
$M_MATTE   = U '\u9727\u9762\u76ae'
$M_PATENT  = U '\u6f06\u76ae'
$M_GLITTER = U '\u4eae\u7c89'

$C_BLACK  = U '\u9ed1'
$C_WHITE  = U '\u767d'
$C_GOLD   = U '\u91d1'
$C_PINK   = U '\u6843\u7d05'
$C_RED    = U '\u7d05'
$C_CLEAR  = U '\u900f\u660e'
$C_SILVER = U '\u9280'
$C_NUDE   = U '\u819a'
$C_BEIGE  = U '\u7c73'
$C_GRAY   = U '\u7070'
$C_BROWN  = U '\u68d5'
$C_OTHER  = U '\u5176\u4ed6'

$D_PLATFORM = U '\u9632\u6c34\u53f0'
$D_TSTRAP   = U 'T\u5b57\u5e36'
$D_ISTRAP   = U '\u4e00\u5b57\u5e36'
$D_MJ       = U '\u746a\u8389\u73cd'
$D_GOLDTRIM = U '\u91d1\u908a'
$D_BOW      = U '\u8774\u8776\u7d50'
$D_REDSOLE  = U '\u7d05\u5e95'
$D_ANKLE    = U '\u8e1d\u5e36'
$D_BUCKLE   = U '\u91d1\u6263'
$D_CUTOUT   = U '\u5074\u7a7a'
$D_CHAIN    = U '\u934a\u5b50'

$RARE_LABEL = U '\u5c11\u898b\u6b3e\u5f0f'

function Read-TextUtf8([string]$path) {
  return [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path))
}

function Extract-BracketedArrayText {
  param([string]$Text, [int]$StartIndex)
  $i = $Text.IndexOf('[', $StartIndex)
  if ($i -lt 0) { return $null }

  $depth = 0
  $inStr = $false
  $quote = ''
  for ($p = $i; $p -lt $Text.Length; $p++) {
    $ch = $Text[$p]
    if ($inStr) {
      if ($ch -eq '\') { $p++; continue }
      if ($ch -eq $quote) { $inStr = $false }
      continue
    }
    if ($ch -eq '"' -or $ch -eq "'") { $inStr = $true; $quote = $ch; continue }
    if ($ch -eq '[') { $depth++; continue }
    if ($ch -eq ']') { $depth--; if ($depth -eq 0) { return $Text.Substring($i, ($p - $i + 1)) } }
  }
  return $null
}

function Extract-ObjectsFromArrayText([string]$arrayText) {
  if (-not $arrayText) { return @() }
  $objs = New-Object System.Collections.Generic.List[string]
  $depth = 0
  $inStr = $false
  $quote = ''
  $buf = New-Object System.Text.StringBuilder

  for ($i = 0; $i -lt $arrayText.Length; $i++) {
    $ch = $arrayText[$i]
    if ($inStr) {
      [void]$buf.Append($ch)
      if ($ch -eq '\') { if ($i + 1 -lt $arrayText.Length) { $i++; [void]$buf.Append($arrayText[$i]) }; continue }
      if ($ch -eq $quote) { $inStr = $false }
      continue
    }
    if ($ch -eq '"' -or $ch -eq "'") { $inStr = $true; $quote = $ch; if ($depth -gt 0) { [void]$buf.Append($ch) }; continue }
    if ($ch -eq '{') { $depth++; [void]$buf.Append($ch); continue }
    if ($depth -gt 0) { [void]$buf.Append($ch) }
    if ($ch -eq '}') {
      $depth--
      if ($depth -eq 0) { $objs.Add($buf.ToString()) | Out-Null; $buf.Clear() | Out-Null }
    }
  }
  return $objs.ToArray()
}

function Unescape-String([string]$s) {
  if ($null -eq $s) { return $null }
  return ($s -replace '\\\\"', '"' -replace '\\\\n', "`n" -replace '\\\\r', "`r" -replace '\\\\t', "`t" -replace "\\\\'", "'")
}

function Get-PropString([string]$objText, [string]$key) {
  $k = [regex]::Escape($key)
  $m = [regex]::Match($objText, "(?m)^\s*$k\s*:\s*`"([^`"]*)`"\s*,?\s*$")
  if ($m.Success) { return (Unescape-String $m.Groups[1].Value) }
  $m2 = [regex]::Match($objText, "(?m)^\s*$k\s*:\s*'([^']*)'\s*,?\s*$")
  if ($m2.Success) { return (Unescape-String $m2.Groups[1].Value) }
  return $null
}

function Extract-QuotedStrings([string]$text) {
  if (-not $text) { return @() }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($text, '"([^"\\\\]*(?:\\\\.[^"\\\\]*)*)"')) { $out.Add((Unescape-String $m.Groups[1].Value)) | Out-Null }
  foreach ($m in [regex]::Matches($text, "'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'")) { $out.Add((Unescape-String $m.Groups[1].Value)) | Out-Null }
  return $out.ToArray()
}

function Get-PropArray([string]$objText, [string]$key) {
  $k = [regex]::Escape($key)
  $m = [regex]::Match($objText, "(?ms)^\s*$k\s*:\s*\[([\s\S]*?)\]\s*,?\s*$")
  if ($m.Success) { return (Extract-QuotedStrings $m.Groups[1].Value) }
  $s = Get-PropString $objText $key
  if ($s) { return @($s) }
  return @()
}

function To-Array([object]$v) {
  if ($null -eq $v) { return @() }
  if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [string])) {
    $out = @()
    foreach ($x in $v) {
      $t = ''
      if ($null -ne $x) { $t = $x.ToString().Trim() }
      if ($t) { $out += $t }
    }
    return $out
  }
  $t2 = $v.ToString().Trim()
  if ($t2) { return @($t2) }
  return @()
}

function Code-FromFilename([string]$filename) {
  if (-not $filename) { return '' }
  $base = [IO.Path]::GetFileNameWithoutExtension($filename)
  return ($base.Split('.')[0]).ToUpperInvariant()
}

function Normalize-Style([string]$style, [string]$toe) {
  $s = ''
  $t = ''
  if ($null -ne $style) { $s = $style.Trim() }
  if ($null -ne $toe) { $t = $toe.Trim() }

  if ($s -match '\u904e\u819d|\u819d|\u9577\u7b52|\u9577\u9774') { return $S_LONGBOOT }
  if ($s -match '\u8e1d\u9774|\u8e1d') { return $S_ANKLEBOOT }
  if ($s -match '\u77ed\u9774|\u77ed\u7b52') { return $S_SHORTBOOT }
  if ($s -match '\u9774') { return $S_SHORTBOOT }

  if ($s -match '\u62d6\u978b|\u62d6') { return $S_SLIPPER }
  if ($s -match '\u6dbc\u978b|\u6dbc\u62d6|\u6dbc') { return $S_SANDAL }
  if ($t -eq $T_OPEN -or $t -eq $T_PEEP) { return $S_SANDAL }

  return $S_PUMP
}

function Normalize-Toe([string]$toe, [string]$style) {
  $t = ''
  $s = ''
  if ($null -ne $toe) { $t = $toe.Trim() }
  if ($null -ne $style) { $s = $style.Trim() }

  if ($t -match '\u5c16') { return $T_POINT }
  if ($t -match '\u65b9') { return $T_SQUARE }
  if ($t -match '\u5713|\u5706') { return $T_ROUND }
  if ($t -match '\u9732\u8dbe|\u9732\u6307|open\s*toe') { return $T_OPEN }
  if ($t -match '\u9b5a\u53e3|\u9c7c\u53e3|\u9b5a\u5634|\u9c7c\u5634|peep|\u9b5a\u982d') { return $T_PEEP }
  if (-not $t -and ($s -eq $S_SANDAL -or $s -eq $S_SLIPPER)) { return $T_OPEN }
  return ''
}

function Normalize-HeelStyles([object]$v) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($token in (To-Array $v)) {
    $s = ''
    if ($null -ne $token) { $s = $token.ToString().Trim() }
    if (-not $s) { continue }
    if ($s -match '\u5e73\u5e95|\u5e73\u8ddf|flat') { [void]$set.Add($H_FLAT) }
    if ($s -match '\u5761\u8ddf|\u6974\u8ddf|\u6974\u5f62|wedge') { [void]$set.Add($H_WEDGE) }
    if ($s -match '\u539a\u5e95|\u677e\u7cd5|\u539a\u53f0|platform') { [void]$set.Add($H_PLATFORM) }
    if ($s -match '\u9632\u6c34\u53f0') { [void]$set.Add($H_PLATFORM) }
    if ($s -match '\u7d30\u8ddf|\u7ec6\u8ddf|stiletto') { [void]$set.Add($H_STILETTO) }
    if ($s -match '\u7c97\u8ddf|block\s*heel|block|\u7c97') { [void]$set.Add($H_BLOCK) }
    if ($s -match '\u9ad8\u8ddf|high\s*heel') { if ($s -match '\u7c97') { [void]$set.Add($H_BLOCK) } else { [void]$set.Add($H_STILETTO) } }
  }
  $order = @($H_FLAT,$H_WEDGE,$H_PLATFORM,$H_STILETTO,$H_BLOCK)
  return $order | Where-Object { $set.Contains($_) }
}

function Normalize-Material([string]$m) {
  $s = ''
  if ($null -ne $m) { $s = $m.ToString().ToLowerInvariant() }
  if (-not $s) { return '' }
  if ($s -match '\u9e82\u76ae|\u7d68\u9762') { return $M_SUEDE }
  if ($s -match '\u4eae\u7c89|\u9583|\u91d1\u5c6c|glitter') { return $M_GLITTER }
  if ($s -match '\u6f06\u76ae|\u4eae\u9762|\u93e1\u9762|patent') { return $M_PATENT }
  if ($s -match '\u9727\u9762|\u76ae\u9769|\u4eba\u9020\u76ae|\u76ae') { return $M_MATTE }
  return ''
}

function Normalize-Colors([object]$v) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($token in (To-Array $v)) {
    $s = ''
    if ($null -ne $token) { $s = $token.ToString().Trim() }
    if (-not $s) { continue }
    if ($s -match '\u900f\u660e|clear') { [void]$set.Add($C_CLEAR) }
    if ($s -match '\u9ed1') { [void]$set.Add($C_BLACK) }
    if ($s -match '\u767d') { [void]$set.Add($C_WHITE) }
    if ($s -match '\u9280|\u94f6|silv') { [void]$set.Add($C_SILVER) }
    if ($s -match '\u91d1|gold') { [void]$set.Add($C_GOLD) }
    if ($s -match '\u6843\u7d05|\u6843\u7ea2|\u73ab\u7d05|\u73ab\u7ea2|fuchsia|magenta|hot\s*pink') { [void]$set.Add($C_PINK) }
    elseif ($s -match '\u7d05|\u7ea2|red') { [void]$set.Add($C_RED) }
    if ($s -match '\u819a|\u80a4|nude|skin') { [void]$set.Add($C_NUDE) }
    if ($s -match '\u7c73|\u5976|\u8c61\u7259|ivory|beige') { [void]$set.Add($C_BEIGE) }
    if ($s -match '\u7070|gray') { [void]$set.Add($C_GRAY) }
    if ($s -match '\u68d5|\u5496|\u5561|\u5561\u5561|brown') { [void]$set.Add($C_BROWN) }
  }
  if ($set.Count -eq 0) { [void]$set.Add($C_OTHER) }
  $order = @($C_BLACK,$C_WHITE,$C_RED,$C_PINK,$C_GOLD,$C_SILVER,$C_CLEAR,$C_NUDE,$C_BEIGE,$C_GRAY,$C_BROWN,$C_OTHER)
  return $order | Where-Object { $set.Contains($_) }
}

function Normalize-Decorations([object]$v) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($token in (To-Array $v)) {
    $s = ''
    if ($null -ne $token) { $s = $token.ToString().Trim() }
    if (-not $s) { continue }
    if ($s -match '\u9632\u6c34\u53f0|\u539a\u5e95|\u53f0(?!\u7063)') { [void]$set.Add($D_PLATFORM) }
    if ($s -match 'T\u5b57\u5e36|\u4e01\u5b57\u5e36|T\s*\u5b57|\u4e01\s*\u5b57') { [void]$set.Add($D_TSTRAP) }
    if ($s -match '\u4e00\u5b57\u5e36|\u4e00\u5b57(\u5e36)?') { [void]$set.Add($D_ISTRAP) }
    if ($s -match '\u746a\u8389\u73cd|\u746a\u9e97\u73cd|\u739b\u4e3d\u73cd|mary\s*jane') { [void]$set.Add($D_MJ) }
    if ($s -match '\u91d1\u908a|\u91d1\u8272\u908a|\u91d1\u908a\u98fe|\u91d1\u6846') { [void]$set.Add($D_GOLDTRIM) }
    if ($s -match '\u8774\u8776\u7d50|\u8774\u7d50|\u8774\u8776') { [void]$set.Add($D_BOW) }
    if ($s -match '\u7d05\u5e95|\u7ea2\u5e95|red\s*sole|louboutin') { [void]$set.Add($D_REDSOLE) }
    if ($s -match '\u8e1d\u5e36|\u8173\u8e1d\u5e36|\u8e1d\u7e6b|ankle\s*strap|ankle-strap') { [void]$set.Add($D_ANKLE) }
    if ($s -match '\u91d1\u6263|\u91d1\u6263\u74b0|\u91d1\u91e6') { [void]$set.Add($D_BUCKLE) }
    if ($s -match '\u5074\u7a7a|\u4fa7\u7a7a|\u5074\u93e4\u7a7a|\u4fa7\u9542\u7a7a|\u93e4\u7a7a|\u9542\u7a7a') { [void]$set.Add($D_CUTOUT) }
    if ($s -match '\u934a\u5b50|\u93c8\u5b50|\u934a\u689d|\u93c8\u689d|\u94fe\u6761|chain') { [void]$set.Add($D_CHAIN) }
  }
  $order = @($D_PLATFORM,$D_TSTRAP,$D_ISTRAP,$D_MJ,$D_GOLDTRIM,$D_BOW,$D_REDSOLE,$D_ANKLE,$D_BUCKLE,$D_CUTOUT,$D_CHAIN)
  return $order | Where-Object { $set.Contains($_) }
}

function Parse-DataItemsFromJs([string]$path, [string]$varName) {
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
  $txt = Read-TextUtf8 $path
  $idx = $txt.IndexOf("window.$varName")
  if ($idx -lt 0) { return @() }
  $arrText = Extract-BracketedArrayText -Text $txt -StartIndex $idx
  if (-not $arrText) { return @() }
  $objs = Extract-ObjectsFromArrayText $arrText
  $items = @()
  foreach ($o in $objs) {
    $fn = Get-PropString $o 'filename'
    $img = Get-PropString $o 'image'
    if (-not $fn -or -not $img) { continue }
    $items += [pscustomobject]@{
      filename       = $fn
      image          = $img
      style          = (Get-PropString $o 'style')
      toe            = (Get-PropString $o 'toe')
      heelStyle      = (Get-PropString $o 'heelStyle')
      material       = (Get-PropString $o 'material')
      materialSimple = (Get-PropString $o 'materialSimple')
      color          = (Get-PropString $o 'color')
      decoration     = (Get-PropArray  $o 'decoration')
      rare           = (Get-PropString $o 'rare')
    }
  }
  return $items
}

function Parse-CsvTags([string]$path, [string]$globalName) {
  if (!(Test-Path -LiteralPath $path -PathType Leaf)) { return @{} }
  $txt = Read-TextUtf8 $path
  $idx = $txt.IndexOf("window.$globalName")
  if ($idx -lt 0) { return @{} }
  $brace = $txt.IndexOf('{', $idx)
  if ($brace -lt 0) { return @{} }
  $end = $txt.LastIndexOf('};')
  if ($end -lt 0 -or $end -le $brace) { return @{} }
  $json = $txt.Substring($brace, ($end - $brace + 1))
  $obj = $json | ConvertFrom-Json
  if ($null -eq $obj -or $null -eq $obj.tagsByCode) { return @{} }
  $map = @{}
  foreach ($p in $obj.tagsByCode.PSObject.Properties) { $map[$p.Name.ToUpperInvariant()] = $p.Value }
  return $map
}

if (!(Test-Path -LiteralPath $CatalogDir -PathType Container)) { throw "CatalogDir not found: $CatalogDir" }

$dataJs = Join-Path $CatalogDir 'data.js'
$manualJs = Join-Path $CatalogDir 'data_unprocessed_manual.js'
$importedCsvJs = Join-Path $CatalogDir 'data_imported_csv.js'
$importedPttJs = Join-Path $CatalogDir 'data_imported_ptt.js'
$csvTagsJs = Join-Path $CatalogDir 'csv_tags.js'
$csvTagsPttJs = Join-Path $CatalogDir 'csv_tags_ptt.js'

$items = @()
$items += Parse-DataItemsFromJs $dataJs 'SHOE_DATA'
$items += Parse-DataItemsFromJs $manualJs 'SHOE_DATA'
$items += Parse-DataItemsFromJs $importedCsvJs 'SHOE_DATA_IMPORTED'
$items += Parse-DataItemsFromJs $importedPttJs 'SHOE_DATA_IMPORTED_PTT'

$tagsPtt = Parse-CsvTags $csvTagsPttJs 'CSV_TAGS_PTT'
$tagsCoded = Parse-CsvTags $csvTagsJs 'CSV_TAGS'
$tagsMerged = @{}
foreach ($k in $tagsPtt.Keys) { $tagsMerged[$k] = $tagsPtt[$k] }
foreach ($k in $tagsCoded.Keys) { $tagsMerged[$k] = $tagsCoded[$k] }

# Merge CSV tags into items (fill blanks only)
$mergedItems = @()
foreach ($it in $items) {
  $code = Code-FromFilename $it.filename
  $t = $tagsMerged[$code]

  $style = $it.style
  $toe = $it.toe
  $heelStyle = $it.heelStyle
  $materialSimple = $it.materialSimple
  $material = $it.material
  $color = $it.color
  $decoration = $it.decoration
  $rare = $it.rare

  if ($t) {
    if (-not $style -and $t.style) { $style = $t.style }
    if (-not $toe -and $t.toe) { $toe = $t.toe }
    if (-not $heelStyle -and $t.heelStyle) { $heelStyle = $t.heelStyle }
    if (-not $materialSimple -and $t.materialSimple) { $materialSimple = $t.materialSimple }
    if (-not $color -and $t.color) { $color = $t.color }
    if ((-not $decoration -or $decoration.Count -eq 0) -and $t.decoration) { $decoration = @($t.decoration) }
    if (-not $rare -and $t.rare) { $rare = $t.rare }
  }

  $mergedItems += [pscustomobject]@{
    code           = $code
    filename       = $it.filename
    style          = $style
    toe            = $toe
    heelStyle      = $heelStyle
    material       = $material
    materialSimple = $materialSimple
    color          = $color
    decoration     = $decoration
    rare           = $rare
  }
}

# Group by code (one Notion page per code)
$groups = @{}
foreach ($it in $mergedItems) {
  if (-not $it.code) { continue }
  if (-not $groups.ContainsKey($it.code)) {
    $groups[$it.code] = [pscustomobject]@{
      code = $it.code
      filenames  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      styles     = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      toes       = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      heelStyles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      materials  = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      colors     = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      decorations= New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      rare = $false
    }
  }
  $g = $groups[$it.code]
  [void]$g.filenames.Add($it.filename)

  $styleN = Normalize-Style $it.style $it.toe
  if ($styleN) { [void]$g.styles.Add($styleN) }
  $toeN = Normalize-Toe $it.toe $styleN
  if ($toeN) { [void]$g.toes.Add($toeN) }
  foreach ($h in (Normalize-HeelStyles $it.heelStyle)) { [void]$g.heelStyles.Add($h) }

  $m0 = $it.materialSimple
  if (-not $m0) { $m0 = Normalize-Material $it.material }
  if ($m0) { [void]$g.materials.Add($m0) }

  foreach ($c in (Normalize-Colors $it.color)) { [void]$g.colors.Add($c) }
  foreach ($d in (Normalize-Decorations $it.decoration)) { [void]$g.decorations.Add($d) }

  $rareText = ''
  if ($null -ne $it.rare) { $rareText = $it.rare.ToString().Trim() }
  if ($rareText) { $g.rare = $true }
}

function Set-ToCsvMulti($set, $order) {
  if ($null -eq $set -or $set.Count -eq 0) { return '' }
  $out = @()
  foreach ($k in $order) { if ($set.Contains($k)) { $out += $k } }
  foreach ($k in ($set | Sort-Object)) { if ($out -notcontains $k) { $out += $k } }
  return ($out -join ', ')
}

$styleOrder = @($S_PUMP,$S_SLIPPER,$S_SANDAL,$S_LONGBOOT,$S_SHORTBOOT,$S_ANKLEBOOT)
$toeOrder = @($T_POINT,$T_OPEN,$T_PEEP,$T_ROUND,$T_SQUARE)
$heelOrder = @($H_FLAT,$H_WEDGE,$H_PLATFORM,$H_STILETTO,$H_BLOCK)
$matOrder = @($M_SUEDE,$M_MATTE,$M_PATENT,$M_GLITTER)
$colorOrder = @($C_BLACK,$C_WHITE,$C_RED,$C_PINK,$C_GOLD,$C_SILVER,$C_CLEAR,$C_NUDE,$C_BEIGE,$C_GRAY,$C_BROWN,$C_OTHER)
$decOrder = @($D_PLATFORM,$D_TSTRAP,$D_ISTRAP,$D_MJ,$D_GOLDTRIM,$D_BOW,$D_REDSOLE,$D_ANKLE,$D_BUCKLE,$D_CUTOUT,$D_CHAIN)

$rows = @()
foreach ($k in ($groups.Keys | Sort-Object)) {
  $g = $groups[$k]
  $files = ($g.filenames | Sort-Object)
  $rows += [pscustomobject]@{
    Name       = $g.code
    Filenames  = ($files -join "`n")
    Variants   = $files.Count
    Style      = (Set-ToCsvMulti $g.styles $styleOrder)
    Toe        = (Set-ToCsvMulti $g.toes $toeOrder)
    HeelStyle  = (Set-ToCsvMulti $g.heelStyles $heelOrder)
    Material   = (Set-ToCsvMulti $g.materials $matOrder)
    Color      = (Set-ToCsvMulti $g.colors $colorOrder)
    Decoration = (Set-ToCsvMulti $g.decorations $decOrder)
    Rare       = ($(if ($g.rare) { 'TRUE' } else { 'FALSE' }))
  }
}

$outDir = Split-Path -Parent $OutCsvPath
if (!(Test-Path -LiteralPath $outDir -PathType Container)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$rows | Export-Csv -LiteralPath $OutCsvPath -Encoding UTF8 -NoTypeInformation
Write-Host "Wrote: $OutCsvPath (rows=$($rows.Count))"
