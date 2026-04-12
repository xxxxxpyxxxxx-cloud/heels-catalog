param(
  [Parameter(Mandatory = $true)]
  [string]$NewImagePath,

  [int]$TopK = 8
)

$ErrorActionPreference = "Stop"

function Add-SystemDrawing {
  try {
    Add-Type -AssemblyName System.Drawing | Out-Null
  } catch {
    # On some environments, System.Drawing is already loaded.
  }
}

function Get-DHash64FromBitmap {
  param(
    [Parameter(Mandatory = $true)]
    [System.Drawing.Bitmap]$Bitmap,

    [int]$CropX = 0,
    [int]$CropY = 0,
    [int]$CropW = 0,
    [int]$CropH = 0
  )

  $small = $null
  $g = $null
  try {
    $srcX = 0
    $srcY = 0
    $srcW = $Bitmap.Width
    $srcH = $Bitmap.Height
    if ($CropW -gt 0 -and $CropH -gt 0) {
      $srcX = [Math]::Max(0, [Math]::Min($Bitmap.Width - 1, $CropX))
      $srcY = [Math]::Max(0, [Math]::Min($Bitmap.Height - 1, $CropY))
      $srcW = [Math]::Max(1, [Math]::Min($Bitmap.Width - $srcX, $CropW))
      $srcH = [Math]::Max(1, [Math]::Min($Bitmap.Height - $srcY, $CropH))
    }

    $small = [System.Drawing.Bitmap]::new(9, 8)
    $g = [System.Drawing.Graphics]::FromImage($small)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $destRect = [System.Drawing.Rectangle]::new(0, 0, 9, 8)
    $srcRect = [System.Drawing.Rectangle]::new($srcX, $srcY, $srcW, $srcH)
    $g.DrawImage($Bitmap, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)

    [UInt64]$hash = 0
    for ($y = 0; $y -lt 8; $y++) {
      for ($x = 0; $x -lt 8; $x++) {
        $p1 = $small.GetPixel($x, $y)
        $p2 = $small.GetPixel($x + 1, $y)

        $b1 = (0.299 * $p1.R) + (0.587 * $p1.G) + (0.114 * $p1.B)
        $b2 = (0.299 * $p2.R) + (0.587 * $p2.G) + (0.114 * $p2.B)

        $hash = $hash -shl 1
        if ($b1 -gt $b2) { $hash = $hash -bor 1 }
      }
    }

    return $hash
  } finally {
    if ($g) { $g.Dispose() }
    if ($small) { $small.Dispose() }
  }
}

function Get-DHash64 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [int]$CropX = 0,
    [int]$CropY = 0,
    [int]$CropW = 0,
    [int]$CropH = 0
  )

  if (!(Test-Path -LiteralPath $Path)) {
    throw "Image not found: $Path"
  }

  Add-SystemDrawing
  $bmp = $null
  try {
    $bmp = [System.Drawing.Bitmap]::new($Path)
    return Get-DHash64FromBitmap -Bitmap $bmp -CropX $CropX -CropY $CropY -CropW $CropW -CropH $CropH
  } finally {
    if ($bmp) { $bmp.Dispose() }
  }
}

function Get-DHashSet {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  Add-SystemDrawing
  $bmp = $null
  try {
    $bmp = [System.Drawing.Bitmap]::new($Path)
    $w = $bmp.Width
    $h = $bmp.Height
    # Multi-crop for robustness: full + bottom half + bottom-right
    $full = Get-DHash64FromBitmap -Bitmap $bmp
    $bottom = Get-DHash64FromBitmap -Bitmap $bmp -CropX 0 -CropY ([Math]::Floor($h * 0.5)) -CropW $w -CropH ([Math]::Ceiling($h * 0.5))
    $br = Get-DHash64FromBitmap -Bitmap $bmp -CropX ([Math]::Floor($w * 0.4)) -CropY ([Math]::Floor($h * 0.45)) -CropW ([Math]::Ceiling($w * 0.6)) -CropH ([Math]::Ceiling($h * 0.55))
    return @([UInt64]$full, [UInt64]$bottom, [UInt64]$br)
  } finally {
    if ($bmp) { $bmp.Dispose() }
  }
}

function PopCount64 {
  param([UInt64]$Value)
  $c = 0
  $v = $Value
  while ($v -ne 0) {
    $c++
    $v = $v -band ($v - 1)
  }
  return $c
}

function Hamming64 {
  param(
    [UInt64]$A,
    [UInt64]$B
  )
  return (PopCount64 ($A -bxor $B))
}

