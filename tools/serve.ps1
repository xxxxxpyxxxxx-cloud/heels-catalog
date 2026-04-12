param(
  [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.css' { 'text/css; charset=utf-8' }
    '.js' { 'text/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.svg' { 'image/svg+xml' }
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    '.webp' { 'image/webp' }
    default { 'application/octet-stream' }
  }
}

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $toolsDir  # heels_catalog

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "Serving: $root"
Write-Host "Open:    http://localhost:$Port/tools/knn_clip_demo.html"
Write-Host "Stop with Ctrl+C"

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    try {
      $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath.TrimStart('/'))
      if ([string]::IsNullOrWhiteSpace($rel)) { $rel = 'index.html' }
      $rel = $rel -replace '/', '\'
      if ($rel.Contains('..')) { throw "Invalid path" }

      $full = Join-Path $root $rel
      if (!(Test-Path -LiteralPath $full -PathType Leaf)) {
        $res.StatusCode = 404
        $bytes = [Text.Encoding]::UTF8.GetBytes("404 Not Found")
        $res.ContentType = 'text/plain; charset=utf-8'
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
        $res.OutputStream.Close()
        continue
      }

      $res.StatusCode = 200
      $res.ContentType = Get-ContentType $full
      $bytes = [IO.File]::ReadAllBytes($full)
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.OutputStream.Close()
    } catch {
      $res.StatusCode = 500
      $bytes = [Text.Encoding]::UTF8.GetBytes("500 Server Error")
      $res.ContentType = 'text/plain; charset=utf-8'
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
      $res.OutputStream.Close()
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}

