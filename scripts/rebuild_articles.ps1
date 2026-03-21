$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$rawDir = Join-Path $root "raw-singlefile"
$articlesDir = Join-Path $root "articles"
$imagesDir = Join-Path $root "images\articles"
$siteUrl = "https://ecobalcon.com"

function HtmlEscape {
  param([string]$text)

  if ($null -eq $text) { return "" }
  return [System.Security.SecurityElement]::Escape([string]$text)
}

function Convert-IsoDateToFrench {
  param([string]$iso)

  if ([string]::IsNullOrWhiteSpace($iso)) { return "" }

  $months = @(
    "", "janvier", "fevrier", "mars", "avril", "mai", "juin",
    "juillet", "aout", "septembre", "octobre", "novembre", "decembre"
  )

  $dt = [DateTime]::Parse($iso).ToLocalTime()
  return "{0} {1} {2}" -f $dt.Day, $months[$dt.Month], $dt.Year
}

function Convert-TimeRequired {
  param([string]$value)

  if ($value -match '^PT(?:(\d+)H)?(?:(\d+)M)?$') {
    $hours = if ($matches[1]) { [int]$matches[1] } else { 0 }
    $minutes = if ($matches[2]) { [int]$matches[2] } else { 0 }
    if ($hours -gt 0 -and $minutes -gt 0) { return "$hours h $minutes" }
    if ($hours -gt 0) { return "$hours h" }
    if ($minutes -gt 0) { return "$minutes min" }
  }

  return ""
}

function Get-ImageFileName {
  param(
    [string]$url,
    [string]$slug
  )

  if ([string]::IsNullOrWhiteSpace($url)) {
    return "$slug.webp"
  }

  $decodedUrl = [System.Net.WebUtility]::HtmlDecode($url)

  try {
    $uri = [System.Uri]$decodedUrl
    $fileName = [System.IO.Path]::GetFileName($uri.AbsolutePath)
  } catch {
    $fileName = [System.IO.Path]::GetFileName(($decodedUrl -split '\?')[0])
  }

  if ([string]::IsNullOrWhiteSpace($fileName)) {
    $fileName = "$slug.webp"
  }

  return [regex]::Replace($fileName, '[^A-Za-z0-9._-]', '-')
}

function Get-ImageCanonicalUrl {
  param([string]$fileName)

  if ([string]::IsNullOrWhiteSpace($fileName)) { return "" }
  return "$siteUrl/images/articles/$fileName"
}

function Get-ImagePagePath {
  param(
    [string]$fileName,
    [string]$pagePrefix
  )

  if ([string]::IsNullOrWhiteSpace($fileName)) { return "" }
  return "$pagePrefix$fileName"
}