function Load-HashCache {
  param([string]$Path)
  $cache = @{}
  if (!(Test-Path -LiteralPath $Path)) { return $cache }
  try {
    $raw = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw
    if (-not $raw) { return $cache }
    $obj = $raw | ConvertFrom-Json
    if ($null -eq $obj) { return $cache }
    foreach ($p in $obj.PSObject.Properties) {
      $cache[$p.Name] = $p.Value
    }
  } catch {
    # ignore broken cache
  }
  return $cache
}

function Save-HashCache {
  param(
    [hashtable]$Cache,
    [string]$Path
  )
  try {
    $json = ($Cache | ConvertTo-Json -Depth 10)
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
  } catch {
    # ignore
  }
}

function Get-HashSetCached {
  param(
    [Parameter(Mandatory = $true)]
    [string]$CacheKey,
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,
    [Parameter(Mandatory = $true)]
    [hashtable]$Cache,
    [Parameter(Mandatory = $true)]
    [ref]$Dirty
  )

  $k = $CacheKey.Replace("\\", "/")
  $fi = Get-Item -LiteralPath $ImagePath
  $mtime = $fi.LastWriteTimeUtc.Ticks
  $size = $fi.Length

  if ($Cache.ContainsKey($k)) {
    $e = $Cache[$k]
    try {
      if ($e.size -eq $size -and $e.mtimeUtc -eq $mtime -and $e.hashes -and $e.hashes.Count -ge 3) {
        return @(
          [UInt64]::Parse($e.hashes[0], [System.Globalization.NumberStyles]::HexNumber),
          [UInt64]::Parse($e.hashes[1], [System.Globalization.NumberStyles]::HexNumber),
          [UInt64]::Parse($e.hashes[2], [System.Globalization.NumberStyles]::HexNumber)
        )
      }
    } catch {
      # fallthrough to recompute
    }
  }

  $hashes = Get-DHashSet -Path $ImagePath
  $Cache[$k] = [pscustomobject]@{
    size     = $size
    mtimeUtc = $mtime
    hashes   = @($hashes[0].ToString("x16"), $hashes[1].ToString("x16"), $hashes[2].ToString("x16"))
  }
  $Dirty.Value = $true
  return $hashes
}

function Extract-QuotedStrings {
  param([string]$Text)
  if (-not $Text) { return @() }
  return [regex]::Matches($Text, '"([^"\\\\]*(?:\\\\.[^"\\\\]*)*)"') | ForEach-Object {
    $_.Groups[1].Value -replace '\\\\"', '"' -replace '\\\\n', "`n" -replace '\\\\r', "`r" -replace '\\\\t', "`t"
  }
}

function Get-PropString {
  param(
    [string]$ObjText,
    [string]$Key
  )
  $k = [regex]::Escape($Key)
  $pat = '(?m)^\s*' + $k + '\s*:\s*"([^"]*)"\s*,?\s*$'
  $m = [regex]::Match($ObjText, $pat)
  if ($m.Success) { return $m.Groups[1].Value }
  return $null
}

function Get-PropArray {
  param(
    [string]$ObjText,
    [string]$Key
  )
  $k = [regex]::Escape($Key)
  $pat = '(?ms)^\s*' + $k + '\s*:\s*\[([\s\S]*?)\]\s*,?\s*$'
  $m = [regex]::Match($ObjText, $pat)
  if ($m.Success) { return (Extract-QuotedStrings $m.Groups[1].Value) }
  $s = Get-PropString -ObjText $ObjText -Key $Key
  if ($s) { return @($s) }
  return @()
}

function Get-PropNumber {
  param(
    [string]$ObjText,
    [string]$Key
  )
  $k = [regex]::Escape($Key)
  $m = [regex]::Match($ObjText, '(?m)^\s*' + $k + '\s*:\s*([0-9]+(?:\.[0-9]+)?)\s*,?\s*$')
  if ($m.Success) { return [double]$m.Groups[1].Value }
  return $null
}

function Derive-HeelHeight {
  param([object]$HeelHeightCm)
  if ($null -eq $HeelHeightCm) { return $null }
  $h = 0.0
  try { $h = [double]$HeelHeightCm } catch { return $null }
  if ($h -lt 1.5) { return "平底" }
  if ($h -lt 5) { return "低跟" }
  if ($h -lt 8) { return "中跟" }
  if ($h -lt 11) { return "高跟" }
  return "超高跟"
}

