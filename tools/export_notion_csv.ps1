param(
  [string]$CatalogDir = "D:\Codex\Image\heels_catalog",
  [string]$OutCsvPath = "D:\Codex\Image\heels_catalog\export_notion.csv"
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Read-TextUtf8([string]$path) {
  return [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path))
}

function Extract-BracketedArrayText {
  param(
    [Parameter(Mandatory = $true)] [string]$Text,
    [Parameter(Mandatory = $true)] [int]$StartIndex
  )
  $i = $Text.IndexOf('[', $StartIndex)
  if ($i -lt 0) { return $null }

  $depth = 0
  $inStr = $false
  $strQuote = ''
  for ($p = $i; $p -lt $Text.Length; $p++) {
    $ch = $Text[$p]
    if ($inStr) {
      if ($ch -eq '\') { $p++; continue }
      if ($ch -eq $strQuote) { $inStr = $false; continue }
      continue
    }

    if ($ch -eq '"' -or $ch -eq "'") { $inStr = $true; $strQuote = $ch; continue }
    if ($ch -eq '[') { $depth++; continue }
    if ($ch -eq ']') {
      $depth--
      if ($depth -eq 0) {
        return $Text.Substring($i, ($p - $i + 1))
      }
    }
  }
  return $null
}

function Extract-ObjectsFromArrayText([string]$arrayText) {
  if (-not $arrayText) { return @() }
  $objs = New-Object System.Collections.Generic.List[string]
  $depth = 0
  $inStr = $false
  $strQuote = ''
  $buf = New-Object System.Text.StringBuilder

  for ($i = 0; $i -lt $arrayText.Length; $i++) {
    $ch = $arrayText[$i]
    if ($inStr) {
      [void]$buf.Append($ch)
      if ($ch -eq '\') { if ($i + 1 -lt $arrayText.Length) { $i++; [void]$buf.Append($arrayText[$i]) }; continue }
      if ($ch -eq $strQuote) { $inStr = $false }
      continue
    }

    if ($ch -eq '"' -or $ch -eq "'") { $inStr = $true; $strQuote = $ch; if ($depth -gt 0) { [void]$buf.Append($ch) }; continue }

    if ($ch -eq '{') {
      $depth++
      [void]$buf.Append($ch)
      continue
    }
    if ($depth -gt 0) { [void]$buf.Append($ch) }
    if ($ch -eq '}') {
      $depth--
      if ($depth -eq 0) {
        $objs.Add($buf.ToString()) | Out-Null
        $buf.Clear() | Out-Null
      }
    }
  }
  return $objs.ToArray()
}

function Unescape-JsonLikeString([string]$s) {
  if ($null -eq $s) { return $null }
  $t = $s -replace '\\\\"', '"' -replace '\\\\n', "`n" -replace '\\\\r', "`r" -replace '\\\\t', "`t" -replace "\\\\'", "'"
  return $t
}

function Get-PropString([string]$objText, [string]$key) {
  $k = [regex]::Escape($key)
  $m = [regex]::Match($objText, "(?m)^\s*$k\s*:\s*`"([^`"]*)`"\s*,?\s*$")
  if ($m.Success) { return (Unescape-JsonLikeString $m.Groups[1].Value) }
  $m2 = [regex]::Match($objText, "(?m)^\s*$k\s*:\s*'([^']*)'\s*,?\s*$")
  if ($m2.Success) { return (Unescape-JsonLikeString $m2.Groups[1].Value) }
  return $null
}

function Extract-QuotedStrings([string]$text) {
  if (-not $text) { return @() }
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($m in [regex]::Matches($text, '"([^"\\\\]*(?:\\\\.[^"\\\\]*)*)"')) {
    $out.Add((Unescape-JsonLikeString $m.Groups[1].Value)) | Out-Null
  }
  foreach ($m in [regex]::Matches($text, "'([^'\\\\]*(?:\\\\.[^'\\\\]*)*)'")) {
    $out.Add((Unescape-JsonLikeString $m.Groups[1].Value)) | Out-Null
  }
  return $out.ToArray()
}

function Get-PropArray([string]$objText, [string]$key) {
  $k = [regex]::Escape($key)
  $m = [regex]::Match($objText, "(?ms)^\s*$k\s*:\s*\[([\s\S]*?)\]\s*,?\s*$")
  if ($m.Success) { return (Extract-QuotedStrings $m.Groups[1].Value) }
  $s = Get-PropString -objText $objText -key $key
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
  if ($s -match '過膝|膝|長筒|長靴') { return '長靴' }
  if ($s -match '踝靴|踝') { return '踝靴' }
  if ($s -match '短靴|短筒') { return '短靴' }
  if ($s -match '靴') { return '短靴' }
  if ($s -match '拖鞋|拖') { return '拖鞋' }
  if ($s -match '涼鞋|涼拖|涼') { return '涼鞋' }
  if ($t -eq '露趾' -or $t -eq '魚頭') { return '涼鞋' }
  return '包鞋'
}

function Normalize-Toe([string]$toe, [string]$style) {
  $t = ''
  $s = ''
  if ($null -ne $toe) { $t = $toe.Trim() }
  if ($null -ne $style) { $s = $style.Trim() }
  if ($t -match '尖') { return '尖頭' }
  if ($t -match '方') { return '方頭' }
  if ($t -match '圓|圆') { return '圓頭' }
  if ($t -match '露趾|露指|open\s*toe') { return '露趾' }
  if ($t -match '魚口|鱼口|魚嘴|鱼嘴|peep|魚頭') { return '魚頭' }
  if (-not $t -and ($s -eq '涼鞋' -or $s -eq '拖鞋')) { return '露趾' }
  return ''
}

function Normalize-HeelStyles([object]$v) {
  $out = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($token in (To-Array $v)) {
    $s = ''
    if ($null -ne $token) { $s = $token.ToString().Trim() }
    if (-not $s) { continue }
    if ($s -match '平底|平跟|flat') { [void]$out.Add('平底') }
    if ($s -match '坡跟|楔跟|楔形|wedge') { [void]$out.Add('坡跟') }
    if ($s -match '厚底|松糕|厚台|platform') { [void]$out.Add('厚底') }
    if ($s -match '防水台') { [void]$out.Add('厚底') }
    if ($s -match '細跟|细跟|stiletto') { [void]$out.Add('細跟') }
    if ($s -match '粗跟|block\s*heel|block|粗') { [void]$out.Add('粗跟') }
    if ($s -match '高跟|high\s*heel') {
      if ($s -match '粗') { [void]$out.Add('粗跟') } else { [void]$out.Add('細跟') }
    }
  }
  $order = @('平底','坡跟','厚底','細跟','粗跟')
  return $order | Where-Object { $out.Contains($_) }
}

function Normalize-Material([string]$m) {
  $s = ''
  if ($null -ne $m) { $s = $m.ToString().ToLowerInvariant() }
  if (-not $s) { return '' }
  if ($s -match '麂皮|絨面') { return '麂皮' }
  if ($s -match '亮粉|閃|金屬|glitter') { return '亮粉' }
  if ($s -match '漆皮|亮面|鏡面|patent') { return '漆皮' }
  if ($s -match '霧面|皮革|人造皮|皮') { return '霧面皮' }
  return ''
}

function Normalize-Colors([object]$v) {
  $out = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($token in (To-Array $v)) {
    $s = ''
    if ($null -ne $token) { $s = $token.ToString().Trim() }
    if (-not $s) { continue }
    if ($s -match '透明|clear') { [void]$out.Add('透明') }
    if ($s -match '黑') { [void]$out.Add('黑') }
    if ($s -match '白') { [void]$out.Add('白') }
    if ($s -match '銀|银|silv') { [void]$out.Add('銀') }
    if ($s -match '金|gold') { [void]$out.Add('金') }
    if ($s -match '桃紅|桃红|玫紅|玫红|fuchsia|magenta|hot\s*pink') { [void]$out.Add('桃紅') }
    elseif ($s -match '紅|红|red') { [void]$out.Add('紅') }
    if ($s -match '膚|肤|nude|skin') { [void]$out.Add('膚') }
    if ($s -match '米|奶|象牙|ivory|beige') { [void]$out.Add('米') }
    if ($s -match '灰|gray') { [void]$out.Add('灰') }
    if ($s -match '棕|咖|啡|brown') { [void]$out.Add('棕') }
  }
  if ($out.Count -eq 0) { [void]$out.Add('其他') }
  $order = @('黑','白','紅','桃紅','金','銀','透明','膚','米','灰','棕','其他')
  return $order | Where-Object { $out.Contains($_) }
}

function Normalize-Decorations([object]$v) {
  $out = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
  foreach ($token in (To-Array $v)) {
    $s = ''
    if ($null -ne $token) { $s = $token.ToString().Trim() }
    if (-not $s) { continue }
    if ($s -match '防水台|厚底|台(?!灣)') { [void]$out.Add('防水台') }
    if ($s -match 'T字帶|丁字帶|T\s*字|丁\s*字') { [void]$out.Add('T字帶') }
    if ($s -match '一字帶|一字(帶)?') { [void]$out.Add('一字帶') }
    if ($s -match '瑪莉珍|瑪麗珍|玛丽珍|mary\s*jane') { [void]$out.Add('瑪莉珍') }
    if ($s -match '金邊|金色邊|金邊飾|金框') { [void]$out.Add('金邊') }
    if ($s -match '蝴蝶結|蝴結|蝴蝶') { [void]$out.Add('蝴蝶結') }
    if ($s -match '紅底|红底|red\s*sole|louboutin') { [void]$out.Add('紅底') }
    if ($s -match '踝帶|腳踝帶|踝繫|ankle\s*strap|ankle-strap') { [void]$out.Add('踝帶') }
    if ($s -match '金扣|金釦|金扣環') { [void]$out.Add('金扣') }
    if ($s -match '側空|侧空|側鏤空|侧镂空|鏤空|镂空') { [void]$out.Add('側空') }
    if ($s -match '鍊子|鏈子|鍊條|鏈條|链条|chain') { [void]$out.Add('鍊子') }
  }
  $order = @('防水台','T字帶','一字帶','瑪莉珍','金邊','蝴蝶結','紅底','踝帶','金扣','側空','鍊子')
  return $order | Where-Object { $out.Contains($_) }
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
  foreach ($p in $obj.tagsByCode.PSObject.Properties) {
    $map[$p.Name.ToUpperInvariant()] = $p.Value
  }
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
$items += Parse-DataItemsFromJs -path $dataJs -varName 'SHOE_DATA'
$items += Parse-DataItemsFromJs -path $manualJs -varName 'SHOE_DATA'
$items += Parse-DataItemsFromJs -path $importedCsvJs -varName 'SHOE_DATA_IMPORTED'
$items += Parse-DataItemsFromJs -path $importedPttJs -varName 'SHOE_DATA_IMPORTED_PTT'

$tagsPtt = Parse-CsvTags -path $csvTagsPttJs -globalName 'CSV_TAGS_PTT'
$tagsCoded = Parse-CsvTags -path $csvTagsJs -globalName 'CSV_TAGS'
$tagsMerged = @{}
foreach ($k in $tagsPtt.Keys) { $tagsMerged[$k] = $tagsPtt[$k] }
foreach ($k in $tagsCoded.Keys) { $tagsMerged[$k] = $tagsCoded[$k] } # coded overrides

# Merge tags into items (fill blanks only)
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
    code          = $code
    filename      = $it.filename
    image         = $it.image
    style         = $style
    toe           = $toe
    heelStyle     = $heelStyle
    material      = $material
    materialSimple= $materialSimple
    color         = $color
    decoration    = $decoration
    rare          = $rare
  }
}

# Group by code for Notion pages
$groups = @{}
foreach ($it in $mergedItems) {
  if (-not $it.code) { continue }
  if (-not $groups.ContainsKey($it.code)) {
    $groups[$it.code] = [pscustomobject]@{
      code = $it.code
      filenames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      styles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      toes = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      heelStyles = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      materials = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      colors = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      decorations = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
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

function Set-ToCsvMulti([System.Collections.Generic.HashSet[string]]$set, [string[]]$order) {
  if ($null -eq $set -or $set.Count -eq 0) { return '' }
  if ($order -and $order.Count) {
    $out = @()
    foreach ($k in $order) { if ($set.Contains($k)) { $out += $k } }
    foreach ($k in ($set | Sort-Object)) { if ($out -notcontains $k) { $out += $k } }
    return ($out -join ', ')
  }
  return (($set | Sort-Object) -join ', ')
}

$styleOrder = @('包鞋','拖鞋','涼鞋','長靴','短靴','踝靴')
$toeOrder = @('尖頭','露趾','魚頭','圓頭','方頭')
$heelOrder = @('平底','坡跟','厚底','細跟','粗跟')
$matOrder = @('麂皮','霧面皮','漆皮','亮粉')
$colorOrder = @('黑','白','紅','桃紅','金','銀','透明','膚','米','灰','棕','其他')
$decOrder = @('防水台','T字帶','一字帶','瑪莉珍','金邊','蝴蝶結','紅底','踝帶','金扣','側空','鍊子')

$rows = @()
foreach ($k in ($groups.Keys | Sort-Object)) {
  $g = $groups[$k]
  $files = ($g.filenames | Sort-Object)
  $rows += [pscustomobject]@{
    Name       = $g.code
    Filenames  = ($files -join "`n")
    Variants   = $files.Count
    '款式'       = (Set-ToCsvMulti $g.styles $styleOrder)
    '鞋頭'       = (Set-ToCsvMulti $g.toes $toeOrder)
    '鞋跟樣式'   = (Set-ToCsvMulti $g.heelStyles $heelOrder)
    '材質'       = (Set-ToCsvMulti $g.materials $matOrder)
    '顏色'       = (Set-ToCsvMulti $g.colors $colorOrder)
    '裝飾'       = (Set-ToCsvMulti $g.decorations $decOrder)
    '少見款式'   = ($g.rare ? 'TRUE' : 'FALSE')
  }
}

$outDir = Split-Path -Parent $OutCsvPath
if (!(Test-Path -LiteralPath $outDir -PathType Container)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$rows | Export-Csv -LiteralPath $OutCsvPath -Encoding UTF8 -NoTypeInformation
Write-Host "Wrote: $OutCsvPath (rows=$($rows.Count))"