function Ensure-ArticleImages {
  param([object[]]$allArticles)

  if (-not (Test-Path $imagesDir)) {
    New-Item -ItemType Directory -Force -Path $imagesDir | Out-Null
  }

  try {
    [Net.ServicePointManager]::SecurityProtocol = `
      [Net.SecurityProtocolType]::Tls12 -bor `
      [Net.SecurityProtocolType]::Tls11 -bor `
      [Net.SecurityProtocolType]::Tls
  } catch {
  }

  $imageMap = [ordered]@{}
  foreach ($article in $allArticles) {
    if ($article.ImageRemoteUrl -and $article.ImageFileName) {
      $imageMap[$article.ImageFileName] = $article.ImageRemoteUrl
    }
  }

  foreach ($entry in $imageMap.GetEnumerator()) {
    $fileName = $entry.Key
    $remoteUrl = $entry.Value
    $outputPath = Join-Path $imagesDir $fileName

    if ((Test-Path $outputPath) -and ((Get-Item $outputPath).Length -gt 0)) {
      continue
    }

    try {
      Invoke-WebRequest `
        -Uri $remoteUrl `
        -OutFile $outputPath `
        -UseBasicParsing `
        -Headers @{ "User-Agent" = "Mozilla/5.0 (compatible; EcoBalconStatic/1.0)" }
      Write-Output "Downloaded image $fileName"
    } catch {
      throw "Impossible de telecharger l'image distante $remoteUrl"
    }
  }
}

function Get-CardExcerpt {
  param(
    [string]$text,
    [int]$maxLength = 148
  )

  $clean = ($text -replace '\s+', ' ').Trim()
  if ($clean.Length -le $maxLength) { return $clean }

  $slice = $clean.Substring(0, $maxLength)
  $lastSpace = $slice.LastIndexOf(' ')
  if ($lastSpace -gt 60) {
    $slice = $slice.Substring(0, $lastSpace)
  }

  return ($slice.TrimEnd(@('.',' ',',',';',':')) + "...")
}

function Get-SchemaData {
  param([string]$content)

  $schemaMatch = [regex]::Match($content, '<script type=application/ld\+json>(?<json>\{.*?\})</script>', 'Singleline')
  if (-not $schemaMatch.Success) {
    throw "Schema JSON-LD introuvable."
  }

  return ($schemaMatch.Groups["json"].Value | ConvertFrom-Json)
}

function Get-HeroCaption {
  param([string]$content)

  $patterns = @(
    'title="(?<caption>[^"]+)"[^>]*class="image image--grid loaded image-wrapper--desktop"'
    'title="(?<caption>[^"]+)"[^>]*class="image image--grid loaded image-wrapper--mobile'
    'title="(?<caption>[^"]+)"[^>]*class="image image--grid'
    'alt="(?<caption>[^"]+)"[^>]*class="image__image--cropped image__image"'
    'title="(?<caption>[^"]+)"[^>]*data-qa=grid-image'
  )

  foreach ($pattern in $patterns) {
    $match = [regex]::Match($content, $pattern, 'Singleline')
    if (-not $match.Success) { continue }

    $caption = [System.Net.WebUtility]::HtmlDecode($match.Groups["caption"].Value).Trim()
    if (-not $caption) { continue }
    if ($caption -match '^(Go to |Instagram|Twitter|X$|EcoBalcon$)') { continue }
    return $caption
  }

  return ""
}

function Get-AuthorNameFromPageData {
  param(
    [string]$content,
    [string]$slug
  )

  if ([string]::IsNullOrWhiteSpace($slug)) { return "" }

  $searchContent = [System.Net.WebUtility]::HtmlDecode($content)
  $matches = [regex]::Matches(
    $searchContent,
    '"authorName":\[0,"(?<author>[^"]+)"\][\s\S]{0,4000}?"slug":\[0,"(?<slug>[^"]+)"',
    'Singleline'
  )

  foreach ($match in $matches) {
    if ($match.Groups["slug"].Value -eq $slug -and $match.Groups["author"].Value) {
      return [System.Net.WebUtility]::HtmlDecode($match.Groups["author"].Value)
    }
  }

  return ""
}

function Get-AuthorData {
  param(
    $schema,
    [string]$content,
    [string]$slug
  )

  $pageAuthorName = Get-AuthorNameFromPageData -content $content -slug $slug
  if ($pageAuthorName) {
    return [PSCustomObject]@{
      Type = "Person"
      Name = $pageAuthorName
    }
  }

  $author = $schema.author
  if ($null -eq $author) {
    return [PSCustomObject]@{
      Type = "Organization"
      Name = "Eco Balcon"
    }
  }

  if ($author -is [System.Array] -and $author.Count -gt 0) {
    $author = $author[0]
  }

  $authorType = if ($author.'@type') { [string]$author.'@type' } else { "Organization" }
  $authorName = if ($author.name) { [System.Net.WebUtility]::HtmlDecode([string]$author.name) } else { "Eco Balcon" }

  return [PSCustomObject]@{
    Type = $authorType
    Name = $authorName
  }
}

function Get-ArticleSources {
  $ignoreFiles = @("index.html", "articles.html", "galerie.html")
  $articleSources = New-Object System.Collections.Generic.List[object]

  foreach ($file in Get-ChildItem -Path $rawDir -File | Sort-Object Name) {
    if ($ignoreFiles -contains $file.Name) { continue }

    $content = Get-Content -Raw -Encoding UTF8 $file.FullName
    $schema = Get-SchemaData $content
    if ($schema.'@type' -ne 'Article') { continue }

    if ($schema.url -notmatch '^https://ecobalcon\.com/(?<slug>[^/?#]+)') {
      throw "Impossible de determiner le slug pour $($file.Name)."
    }

    $slug = $matches["slug"]
    $date = if ($schema.datePublished) { [DateTime]::Parse($schema.datePublished) } else { [DateTime]::MinValue }
    $authorData = Get-AuthorData -schema $schema -content $content -slug $slug
    $heroCaption = Get-HeroCaption $content
    $imageRemoteUrl = [string]$schema.image
    $imageFileName = Get-ImageFileName -url $imageRemoteUrl -slug $slug
    $category = if ($schema.articleSection -and $schema.articleSection.Count -gt 0) {
      [System.Net.WebUtility]::HtmlDecode($schema.articleSection[0])
    } else {
      "Article"
    }

    $articleSources.Add([PSCustomObject]@{
        SourcePath = $file.FullName
        SourceName = $file.Name
        Slug = $slug
        OutputName = "$slug.html"
        Title = [System.Net.WebUtility]::HtmlDecode($schema.name)
        Description = [System.Net.WebUtility]::HtmlDecode($schema.description)
        ImageRemoteUrl = $imageRemoteUrl
        ImageFileName = $imageFileName
        ImageCanonicalUrl = Get-ImageCanonicalUrl $imageFileName
        ImageAlt = if ($heroCaption) { $heroCaption } else { [System.Net.WebUtility]::HtmlDecode($schema.description) }
        DatePublished = [string]$schema.datePublished
        DateModified = if ($schema.dateModified) { [string]$schema.dateModified } else { [string]$schema.datePublished }
        TimeRequired = [string]$schema.timeRequired
        AuthorName = $authorData.Name
        AuthorType = $authorData.Type
        Category = $category
        DateSort = $date
      })
  }

  return $articleSources | Sort-Object `
    @{ Expression = "DateSort"; Descending = $true }, `
    @{ Expression = "Title"; Descending = $false }
}

$articles = @(Get-ArticleSources)
$slugMap = @{}
foreach ($article in $articles) {
  $slugMap[$article.Slug] = $article.OutputName
}

Ensure-ArticleImages $articles

function Resolve-Link {
  param([string]$url)

  if ($url -match '^https://ecobalcon\.com/([^/?#]+)') {
    $slug = $matches[1]
    if ($slugMap.ContainsKey($slug)) {
      return $slugMap[$slug]
    }
  }

  if ($url -match '^/([^/?#]+)') {
    $slug = $matches[1]
    if ($slugMap.ContainsKey($slug)) {
      return $slugMap[$slug]
    }
  }

  return $url
}

function New-AnchorHtml {
  param(
    [string]$url,
    [string]$text
  )

  if ([string]::IsNullOrWhiteSpace($text)) {
    $text = $url
  }

  $safeText = HtmlEscape $text

  if ($url -like "*.html") {
    return "<a href=`"$url`">$safeText</a>"
  }

  if ($url -match '^https?://(www\.)?amzn\.to/' -or $url -match '^https?://(www\.)?amazon\.') {
    return "<a href=`"$url`" target=`"_blank`" rel=`"nofollow sponsored noopener noreferrer`">$safeText</a>"
  }

  if ($url -match '^https?://') {
    return "<a href=`"$url`" target=`"_blank`" rel=`"noopener noreferrer`">$safeText</a>"
  }

  return "<a href=`"$url`">$safeText</a>"
}

function Sanitize-InlineHtml {
  param([string]$html)

  if ([string]::IsNullOrWhiteSpace($html)) { return "" }

  $anchorMap = @{}
  $working = $html

  $working = [regex]::Replace($working, '(?is)<a\b[^>]*href=(["'']?)(?<url>[^"''\s>]+)\1[^>]*>(?<text>.*?)</a>', {
      param($m)
      $placeholder = "__ANCHOR_{0}__" -f ([guid]::NewGuid().ToString("N"))
      $url = Resolve-Link ([System.Net.WebUtility]::HtmlDecode($m.Groups["url"].Value))
      $text = [regex]::Replace($m.Groups["text"].Value, '(?is)<[^>]+>', '')
      $text = [System.Net.WebUtility]::HtmlDecode($text).Trim()
      $anchorMap[$placeholder] = New-AnchorHtml -url $url -text $text
      return $placeholder
    })

  $working = [regex]::Replace($working, '(?i)<br\s*/?>', '__BR__')
  $working = [regex]::Replace($working, '(?is)</?(strong|em|u|span)[^>]*>', '')
  $working = [regex]::Replace($working, '(?is)<[^>]+>', '')
  $working = [System.Net.WebUtility]::HtmlDecode($working)
  $working = $working -replace '\s*__BR__\s*', '__BR__'
  $working = $working.Trim()
  $working = $working -replace '__BR__', '<br>'

  foreach ($key in $anchorMap.Keys) {
    $working = $working.Replace($key, $anchorMap[$key])
  }

  return $working.Trim()
}

function Get-BodyBlocks {
  param([string]$content)

  $startMatch = [regex]::Match($content, '<h1\b[^>]*dir=(?:"auto"|auto)[^>]*>', 'IgnoreCase')
  if (-not $startMatch.Success) {
    throw "Debut d'article introuvable."
  }

  $start = $startMatch.Index
  $end = $content.IndexOf('</section><section id=zSiG-O', $start)
  if ($end -lt 0) {
    throw "Segment article introuvable."
  }

  $segment = $content.Substring($start, $end - $start)
  $pattern = '(?s)<h(?<level>[1-3])[^>]*>(?<heading>.*?)</h\k<level>>|<li[^>]*>\s*<p[^>]*class=body[^>]*>(?<li>.*?)(?=</p>|<p[^>]*class=body[^>]*>\s*</p>|</li>)|<p[^>]*class=body[^>]*>(?<p>.*?)(?=<p[^>]*class=body|<h[1-3]|<ul|<ol|<li|</section>|</div>)'
  return [regex]::Matches($segment, $pattern)
}

function Build-ArticleBody {
  param([string]$content)

  $matches = Get-BodyBlocks $content
  $builder = New-Object System.Text.StringBuilder
  $listOpen = $false
  $seenH1 = $false

  foreach ($m in $matches) {
    if ($m.Groups["heading"].Success -and $m.Groups["heading"].Value) {
      if ($listOpen) {
        [void]$builder.AppendLine("            </ul>")
        $listOpen = $false
      }

      $level = [int]$m.Groups["level"].Value
      $heading = Sanitize-InlineHtml $m.Groups["heading"].Value
      if (-not $heading) { continue }

      if ($level -eq 1) {
        if (-not $seenH1) {
          $seenH1 = $true
        }
        continue
      }

      [void]$builder.AppendLine("            <h$level>$heading</h$level>")
      continue
    }

    if ($m.Groups["li"].Success -and $m.Groups["li"].Value) {
      $item = Sanitize-InlineHtml $m.Groups["li"].Value
      if (-not $item) { continue }

      if (-not $listOpen) {
        [void]$builder.AppendLine("            <ul>")
        $listOpen = $true
      }

      [void]$builder.AppendLine("              <li>$item</li>")
      continue
    }

    if ($m.Groups["p"].Success -and $m.Groups["p"].Value) {
      if ($listOpen) {
        [void]$builder.AppendLine("            </ul>")
        $listOpen = $false
      }

      $paragraph = Sanitize-InlineHtml $m.Groups["p"].Value
      if (-not $paragraph) { continue }
      [void]$builder.AppendLine("            <p>$paragraph</p>")
    }
  }

  if ($listOpen) {
    [void]$builder.AppendLine("            </ul>")
  }

  return ($builder.ToString().TrimEnd() -replace '(?s)<a href="(?<url>[^"]+)"(?<attrs>[^>]*)>(?<text>[^<]+)</a>\s*<a href="\k<url>"[^>]*>\k<url></a>', '<a href="${url}"${attrs}>${text}</a> ')
}

function Build-ArticleHtml {
  param(
    [pscustomobject]$article,
    [object[]]$allArticles
  )

  $content = Get-Content -Raw -Encoding UTF8 $article.SourcePath
  $heroCaption = if ($article.ImageAlt) { $article.ImageAlt } else { Get-HeroCaption $content }
  $bodyHtml = Build-ArticleBody $content
  $dateText = Convert-IsoDateToFrench $article.DatePublished
  $timeText = Convert-TimeRequired $article.TimeRequired
  $canonicalUrl = "$siteUrl/articles/$($article.OutputName)"
  $heroImageSrc = Get-ImagePagePath -fileName $article.ImageFileName -pagePrefix "../images/articles/"
  $relatedArticles = @(Get-RelatedArticles -article $article -allArticles $allArticles -count 3)

  $jsonLdObject = [ordered]@{
    "@context" = "https://schema.org"
    "@type" = "BlogPosting"
    headline = $article.Title
    description = $article.Description
    url = $canonicalUrl
    mainEntityOfPage = $canonicalUrl
    image = @($article.ImageCanonicalUrl)
    datePublished = $article.DatePublished
    dateModified = $article.DateModified
    articleSection = $article.Category
    inLanguage = "fr"
    author = [ordered]@{
      "@type" = $article.AuthorType
      name = $article.AuthorName
    }
    publisher = [ordered]@{
      "@type" = "Organization"
      name = "EcoBalcon"
      logo = [ordered]@{
        "@type" = "ImageObject"
        url = "$siteUrl/images/logo-site.png"
      }
    }
  }
  $jsonLd = $jsonLdObject | ConvertTo-Json -Depth 6 -Compress

  $metaParts = @("<span>Par $(HtmlEscape $article.AuthorName)</span>")
  if ($dateText) { $metaParts += "<span>&bull;</span><span>$dateText</span>" }
  if ($timeText) { $metaParts += "<span>&bull;</span><span>$timeText</span>" }
  $metaHtml = ($metaParts -join "`n            ")

  $sidebarItems = @()
  if ($article.AuthorName) { $sidebarItems += "                <li><strong>Auteur :</strong> $(HtmlEscape $article.AuthorName)</li>" }
  if ($article.Category) { $sidebarItems += "                <li><strong>Th&egrave;me :</strong> $(HtmlEscape $article.Category)</li>" }
  if ($timeText) { $sidebarItems += "                <li><strong>Lecture :</strong> $(HtmlEscape $timeText)</li>" }
  if ($dateText) { $sidebarItems += "                <li><strong>Publication :</strong> $(HtmlEscape $dateText)</li>" }
  $sidebarHtml = ($sidebarItems -join "`n")

  $heroTitle = if ($heroCaption) { $heroCaption } else { $article.Title }
  $relatedCardsHtml = if ($relatedArticles.Count -gt 0) {
    (($relatedArticles | ForEach-Object {
          Build-ArticleCardHtml -article $_ -hrefPrefix "" -imagePrefix "../images/articles/" -extraClass " related-card"
        }) -join "`n")
  } else { "" }
  $relatedSection = if ($relatedCardsHtml) {
@"
        <section class="related-section" aria-labelledby="related-articles-heading">
          <div class="section-heading section-heading-compact">
            <div>
              <h2 id="related-articles-heading">A lire aussi</h2>
              <p>D'autres articles proches pour continuer naturellement ta lecture.</p>
            </div>
          </div>
          <div class="cards cards-related">
$relatedCardsHtml
          </div>
        </section>
"@
  } else { "" }

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(HtmlEscape $article.Title) | EcoBalcon</title>
  <meta name="description" content="$(HtmlEscape $article.Description)">
  <meta name="robots" content="index,follow,max-image-preview:large">
  <link rel="canonical" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="article">
  <meta property="og:title" content="$(HtmlEscape $article.Title) | EcoBalcon">
  <meta property="og:description" content="$(HtmlEscape $article.Description)">
  <meta property="og:url" content="$canonicalUrl">
  <meta property="og:image" content="$($article.ImageCanonicalUrl)">
  <meta property="og:image:alt" content="$(HtmlEscape $heroCaption)">
  <meta property="article:published_time" content="$($article.DatePublished)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="$(HtmlEscape $article.Title) | EcoBalcon">
  <meta name="twitter:description" content="$(HtmlEscape $article.Description)">
  <meta name="twitter:image" content="$($article.ImageCanonicalUrl)">
  <meta name="twitter:image:alt" content="$(HtmlEscape $heroCaption)">
  <script type="application/ld+json">$jsonLd</script>
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="stylesheet" href="../css/style.css">
</head>
<body>
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../index.html">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo EcoBalcon">
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../index.html">Accueil</a>
            <a href="index.html" aria-current="page">Articles</a>
            <a href="../galerie.html">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/" target="_blank" rel="noopener noreferrer" aria-label="X">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M4 4l16 16"></path>
                <path d="M20 4L4 20"></path>
              </svg>
            </a>
          </div>
        </div>
      </div>
    </header>

    <main class="article-layout">
      <div class="article-shell">
        <header class="article-header">
          <span class="eyebrow">$(HtmlEscape $article.Category)</span>
          <h1 class="article-title">$(HtmlEscape $article.Title)</h1>
          <div class="article-meta">
            $metaHtml
          </div>
          <p class="article-intro">$(HtmlEscape $article.Description)</p>
        </header>

        <figure class="hero-image">
          <img src="$heroImageSrc" alt="$(HtmlEscape $heroCaption)" title="$(HtmlEscape $heroTitle)" loading="eager" decoding="async" fetchpriority="high">
        </figure>

        <div class="article-grid">
          <article class="article-prose">
$bodyHtml
          </article>

          <aside class="sidebar-stack">
            <div class="checklist article-note">
              <h3>Rep&egrave;res</h3>
              <ul class="article-list">
$sidebarHtml
              </ul>
            </div>

            <div class="checklist article-links">
              <h3>Continuer</h3>
              <ul class="article-list">
                <li><a href="index.html">Retour &agrave; la liste des articles</a></li>
                <li><a href="../index.html">Retour &agrave; l'accueil</a></li>
              </ul>
            </div>
          </aside>
        </div>
$relatedSection
      </div>
    </main>

    <footer class="footer">
      <div class="footer-inner">
        <div>EcoBalcon</div>
        <div><a class="muted-link" href="index.html">Retour &agrave; la liste</a></div>
      </div>
    </footer>
  </div>
</body>
</html>
"@
}