function Derive-MaterialSimple {
  param([string]$Material)
  $s = $Material
  if ($null -eq $s) { $s = "" } else { $s = $s.ToString() }
  $s = $s.ToLowerInvariant()
  if (-not $s) { return $null }
  if ($s.Contains("麂皮") -or $s.Contains("絨面")) { return "麂皮" }
  if ($s.Contains("亮粉") -or $s.Contains("閃") -or $s.Contains("金屬")) { return "亮粉" }
  if ($s.Contains("漆皮") -or $s.Contains("亮面") -or $s.Contains("鏡面")) { return "漆皮" }
  if ($s.Contains("霧面") -or $s.Contains("皮革") -or $s.Contains("人造皮") -or $s.Contains("皮")) { return "霧面皮" }
  return $null
}

function Get-ShoeDataFromJs {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DataJsPath,
    [Parameter(Mandatory = $true)]
    [string]$CatalogRoot,
    [Parameter(Mandatory = $true)]
    [hashtable]$Cache,
    [Parameter(Mandatory = $true)]
    [ref]$CacheDirty
  )

  $raw = Get-Content -LiteralPath $DataJsPath -Encoding UTF8 -Raw
  $start = $raw.IndexOf("window.SHOE_DATA")
  if ($start -lt 0) { throw "Cannot find window.SHOE_DATA in $DataJsPath" }
  $arrStart = $raw.IndexOf("[", $start)
  $arrEnd = $raw.LastIndexOf("]")
  if ($arrStart -lt 0 -or $arrEnd -lt 0 -or $arrEnd -le $arrStart) { throw "Cannot find array bounds in $DataJsPath" }
  $body = $raw.Substring($arrStart, ($arrEnd - $arrStart + 1))

  $objs = New-Object System.Collections.Generic.List[string]
  $depth = 0
  $buf = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $body.Length; $i++) {
    $ch = $body[$i]
    if ($ch -eq "{") {
      $depth++
    }
    if ($depth -gt 0) {
      [void]$buf.Append($ch)
    }
    if ($ch -eq "}") {
      $depth--
      if ($depth -eq 0) {
        $objs.Add($buf.ToString()) | Out-Null
        $buf.Clear() | Out-Null
      }
    }
  }

  $items = @()
  foreach ($t in $objs) {
    $filename = Get-PropString -ObjText $t -Key "filename"
    $imageRel = Get-PropString -ObjText $t -Key "image"
    if (-not $filename -or -not $imageRel) { continue }

    $item = [pscustomobject]@{
      id             = (Get-PropString -ObjText $t -Key "id")
      filename       = $filename
      image          = $imageRel
      imagePath      = (Join-Path $CatalogRoot $imageRel)
      style          = (Get-PropString -ObjText $t -Key "style")
      toe            = (Get-PropString -ObjText $t -Key "toe")
      heelStyle      = (Get-PropString -ObjText $t -Key "heelStyle")
      heelHeightCm   = (Get-PropNumber -ObjText $t -Key "heelHeightCm")
      heelHeight     = (Get-PropString -ObjText $t -Key "heelHeight")
      material       = (Get-PropString -ObjText $t -Key "material")
      materialSimple = (Get-PropString -ObjText $t -Key "materialSimple")
      color          = (Get-PropString -ObjText $t -Key "color")
      decoration     = (Get-PropArray -ObjText $t -Key "decoration")
    }

    if (Test-Path -LiteralPath $item.imagePath) {
      try {
        if (-not $item.heelHeight) { $item.heelHeight = Derive-HeelHeight -HeelHeightCm $item.heelHeightCm }
        if (-not $item.materialSimple) { $item.materialSimple = Derive-MaterialSimple -Material $item.material }

        $hashes = Get-HashSetCached -CacheKey $item.image -ImagePath $item.imagePath -Cache $Cache -Dirty $CacheDirty
        $item | Add-Member -NotePropertyName dhashes -NotePropertyValue $hashes
      } catch {
        # skip hash if cannot decode image
      }
      $items += $item
    }
  }

  return $items | Where-Object { $_.dhashes -ne $null }
}

