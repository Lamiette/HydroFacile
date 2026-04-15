$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$imagesDir = Join-Path $repoRoot 'images'
$svgPath = Join-Path $imagesDir 'favicon.svg'
$masterPngPath = Join-Path $imagesDir 'favicon.png'
$appleTouchPath = Join-Path $imagesDir 'apple-touch-icon.png'
$icoPath = Join-Path $imagesDir 'favicon.ico'
$edgeExe = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'

if (-not (Test-Path -LiteralPath $svgPath)) {
  throw "Source SVG introuvable: $svgPath"
}

if (-not (Test-Path -LiteralPath $edgeExe)) {
  throw "Microsoft Edge est introuvable: $edgeExe"
}

$sizes = 16, 32, 48, 64, 180, 192, 256, 512
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('hydrofacile-favicon-' + [guid]::NewGuid().ToString('N'))
$userDataDir = Join-Path $tempRoot 'edge-profile'
$renderHtmlPath = Join-Path $tempRoot 'render-favicon.html'

New-Item -ItemType Directory -Path $tempRoot | Out-Null
New-Item -ItemType Directory -Path $userDataDir | Out-Null

try {
  $svgUri = [Uri]::new($svgPath)
  $renderHtml = @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      overflow: hidden;
      background: transparent;
    }

    body {
      display: grid;
      place-items: center;
    }

    img {
      width: 100%;
      height: 100%;
      display: block;
      object-fit: contain;
    }
  </style>
</head>
<body>
  <img src="$($svgUri.AbsoluteUri)" alt="HydroFacile favicon">
</body>
</html>
"@
  Set-Content -LiteralPath $renderHtmlPath -Value $renderHtml -Encoding UTF8

  $renderUri = [Uri]::new($renderHtmlPath)
  $edgeArgs = @(
    '--headless',
    '--disable-gpu',
    '--hide-scrollbars',
    '--default-background-color=00000000',
    '--window-size=512,512',
    "--user-data-dir=$userDataDir",
    "--screenshot=$masterPngPath",
    $renderUri.AbsoluteUri
  )

  & $edgeExe @edgeArgs | Out-Null

  if (-not (Test-Path -LiteralPath $masterPngPath)) {
    throw "La capture PNG principale n'a pas ete generee."
  }

  $masterBitmap = [System.Drawing.Bitmap]::FromFile($masterPngPath)
  try {
    foreach ($size in $sizes) {
      $targetPath =
        if ($size -eq 180) { $appleTouchPath }
        elseif ($size -eq 512) { Join-Path $imagesDir 'favicon-512.png' }
        else { Join-Path $imagesDir ("favicon-{0}.png" -f $size) }

      $targetBitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
      $graphics = [System.Drawing.Graphics]::FromImage($targetBitmap)

      try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($masterBitmap, 0, 0, $size, $size)
        $targetBitmap.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
      }
      finally {
        $graphics.Dispose()
        $targetBitmap.Dispose()
      }
    }
  }
  finally {
    $masterBitmap.Dispose()
  }

  $icoSizes = 16, 32, 48, 64
  $iconEntries = foreach ($size in $icoSizes) {
    $path = Join-Path $imagesDir ("favicon-{0}.png" -f $size)
    [pscustomobject]@{
      Size = $size
      Bytes = [System.IO.File]::ReadAllBytes($path)
    }
  }

  $stream = [System.IO.File]::Open($icoPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
  $writer = New-Object System.IO.BinaryWriter($stream)

  try {
    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$iconEntries.Count)

    $offset = 6 + (16 * $iconEntries.Count)

    foreach ($entry in $iconEntries) {
      $dimension = if ($entry.Size -ge 256) { 0 } else { $entry.Size }
      $writer.Write([byte]$dimension)
      $writer.Write([byte]$dimension)
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([UInt16]1)
      $writer.Write([UInt16]32)
      $writer.Write([UInt32]$entry.Bytes.Length)
      $writer.Write([UInt32]$offset)
      $offset += $entry.Bytes.Length
    }

    foreach ($entry in $iconEntries) {
      $writer.Write($entry.Bytes)
    }
  }
  finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}
finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