function Build-ArticleCardHtml {
  param(
    [pscustomobject]$article,
    [string]$hrefPrefix,
    [string]$imagePrefix,
    [string]$extraClass = ""
  )

  $category = if ($article.Category) { $article.Category } else { "Article" }
  $summary = Get-CardExcerpt $article.Description
  $href = "$hrefPrefix$($article.OutputName)"
  $imageSrc = Get-ImagePagePath -fileName $article.ImageFileName -pagePrefix $imagePrefix
  $className = "article-card$extraClass"

  return @"
          <article class="$className">
            <img src="$imageSrc" alt="$(HtmlEscape $article.ImageAlt)" title="$(HtmlEscape $article.ImageAlt)" loading="lazy" decoding="async">
            <div class="article-card-body">
              <div class="pill-row"><span class="pill">$(HtmlEscape $category)</span></div>
              <h3><a href="$href">$(HtmlEscape $article.Title)</a></h3>
              <p>$(HtmlEscape $summary)</p>
            </div>
          </article>
"@
}

function Build-HomeHtml {
  param([object[]]$allArticles)

  $featured = @($allArticles | Select-Object -First 6)
  $cardsHtml = (($featured | ForEach-Object { Build-ArticleCardHtml -article $_ -hrefPrefix "articles/" -imagePrefix "images/articles/" }) -join "`n")
  $count = $allArticles.Count
  $featuredArticle = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "jardinage-en-lasagnes-sur-balcon",
    "jardiner-sur-un-balcon",
    "jardin-sur-balcon-astuces"
  ) -fallbackIndex 0
  $featuredImage = if ($featuredArticle) { $featuredArticle.ImageCanonicalUrl } else { "" }
  $featuredImageSrc = if ($featuredArticle) { Get-ImagePagePath -fileName $featuredArticle.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $featuredTitle = if ($featuredArticle) { $featuredArticle.Title } else { "Jardinage urbain sur balcon" }
  $featuredImageAlt = if ($featuredArticle) { $featuredArticle.ImageAlt } else { "Balcon potager et jardinage urbain" }
  $heroSecondary = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "plantes-qui-survivent-a-la-canicule",
    "reduction-consommation-eau-balcon",
    "guide-tomates-sur-son-balcon"
  ) -fallbackIndex 1
  $homeStats = @(
    [PSCustomObject]@{ Value = "$count"; Label = "guides pratiques" },
    [PSCustomObject]@{ Value = "3"; Label = "auteurs" },
    [PSCustomObject]@{ Value = "petits"; Label = "espaces d'abord" }
  )
  $statsHtml = (($homeStats | ForEach-Object {
@"
            <div class="mini-stat">
              <strong>$($_.Value)</strong>
              <span>$($_.Label)</span>
            </div>
"@
      }) -join "`n")
  $startBlocks = @(
    [PSCustomObject]@{
      Label = "Débuter"
      Title = "Poser les bonnes bases"
      Copy = "Un point de départ simple pour installer un balcon agréable et éviter les erreurs classiques."
      Article = (Get-PreferredArticle -allArticles $allArticles -preferredSlugs @("jardin-sur-balcon-astuces", "jardiner-sur-un-balcon") -fallbackIndex 0)
    },
    [PSCustomObject]@{
      Label = "Planter"
      Title = "Choisir des cultures faciles"
      Copy = "Des fiches pratiques pour cultiver sur balcon sans se noyer dans la technique."
      Article = (Get-PreferredArticle -allArticles $allArticles -preferredSlugs @("guide-tomates-sur-son-balcon", "guide-laitues-sur-son-balcon", "guide-fraises-sur-son-balcon") -fallbackIndex 2)
    },
    [PSCustomObject]@{
      Label = "Préserver"
      Title = "Garder un balcon écolo"
      Copy = "Eau, paillage, récupération et gestes durables pour un entretien plus serein."
      Article = (Get-PreferredArticle -allArticles $allArticles -preferredSlugs @("reduction-consommation-eau-balcon", "recuperer-eau-de-pluie-balcon", "paillage-sur-balcon-ecolo") -fallbackIndex 3)
    }
  )
  $startHtml = (($startBlocks | ForEach-Object {
      if (-not $_.Article) { return }
      $href = "articles/$($_.Article.OutputName)"
@"
          <article class="home-path-card">
            <span class="eyebrow">$($_.Label)</span>
            <h3><a href="$href">$(HtmlEscape $_.Title)</a></h3>
            <p>$(HtmlEscape $_.Copy)</p>
            <a class="text-link" href="$href">Lire pour commencer</a>
          </article>
"@
    }) -join "`n")
  $themeHtml = @"
          <article class="theme-card">
            <span class="eyebrow">Potager</span>
            <h3><a href="articles/guide-tomates-sur-son-balcon.html">Cultiver m&ecirc;me avec peu de place</a></h3>
            <p>Tomates, laitues, fraises, aromatiques et petits fruits pour un balcon gourmand.</p>
          </article>
          <article class="theme-card">
            <span class="eyebrow">Chaleur</span>
            <h3><a href="articles/plantes-qui-survivent-a-la-canicule.html">Mieux vivre le plein soleil</a></h3>
            <p>Des plantes plus r&eacute;sistantes et des gestes simples pour traverser l'&eacute;t&eacute; avec moins de stress.</p>
          </article>
          <article class="theme-card">
            <span class="eyebrow">Fiches</span>
            <h3><a href="articles/index.html">Retrouver des guides concrets</a></h3>
            <p>Chaque culture est pr&eacute;sent&eacute;e avec l'essentiel : pot, exposition, arrosage, entretien et r&eacute;colte.</p>
          </article>
          <article class="theme-card">
            <span class="eyebrow">Balcon &eacute;colo</span>
            <h3><a href="articles/reduction-consommation-eau-balcon.html">&Eacute;conomiser l'eau au quotidien</a></h3>
            <p>Paillage, eau de pluie, eau de cuisson et compost pour un jardinage urbain plus durable.</p>
          </article>