function Suggest-FromMatches {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$Matches
  )

  if (-not $Matches -or $Matches.Count -eq 0) { return $null }

  # Weighted vote: closer distance => higher weight
  $weights = @{}
  foreach ($m in $Matches) {
    $w = [Math]::Max(0.1, (64 - [double]$m.dist))
    foreach ($k in @("style", "toe", "heelStyle", "heelHeight", "materialSimple", "color")) {
      $v = $m.item.$k
      if ($null -eq $v) { $v = "" } else { $v = $v.ToString() }
      $v = $v.Trim()
      if (-not $v) { continue }
      $key = "$k::$v"
      $prev = 0
      if ($weights.ContainsKey($key)) { $prev = [double]$weights[$key] }
      $weights[$key] = $prev + $w
    }
    foreach ($d in @($m.item.decoration)) {
      $v = $d
      if ($null -eq $v) { $v = "" } else { $v = $v.ToString() }
      $v = $v.Trim()
      if (-not $v) { continue }
      $key = "decoration::$v"
      $prev = 0
      if ($weights.ContainsKey($key)) { $prev = [double]$weights[$key] }
      $weights[$key] = $prev + ($w * 0.7)
    }
  }

  function PickTop($field) {
    $best = $null
    $bestScore = -1
    foreach ($k in $weights.Keys) {
      if (-not $k.StartsWith("$field::")) { continue }
      $s = [double]$weights[$k]
      if ($s -gt $bestScore) { $bestScore = $s; $best = $k.Substring($field.Length + 2) }
    }
    return $best
  }

  $dec = @()
  foreach ($k in $weights.Keys) {
    if (-not $k.StartsWith("decoration::")) { continue }
    if ([double]$weights[$k] -ge 20) { $dec += $k.Substring("decoration::".Length) }
  }
  $dec = $dec | Sort-Object -Unique

  return [pscustomobject]@{
    style          = (PickTop "style")
    toe            = (PickTop "toe")
    heelStyle      = (PickTop "heelStyle")
    heelHeight     = (PickTop "heelHeight")
    materialSimple = (PickTop "materialSimple")
    color          = (PickTop "color")
    decoration     = $dec
  }
}

$catalogRoot = Split-Path -Parent $PSScriptRoot
$dataJsPath = Join-Path $catalogRoot "data.js"
$cachePath = Join-Path $PSScriptRoot "dhash_cache.json"
$cacheDirty = $false
$cache = Load-HashCache -Path $cachePath

$items = Get-ShoeDataFromJs -DataJsPath $dataJsPath -CatalogRoot $catalogRoot -Cache $cache -CacheDirty ([ref]$cacheDirty)
if (-not $items -or $items.Count -eq 0) {
  throw "No hashed items found from $dataJsPath"
}

$newHashes = Get-DHashSet -Path $NewImagePath

$scored = @()
foreach ($it in $items) {
  $best = 64
  foreach ($nh in $newHashes) {
    foreach ($ih in $it.dhashes) {
      $d = Hamming64 -A ([UInt64]$nh) -B ([UInt64]$ih)
      if ($d -lt $best) { $best = $d }
    }
  }
  $scored += [pscustomobject]@{
    dist = $best
    item = $it
  }
}
$matches = $scored | Sort-Object dist, @{ Expression = { $_.item.filename }; Ascending = $true } | Select-Object -First $TopK

$suggest = Suggest-FromMatches -Matches $matches

Write-Output ("NewImage: {0}" -f $NewImagePath)
Write-Output ("dHash(full/bottom/br): 0x{0} / 0x{1} / 0x{2}" -f $newHashes[0].ToString("x16"), $newHashes[1].ToString("x16"), $newHashes[2].ToString("x16"))
Write-Output ""
Write-Output "Top matches:"
$i = 1
foreach ($m in $matches) {
  $it = $m.item
  $dec = if ($it.decoration -and $it.decoration.Count) { ($it.decoration -join "、") } else { "無裝飾" }
  Write-Output ("{0}. dist={1} / {2} / {3}/{4}/{5}/{6}/{7}/{8}/{9}" -f $i, $m.dist, $it.filename, $it.style, $it.toe, $it.heelStyle, $it.heelHeight, $it.materialSimple, $it.color, $dec)
  $i++
}

Write-Output ""
if ($suggest) {
  $dec2 = if ($suggest.decoration -and $suggest.decoration.Count) { ($suggest.decoration -join "、") } else { "無裝飾" }
  Write-Output ("Suggested (slash): {0}/{1}/{2}/{3}/{4}/{5}/{6}/{7}" -f `
    (Split-Path -Leaf $NewImagePath), $suggest.style, $suggest.toe, $suggest.heelStyle, $suggest.heelHeight, $suggest.materialSimple, $suggest.color, $dec2)
} else {
  Write-Output "Suggested: (none)"
}

if ($cacheDirty) {
  Save-HashCache -Cache $cache -Path $cachePath
}