"@
  $editorialFeature = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "plantes-qui-survivent-a-la-canicule",
    "potager-balcon-eau-de-cuisson",
    "jardinage-en-lasagnes-sur-balcon"
  ) -fallbackIndex 0
  $editorialFeatureHref = if ($editorialFeature) { "articles/$($editorialFeature.OutputName)" } else { "articles/index.html" }
  $editorialFeatureImageSrc = if ($editorialFeature) { Get-ImagePagePath -fileName $editorialFeature.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $editorialList = @(
    $allArticles |
      Where-Object { $null -eq $editorialFeature -or $_.Slug -ne $editorialFeature.Slug } |
      Select-Object -First 3
  )
  $editorialListHtml = (($editorialList | ForEach-Object {
      $href = "articles/$($_.OutputName)"
@"
            <article class="editorial-item">
              <span class="pill">$(HtmlEscape $_.Category)</span>
              <h3><a href="$href">$(HtmlEscape $_.Title)</a></h3>
              <p>$(HtmlEscape (Get-CardExcerpt $_.Description 118))</p>
            </article>
"@
    }) -join "`n")
  $jsonLd = ([ordered]@{
      "@context" = "https://schema.org"
      "@type" = "WebSite"
      name = "EcoBalcon"
      url = "$siteUrl/"
      inLanguage = "fr"
      description = "EcoBalcon partage des conseils pratiques pour jardiner sur balcon, economiser l'eau, choisir les bonnes plantes et reussir un petit potager urbain."
      publisher = [ordered]@{
        "@type" = "Organization"
        name = "EcoBalcon"
        logo = [ordered]@{
          "@type" = "ImageObject"
          url = "$siteUrl/images/logo-site.png"
        }
      }
    } | ConvertTo-Json -Depth 6 -Compress)

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EcoBalcon | Jardinage urbain sur balcon</title>
  <meta name="description" content="EcoBalcon partage des conseils pratiques pour jardiner sur balcon, economiser l'eau, choisir les bonnes plantes et reussir un petit potager urbain.">
  <meta name="robots" content="index,follow,max-image-preview:large">
  <link rel="canonical" href="$siteUrl/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="website">
  <meta property="og:title" content="EcoBalcon | Jardinage urbain sur balcon">
  <meta property="og:description" content="EcoBalcon partage des conseils pratiques pour jardiner sur balcon, economiser l'eau, choisir les bonnes plantes et reussir un petit potager urbain.">
  <meta property="og:url" content="$siteUrl/">
  <meta property="og:image" content="$featuredImage">
  <meta property="og:image:alt" content="$(HtmlEscape $featuredImageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="EcoBalcon | Jardinage urbain sur balcon">
  <meta name="twitter:description" content="EcoBalcon partage des conseils pratiques pour jardiner sur balcon, economiser l'eau, choisir les bonnes plantes et reussir un petit potager urbain.">
  <meta name="twitter:image" content="$featuredImage">
  <meta name="twitter:image:alt" content="$(HtmlEscape $featuredImageAlt)">
  <script type="application/ld+json">$jsonLd</script>
  <link rel="icon" type="image/png" sizes="32x32" href="images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="images/apple-touch-icon.png">
  <link rel="stylesheet" href="css/style.css">
</head>
<body class="home-page">
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="index.html">
          <span class="brand-mark">
            <img class="brand-logo" src="images/logo-site.png" alt="Logo EcoBalcon">
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="index.html" aria-current="page">Accueil</a>
            <a href="articles/index.html">Articles</a>
            <a href="galerie.html">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/" target="_blank" rel="noopener noreferrer" aria-label="X">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M4 4l16 16"></path>
                <path d="M20 4L4 20"></path>
              </svg>
            </a>
          </div>
        </div>
      </div>
    </header>

    <main>
      <section class="hero hero-home">
        <div class="section-inner hero-grid">
          <div class="hero-copy">
            <span class="eyebrow">Jardinage urbain</span>
            <h1>Des conseils simples pour faire d'un petit balcon un coin vivant et g&eacute;n&eacute;reux.</h1>
            <p>
              EcoBalcon rassemble des rep&egrave;res concrets pour jardiner en ville sans pression :
              choisir les bonnes plantes, mieux vivre les fortes chaleurs, gagner en autonomie
              et cultiver un espace ext&eacute;rieur beau, simple et nourricier.
            </p>
            <div class="meta-row hero-badges">
              <span class="status status-ready">Potager urbain</span>
              <span class="status status-ready">Plantes r&eacute;sistantes</span>
              <span class="status status-ready">Gestes &eacute;colo</span>
            </div>
            <div class="hero-actions">
              <a class="button" href="articles/index.html">Voir tous les articles</a>
              <a class="button-secondary" href="articles/$($featuredArticle.OutputName)">Commencer en douceur</a>
            </div>
            <div class="hero-stat-grid">
$statsHtml
            </div>
          </div>

          <aside class="hero-panel" aria-label="Par o&ugrave; commencer">
            <figure class="home-visual">
              <img src="$featuredImageSrc" alt="$(HtmlEscape $featuredImageAlt)" title="$(HtmlEscape $featuredImageAlt)" loading="eager" decoding="async" fetchpriority="high">
            </figure>
            <div class="home-note">
              <span class="eyebrow">&Agrave; la une</span>
              <strong>$(HtmlEscape $featuredTitle)</strong>
              <p>$(HtmlEscape (Get-CardExcerpt $featuredArticle.Description 140))</p>
              <a class="text-link" href="articles/$($featuredArticle.OutputName)">Lire ce guide</a>
            </div>
            <div class="home-note home-note-soft">
              <span class="eyebrow">En ce moment</span>
              <strong>$(HtmlEscape $heroSecondary.Title)</strong>
              <p>$(HtmlEscape (Get-CardExcerpt $heroSecondary.Description 110))</p>
            </div>
          </aside>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading">
            <div>
              <h2>Commencer ici</h2>
              <p>Trois portes d'entr&eacute;e simples selon ton envie du moment.</p>
            </div>
          </div>
          <div class="home-path-grid">
$startHtml
          </div>
        </div>
      </section>

      <section class="section section-soft">
        <div class="section-inner">
          <div class="section-heading">
            <div>
              <h2>Explorer par th&egrave;me</h2>
              <p>Des rep&egrave;res visuels pour trouver rapidement le sujet qui t'aide vraiment.</p>
            </div>
          </div>
          <div class="theme-grid">
$themeHtml
          </div>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading">
            <div>
              <h2>&Agrave; lire cette semaine</h2>
              <p>Une entr&eacute;e plus &eacute;ditoriale pour d&eacute;couvrir les contenus sans scroller toute la biblioth&egrave;que.</p>
            </div>
          </div>
          <div class="editorial-grid">
            <article class="editorial-feature">
              <img src="$editorialFeatureImageSrc" alt="$(HtmlEscape $editorialFeature.ImageAlt)" title="$(HtmlEscape $editorialFeature.ImageAlt)" loading="lazy" decoding="async">
              <div class="editorial-feature-body">
                <span class="pill">$(HtmlEscape $editorialFeature.Category)</span>
                <h3><a href="$editorialFeatureHref">$(HtmlEscape $editorialFeature.Title)</a></h3>
                <p>$(HtmlEscape (Get-CardExcerpt $editorialFeature.Description 172))</p>
                <a class="text-link" href="$editorialFeatureHref">Ouvrir l'article</a>
              </div>
            </article>
            <div class="editorial-list">
$editorialListHtml
            </div>
          </div>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading">
            <div>
              <h2>Articles &agrave; d&eacute;couvrir</h2>
              <p>Une s&eacute;lection des guides les plus r&eacute;cents pour lancer ou am&eacute;liorer ton balcon au fil des saisons.</p>
            </div>
          </div>

          <div class="cards">
$cardsHtml
          </div>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="cta-strip">
            <div>
              <h2 class="page-title">Explorer les $count articles</h2>
              <p class="page-intro">
                Potager, chaleur, &eacute;conomie d'eau, biodiversit&eacute;, fleurs utiles et fiches culture :
                tout est regroup&eacute; dans une page unique avec recherche int&eacute;gr&eacute;e.
              </p>
            </div>
            <a class="button" href="articles/index.html">Ouvrir la rubrique articles</a>
          </div>
        </div>
      </section>
    </main>

    <footer class="footer">
      <div class="footer-inner">
        <div>EcoBalcon</div>
        <div><a class="muted-link" href="articles/index.html">Voir tous les articles</a></div>
      </div>
    </footer>
  </div>
</body>
</html>
"@
}

function Build-ArticlesIndexHtml {
  param([object[]]$allArticles)

  $cardsHtml = (($allArticles | ForEach-Object { Build-ArticleCardHtml -article $_ -hrefPrefix "" -imagePrefix "../images/articles/" }) -join "`n")
  $count = $allArticles.Count
  $heroImage = if ($allArticles.Count -gt 0) { $allArticles[0].ImageCanonicalUrl } else { "" }
  $heroImageAlt = if ($allArticles.Count -gt 0) { $allArticles[0].ImageAlt } else { "Articles EcoBalcon autour du jardinage sur balcon" }
  $jsonLd = ([ordered]@{
      "@context" = "https://schema.org"
      "@type" = "CollectionPage"
      name = "Articles | EcoBalcon"
      url = "$siteUrl/articles/"
      inLanguage = "fr"
      description = "Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes ecolo."
      isPartOf = [ordered]@{
        "@type" = "WebSite"
        name = "EcoBalcon"
        url = "$siteUrl/"
      }
    } | ConvertTo-Json -Depth 6 -Compress)

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Articles | EcoBalcon</title>
  <meta name="description" content="Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes ecolo.">
  <meta name="robots" content="index,follow,max-image-preview:large">
  <link rel="canonical" href="$siteUrl/articles/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Articles | EcoBalcon">
  <meta property="og:description" content="Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes ecolo.">
  <meta property="og:url" content="$siteUrl/articles/">
  <meta property="og:image" content="$heroImage">
  <meta property="og:image:alt" content="$(HtmlEscape $heroImageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Articles | EcoBalcon">
  <meta name="twitter:description" content="Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes ecolo.">
  <meta name="twitter:image" content="$heroImage">
  <meta name="twitter:image:alt" content="$(HtmlEscape $heroImageAlt)">
  <script type="application/ld+json">$jsonLd</script>
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="stylesheet" href="../css/style.css">
</head>
<body>
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../index.html">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo EcoBalcon">
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../index.html">Accueil</a>
            <a href="index.html" aria-current="page">Articles</a>
            <a href="../galerie.html">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/" target="_blank" rel="noopener noreferrer" aria-label="X">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M4 4l16 16"></path>
                <path d="M20 4L4 20"></path>
              </svg>
            </a>
          </div>
        </div>
      </div>
    </header>

    <main class="section">
      <div class="section-inner">
        <div class="page-hero">
          <div class="page-hero-copy">
            <span class="eyebrow">Articles</span>
            <h1 class="page-title">Conseils et guides pour jardiner sur balcon</h1>
            <p class="page-intro">
              Une biblioth&egrave;que de $count contenus pratiques autour du potager urbain, des plantes adapt&eacute;es &agrave; la ville,
              des &eacute;conomies d'eau et des m&eacute;thodes simples pour mieux cultiver sur un petit espace.
            </p>
          </div>

          <section class="search-panel search-panel-compact" aria-label="Recherche d'articles">
            <label class="search-label sr-only" for="article-search">Rechercher un article</label>
            <input
              class="search-input"
              id="article-search"
              type="search"
              name="search"
              placeholder="Rechercher un article"
              autocomplete="off">
          </section>
        </div>

        <p class="search-empty" id="search-empty" hidden>Aucun article ne correspond &agrave; cette recherche.</p>

        <div class="cards" id="article-list">
$cardsHtml
        </div>
      </div>
    </main>

    <footer class="footer">
      <div class="footer-inner">
        <div>EcoBalcon</div>
        <div><a class="muted-link" href="../index.html">Retour &agrave; l'accueil</a></div>
      </div>
    </footer>
  </div>
  <script>
    const searchInput = document.getElementById("article-search");
    const articleCards = Array.from(document.querySelectorAll("#article-list .article-card"));
    const emptyState = document.getElementById("search-empty");

    const normalizeText = (value) =>
      value
        .toLowerCase()
        .normalize("NFD")
        .replace(/[\u0300-\u036f]/g, "");

    const filterArticles = () => {
      const query = normalizeText(searchInput.value.trim());
      let visibleCount = 0;

      articleCards.forEach((card) => {
        const searchableText = normalizeText(card.textContent);
        const matches = query === "" || searchableText.includes(query);
        card.hidden = !matches;

        if (matches) {
          visibleCount += 1;
        }
      });

      emptyState.hidden = visibleCount !== 0;
    };

    searchInput.addEventListener("input", filterArticles);
  </script>
</body>
</html>
"@
}

function Get-RelatedArticles {
  param(
    [pscustomobject]$article,
    [object[]]$allArticles,
    [int]$count = 3
  )

  $stopWords = @(
    "avec", "dans", "pour", "comment", "guide", "balcon", "cultiver", "votre", "villes", "ville",
    "toute", "toutes", "faire", "plus", "moins", "tout", "bien", "entre", "sans", "cette", "votre",
    "leurs", "leurs", "leurs", "sont", "sur", "des", "les", "une", "vos", "son", "ses"
  )

  $termMatches = [regex]::Matches(
    ($article.Title + " " + $article.Description).ToLowerInvariant(),
    '\p{L}[\p{L}\p{N}-]{3,}'
  )
  $terms = @(
    $termMatches |
      ForEach-Object { $_.Value } |
      Where-Object { $stopWords -notcontains $_ } |
      Select-Object -Unique |
      Select-Object -First 8
  )

  $scored = foreach ($candidate in $allArticles) {
    if ($candidate.Slug -eq $article.Slug) { continue }

    $score = 0
    if ($candidate.Category -and $candidate.Category -eq $article.Category) { $score += 6 }
    if ($candidate.AuthorName -and $candidate.AuthorName -eq $article.AuthorName) { $score += 1 }

    $haystack = ($candidate.Title + " " + $candidate.Description).ToLowerInvariant()
    foreach ($term in $terms) {
      if ($haystack -match [regex]::Escape($term)) {
        $score += 1
      }
    }

    [PSCustomObject]@{
      Score = $score
      Article = $candidate
    }
  }

  $selected = @(
    $scored |
      Sort-Object `
        @{ Expression = "Score"; Descending = $true }, `
        @{ Expression = { $_.Article.DateSort }; Descending = $true }, `
        @{ Expression = { $_.Article.Title }; Descending = $false } |
      Select-Object -First $count
  )

  if ($selected.Count -lt $count) {
    $existing = @($selected | ForEach-Object { $_.Article.Slug })
    $fill = @(
      $allArticles |
        Where-Object { $_.Slug -ne $article.Slug -and $existing -notcontains $_.Slug } |
        Select-Object -First ($count - $selected.Count)
    )
    return @($selected | ForEach-Object { $_.Article }) + $fill
  }

  return @($selected | ForEach-Object { $_.Article })
}

function Get-PreferredArticle {
  param(
    [object[]]$allArticles,
    [string[]]$preferredSlugs,
    [int]$fallbackIndex = 0
  )

  foreach ($slug in $preferredSlugs) {
    $match = $allArticles | Where-Object { $_.Slug -eq $slug } | Select-Object -First 1
    if ($match) { return $match }
  }

  if ($allArticles.Count -gt $fallbackIndex) {
    return $allArticles[$fallbackIndex]
  }

  return $allArticles | Select-Object -First 1
}

function Build-SitemapXml {
  param([object[]]$allArticles)

  $today = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
  $entries = New-Object System.Collections.Generic.List[string]

  $entries.Add("<url><loc>$siteUrl/</loc><priority>1.0</priority><lastmod>$today</lastmod></url>")
  $entries.Add("<url><loc>$siteUrl/articles/</loc><priority>0.9</priority><lastmod>$today</lastmod></url>")
  if (Test-Path (Join-Path $root "galerie.html")) {
    $entries.Add("<url><loc>$siteUrl/galerie.html</loc><priority>0.5</priority><lastmod>$today</lastmod></url>")
  }

  foreach ($article in $allArticles) {
    $lastmod = if ($article.DateModified) { $article.DateModified } else { $article.DatePublished }
    $entries.Add("<url><loc>$siteUrl/articles/$($article.OutputName)</loc><priority>0.7</priority><lastmod>$lastmod</lastmod></url>")
  }

  $body = ($entries -join "`n")
  return "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`">`n$body`n</urlset>"
}

function Build-RobotsTxt {
  return @"
User-agent: *
Allow: /

Sitemap: $siteUrl/sitemap.xml
"@
}

foreach ($article in $articles) {
  $outPath = Join-Path $articlesDir $article.OutputName
  $html = Build-ArticleHtml -article $article -allArticles $articles
  Set-Content -Path $outPath -Value $html -Encoding UTF8
  Write-Output "Rebuilt $($article.OutputName)"
}

Set-Content -Path (Join-Path $articlesDir "index.html") -Value (Build-ArticlesIndexHtml $articles) -Encoding UTF8
Set-Content -Path (Join-Path $root "index.html") -Value (Build-HomeHtml $articles) -Encoding UTF8
Set-Content -Path (Join-Path $root "sitemap.xml") -Value (Build-SitemapXml $articles) -Encoding UTF8
Set-Content -Path (Join-Path $root "robots.txt") -Value (Build-RobotsTxt) -Encoding UTF8

Write-Output "Updated articles index, homepage, sitemap.xml and robots.txt"

