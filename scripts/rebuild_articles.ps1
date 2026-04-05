$ErrorActionPreference = "Stop"

# Safe by default: keep the current homepage unless the script is launched with -RebuildHome.
$RebuildHome = @($args | Where-Object { $_ -ieq "-RebuildHome" }).Count -gt 0

$root = Split-Path -Parent $PSScriptRoot
$rawDir = Join-Path $root "raw-singlefile"
$articlesDir = Join-Path $root "articles"
$imagesDir = Join-Path $root "images\articles"
$sourceStylesheetPath = Join-Path $root "css\style.css"
$minifiedStylesheetPath = Join-Path $root "css\style.min.css"
$rootStylesheetHref = "css/style.min.css"
$articleStylesheetHref = "../css/style.min.css"
$articleDetailStylesheetHref = "../../css/style.min.css"
$siteName = "HydroFacile"
$siteUrl = "https://hydrofacile.fr"
$siteTagline = "Hydroponie débutant en appartement."
$siteDescription = "HydroFacile aide à débuter en hydroponie en appartement avec des guides simples sur les systèmes, la lumière, les nutriments et les cultures faciles."
$siteLongDescription = "HydroFacile est un site sur l'hydroponie débutant en appartement : système hydroponique simple, cultures faciles, lumière, nutriments et potager intérieur propre."
$siteContactEmail = "ecobalcon21@gmail.com"
$siteContactFormAction = "https://formsubmit.co/$siteContactEmail"
$siteLogoPath = "images\logo-site.png"
$siteLogoUrl = "$siteUrl/images/logo-site.png"
$primaryArticleSlugs = @(
  "hydroponie-sans-pompe-appartement",
  "cultures-faciles-hydroponie-appartement",
  "lumiere-hydroponie-appartement",
  "nutriments-hydroponie-debutant",
  "laitue-hydroponique-appartement",
  "basilic-hydroponie-interieur",
  "nettoyer-systeme-hydroponique"
)
$articleOverrides = @{}
$articleOverridesPath = Join-Path $PSScriptRoot "article-overrides.ps1"

if (Test-Path $articleOverridesPath) {
  . $articleOverridesPath

  if (Get-Command Get-ArticleOverrides -ErrorAction SilentlyContinue) {
    $articleOverrides = Get-ArticleOverrides
  }
}

if ($null -eq $articleOverrides) {
  $articleOverrides = @{}
}

function Test-IsPrimaryArticle {
  param([string]$slug)

  return $primaryArticleSlugs -contains $slug
}

function HtmlEscape {
  param([string]$text)

  if ($null -eq $text) { return "" }
  return [System.Security.SecurityElement]::Escape([string]$text)
}

function Get-MinifiedCss {
  param([string]$css)

  if ([string]::IsNullOrWhiteSpace($css)) { return "" }

  $minified = [regex]::Replace($css, '/\*[\s\S]*?\*/', '')
  $minified = $minified -replace '\r?\n', ' '
  $minified = [regex]::Replace($minified, '\s+', ' ')
  $minified = [regex]::Replace($minified, '\s*([{}:;,])\s*', '$1')
  $minified = [regex]::Replace($minified, ';}', '}')

  return $minified.Trim()
}

function Write-MinifiedStylesheet {
  if (-not (Test-Path $sourceStylesheetPath)) { return }

  $sourceCss = Get-Content -Raw -Encoding UTF8 $sourceStylesheetPath
  $minifiedCss = Get-MinifiedCss $sourceCss
  Set-Content -Path $minifiedStylesheetPath -Value $minifiedCss -Encoding UTF8
}

function Get-TagManagerHeadHtml {
  return ""
}

function Get-TagManagerBodyHtml {
  return ""
}

function Escape-Xml {
  param([string]$text)

  if ($null -eq $text) { return "" }
  return [System.Security.SecurityElement]::Escape([string]$text)
}

function Convert-IsoDateToFrench {
  param([string]$iso)

  if ([string]::IsNullOrWhiteSpace($iso)) { return "" }

  $months = @(
    "", "janvier", "février", "mars", "avril", "mai", "juin",
    "juillet", "août", "septembre", "octobre", "novembre", "décembre"
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

function Get-ArticleLegacyFileName {
  param([pscustomobject]$article)

  return "$($article.Slug).html"
}

function Get-ArticlePrettyHref {
  param(
    [pscustomobject]$article,
    [string]$hrefPrefix = ""
  )

  return "$hrefPrefix$($article.Slug)/"
}

function Get-ArticleCanonicalUrl {
  param([pscustomobject]$article)

  return "$siteUrl/articles/$($article.Slug)/"
}

function Get-RedirectHtml {
  param(
    [string]$targetUrl,
    [string]$title = "Redirection | $siteName",
    [string]$description = "Cette page a changé d'adresse."
  )

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(HtmlEscape $title)</title>
  <meta name="robots" content="noindex,follow">
  <meta name="description" content="$(HtmlEscape $description)">
  <link rel="canonical" href="$targetUrl">
  <meta http-equiv="refresh" content="0; url=$targetUrl">
  <script>window.location.replace("$targetUrl");</script>
</head>
<body>
  <p>Redirection vers <a href="$targetUrl">$targetUrl</a>.</p>
</body>
</html>
"@
}

try {
  Add-Type -AssemblyName System.Drawing | Out-Null
} catch {
}

$imageDimensionCache = @{}

function Get-ImageDimensions {
  param([string]$path)

  if ([string]::IsNullOrWhiteSpace($path)) { return $null }

  $fullPath = [System.IO.Path]::GetFullPath($path)
  if ($imageDimensionCache.ContainsKey($fullPath)) {
    return $imageDimensionCache[$fullPath]
  }

  if (-not (Test-Path $fullPath)) {
    return $null
  }

  $extension = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()

  if ($extension -eq ".svg") {
    $svgContent = Get-Content -Raw -Encoding UTF8 $fullPath
    $viewBoxMatch = [regex]::Match($svgContent, 'viewBox="[^"]*\s(?<width>[\d.]+)\s(?<height>[\d.]+)"')
    $widthMatch = [regex]::Match($svgContent, 'width="(?<width>[\d.]+)"')
    $heightMatch = [regex]::Match($svgContent, 'height="(?<height>[\d.]+)"')

    $svgWidth = if ($widthMatch.Success) { [double]$widthMatch.Groups["width"].Value } elseif ($viewBoxMatch.Success) { [double]$viewBoxMatch.Groups["width"].Value } else { 0 }
    $svgHeight = if ($heightMatch.Success) { [double]$heightMatch.Groups["height"].Value } elseif ($viewBoxMatch.Success) { [double]$viewBoxMatch.Groups["height"].Value } else { 0 }

    if ($svgWidth -gt 0 -and $svgHeight -gt 0) {
      $dimensions = [PSCustomObject]@{
        Width = [int][Math]::Round($svgWidth)
        Height = [int][Math]::Round($svgHeight)
      }

      $imageDimensionCache[$fullPath] = $dimensions
      return $dimensions
    }
  }

  try {
    $image = [System.Drawing.Image]::FromFile($fullPath)
    try {
      $dimensions = [PSCustomObject]@{
        Width = $image.Width
        Height = $image.Height
      }
    } finally {
      $image.Dispose()
    }
  } catch {
    return $null
  }

  $imageDimensionCache[$fullPath] = $dimensions
  return $dimensions
}

function Get-ImageDimensionAttributes {
  param([string]$path)

  $dimensions = Get-ImageDimensions $path
  if ($null -eq $dimensions) { return "" }
  return " width=`"$($dimensions.Width)`" height=`"$($dimensions.Height)`""
}

function Get-ArticleImageDimensionAttributes {
  param([string]$fileName)

  if ([string]::IsNullOrWhiteSpace($fileName)) { return "" }
  return Get-ImageDimensionAttributes (Join-Path $imagesDir $fileName)
}

function Get-RootImageDimensionAttributes {
  param([string]$relativePath)

  if ([string]::IsNullOrWhiteSpace($relativePath)) { return "" }
  return Get-ImageDimensionAttributes (Join-Path $root $relativePath)
}

function Get-SiteFooterHtml {
  param([string]$pagePrefix = "")

  return @"
    <footer class="footer">
      <div class="footer-inner">
        <div class="footer-main">
          <div class="footer-brand">
            <strong>$siteName</strong>
            <p>Hydroponie débutant en appartement, culture propre et conseils faciles à suivre pour bien commencer.</p>
          </div>
        </div>
        <div class="footer-side">
          <strong>Explorer</strong>
          <ul class="footer-list">
            <li><a href="${pagePrefix}articles/">Guides hydroponie débutant</a></li>
            <li><a href="${pagePrefix}articles/hydroponie-sans-pompe-appartement/">Premier système sans pompe</a></li>
            <li><a href="${pagePrefix}contact/">Contacter HydroFacile</a></li>
          </ul>
        </div>
        <div class="footer-legal">&copy; 2026. Tous droits r&eacute;serv&eacute;s. <span class="footer-legal-sep">&bull;</span> <a href="${pagePrefix}politique-confidentialite/">Politique de confidentialité</a></div>
      </div>
    </footer>
"@
}

function Normalize-ArticleCategoryToken {
  param([string]$value)

  if ([string]::IsNullOrWhiteSpace($value)) { return "" }

  $normalized = $value.ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
  $builder = New-Object System.Text.StringBuilder

  foreach ($char in $normalized.ToCharArray()) {
    if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$builder.Append($char)
    }
  }

  return (($builder.ToString().Normalize([System.Text.NormalizationForm]::FormC) -replace '[^a-z0-9]+', ' ') -replace '\s+', ' ').Trim()
}

function Get-CanonicalArticleCategory {
  param(
    [string]$slug,
    [string]$rawCategory,
    [string]$title,
    [string]$description
  )

  $categoryBySlug = @{
    "hydroponie-sans-pompe-appartement" = "Matériel & systèmes"
    "cultures-faciles-hydroponie-appartement" = "Débuter"
    "lumiere-hydroponie-appartement" = "Matériel & systèmes"
    "nutriments-hydroponie-debutant" = "Routine & réglages"
    "laitue-hydroponique-appartement" = "Cultures faciles"
    "basilic-hydroponie-interieur" = "Cultures faciles"
    "nettoyer-systeme-hydroponique" = "Routine & réglages"
    "jardiner-sur-un-balcon" = "Débuter"
    "legumes-faciles-a-cultiver" = "Débuter"
    "le-materiel-essentiel-pour-commencer" = "Matériel & systèmes"
    "calendrier-du-jardin-de-balcon" = "Routine & réglages"
    "guide-laitues-sur-son-balcon" = "Cultures faciles"
    "guide-basilic-sur-son-balcon" = "Cultures faciles"
    "plantes-aromatiques-sur-balcon" = "Cultures faciles"
    "guide-tomates-sur-son-balcon" = "Cultures faciles"
    "guide-poivrons-sur-son-balcon" = "Fiches Techniques"
    "guide-epinards-sur-son-balcon" = "Fiches Techniques"
    "guide-fraises-sur-son-balcon" = "Fiches Techniques"
    "guide-radis-sur-son-balcon" = "Fiches Techniques"
    "tomates-cerises-balcon" = "Fiches Techniques"
    "potager-balcon-eau-de-cuisson" = "Plantes & semis"
    "pommes-de-terre-balcon" = "Plantes & semis"
    "petits-fruits-en-pot" = "Plantes & semis"
    "fleurs-comestibles-melliferes-balcon" = "Plantes & semis"
    "plantes-pour-un-balcon-plein-soleil" = "Plantes & semis"
    "balcon-a-lombre-plantes-et-culture" = "Plantes & semis"
    "balcon-durable-plantes" = "Plantes & semis"
    "balcon-pour-pollinisateurs" = "Plantes & semis"
    "jardinage-en-lasagnes-sur-balcon" = "Entretien & astuces"
    "plantes-qui-survivent-a-la-canicule" = "Entretien & astuces"
    "reduction-consommation-eau-balcon" = "Entretien & astuces"
    "insectes-utiles-sur-un-balcon" = "Entretien & astuces"
    "calendrier-lunaire-balcon" = "Entretien & astuces"
    "paillage-sur-balcon-ecolo" = "Entretien & astuces"
    "proteger-son-balcon-des-nuisibles-naturellement" = "Entretien & astuces"
    "utilisation-compost-sur-balcon" = "Entretien & astuces"
    "jardin-sur-balcon-astuces" = "Entretien & astuces"
    "erreurs-jardiner-sur-un-balcon" = "Entretien & astuces"
    "meilleures-plantes-grimpantes-en-ville" = "Aménagement du balcon"
    "recuperer-eau-de-pluie-balcon" = "Aménagement du balcon"
    "diy-pots-pour-le-balcon" = "Aménagement du balcon"
    "solutions-compostage-sur-balcon" = "Aménagement du balcon"
  }

  if ($categoryBySlug.ContainsKey($slug)) {
    return $categoryBySlug[$slug]
  }

  $normalizedCategory = Normalize-ArticleCategoryToken $rawCategory
  switch ($normalizedCategory) {
    "debuter" { return "Débuter" }
    "cultures faciles" { return "Cultures faciles" }
    "materiel systemes" { return "Matériel & systèmes" }
    "materiel et systemes" { return "Matériel & systèmes" }
    "routine reglages" { return "Routine & réglages" }
    "routine et reglages" { return "Routine & réglages" }
    "fiches techniques" { return "Fiches Techniques" }
    "plantes semis" { return "Plantes & semis" }
    "plantes et semis" { return "Plantes & semis" }
    "fruits" { return "Plantes & semis" }
    "fruit" { return "Plantes & semis" }
    "entretien astuces" { return "Entretien & astuces" }
    "entretien et astuces" { return "Entretien & astuces" }
    "amenagement du balcon" { return "Aménagement du balcon" }
    "amenagement balcon" { return "Aménagement du balcon" }
  }

  $haystack = Normalize-ArticleCategoryToken "$slug $title $description"

  if ($haystack -match 'hydropon|kratky|dwc|reservoir|nutriment|ph |ph$|laitue|basilic|aromatique|culture facile|tomate cerise') {
    if ($haystack -match 'materiel|systeme|reservoir|pompe|nutriment|ph metre') {
      return "Matériel & systèmes"
    }

    if ($haystack -match 'calendrier|routine|reglage|entretien|stabil') {
      return "Routine & réglages"
    }

    if ($haystack -match 'debut|commencer|premier|facile') {
      return "Débuter"
    }

    return "Cultures faciles"
  }

  if ($haystack -match 'grimp|intimite|treillis|diy|materiel|compostage|eau pluie|gouttiere|amenag') {
    return "Aménagement du balcon"
  }

  if ($haystack -match 'pollinis|mellifer|abeill|papillon|fruit|semis|plante|aromatique|legume|cultiver') {
    return "Plantes & semis"
  }

  if ($haystack -match 'arros|paillage|nuisible|compost|astuce|canicule|lunaire|entretien|erreur|eau') {
    return "Entretien & astuces"
  }

  return "Entretien & astuces"
}

$faqSchemaMap = @{
  "guide-tomates-sur-son-balcon" = @(
    [ordered]@{
      Question = "Quelle exposition faut-il pour cultiver des tomates sur un balcon ?"
      Answer = "Les tomates ont besoin de plein soleil, au moins 6 heures par jour. Une exposition sud convient bien, avec une protection contre le vent et un peu d'ombre aux heures les plus chaudes."
    },
    [ordered]@{
      Question = "Quel contenant choisir pour des tomates en pot ?"
      Answer = "Prevois un pot d'au moins 30 cm de profondeur et de largeur, assez stable, avec un bon drainage et une couche de billes d'argile ou de graviers au fond."
    },
    [ordered]@{
      Question = "Comment limiter les problemes courants sur les tomates ?"
      Answer = "Arrose regulierement sans mouiller le feuillage, paille le pot, installe un tuteur des la plantation et surveille rapidement les signes de carence, de necrose apicale, de pucerons ou de mildiou."
    }
  )
  "jardinage-en-lasagnes-sur-balcon" = @(
    [ordered]@{
      Question = "Qu'est-ce que le jardinage en lasagnes sur balcon ?"
      Answer = "C'est une methode qui consiste a superposer des matieres brunes et vertes dans un bac pour creer un substrat riche, vivant et fertile, adapte aux petits espaces urbains."
    },
    [ordered]@{
      Question = "Quelles matieres faut-il utiliser pour une lasagne de balcon ?"
      Answer = "Il faut un contenant profond avec drainage, puis du carton humidifie, des matieres brunes comme les feuilles mortes ou la paille, des matieres vertes comme les epluchures ou le marc de cafe, et une couche finale de compost ou de terreau mur."
    },
    [ordered]@{
      Question = "Quand installer une lasagne sur son balcon ?"
      Answer = "Le printemps permet de planter rapidement, tandis que l'automne est ideal pour laisser la lasagne murir pendant l'hiver. C'est aussi possible en ete ou en hiver avec un suivi d'arrosage adapte."
    }
  )
  "jardin-sur-balcon-astuces" = @(
    [ordered]@{
      Question = "Quelles plantes choisir pour debuter un jardin sur balcon ?"
      Answer = "Le choix depend d'abord de l'exposition. Au soleil, privilegie les plantes mediterraneennes, tomates, aromatiques et fraisiers ; a l'ombre, les menthes, fougeres ou begonias sont plus adaptes."
    },
    [ordered]@{
      Question = "Comment bien gerer l'arrosage sur un balcon ?"
      Answer = "Arrose de preference le matin ou en fin de journee, surveille le dessechement rapide des pots en ete et utilise si besoin un goutte-a-goutte, des oyas ou des bouteilles retournees pour gagner en regularite."
    },
    [ordered]@{
      Question = "Comment gagner de la place sur un petit balcon ?"
      Answer = "Exploite la verticalité avec étagères, treillis, jardinières suspendues et cultures sur plusieurs niveaux. Pense aussi à organiser les plantes selon leur hauteur pour faciliter la circulation et la lumière."
    }
  )
  "erreurs-jardiner-sur-un-balcon" = @(
    [ordered]@{
      Question = "Quelle est l'erreur la plus frequente quand on jardine sur un balcon ?"
      Answer = "L'une des erreurs les plus courantes est de ne pas tenir compte de l'exposition au soleil. Le choix des plantes doit toujours partir du niveau d'ensoleillement reel du balcon."
    },
    [ordered]@{
      Question = "Comment eviter les erreurs d'arrosage sur un balcon ?"
      Answer = "Il faut adapter l'arrosage a chaque plante, verifier l'humidite du terreau sur quelques centimetres avant d'arroser et intervenir plutot le matin ou le soir pour limiter l'evaporation."
    },
    [ordered]@{
      Question = "Pourquoi ne faut-il pas surcharger un balcon de pots ?"
      Answer = "Un balcon trop chargé freine la circulation de l'air, augmente l'humidité stagnante, limite la lumière et complique l'entretien. Une sélection mieux espacée est plus saine et plus facile à gérer."
    }
  )
  "legumes-faciles-a-cultiver" = @(
    [ordered]@{
      Question = "Quels legumes sont les plus faciles a cultiver en pot sur un balcon ?"
      Answer = "Les laitues, radis, epinards, tomates cerises ou tomates cocktail font partie des cultures les plus accessibles pour debuter un potager de balcon productif."
    },
    [ordered]@{
      Question = "Quelle profondeur de pot faut-il prevoir pour un potager en conteneur ?"
      Answer = "Cela depend des cultures : environ 10 a 15 cm suffisent pour les radis, 15 a 20 cm pour les laitues et 30 cm ou plus pour les tomates afin d'offrir assez d'espace aux racines."
    },
    [ordered]@{
      Question = "Comment maximiser les recoltes sur un balcon ?"
      Answer = "Choisis un substrat adapte, respecte l'exposition de chaque legume, arrose regulierement, fertilise en saison et privilegie des semis echelonnes pour prolonger les recoltes."
    }
  )
  "guide-poivrons-sur-son-balcon" = @(
    [ordered]@{
      Question = "Quelle exposition faut-il pour cultiver des poivrons sur un balcon ?"
      Answer = "Les poivrons ont besoin d'un emplacement chaud, lumineux et abrite, avec idealement 6 a 8 heures de soleil par jour. Une chaleur stable leur reussit mieux qu'un balcon vente ou trop ombrage."
    },
    [ordered]@{
      Question = "Quel pot choisir pour des poivrons en conteneur ?"
      Answer = "Prevois un pot profond et stable de 15 a 25 litres minimum, avec un tres bon drainage. Un contenant trop petit accentue les coups de chaud, freine la croissance et complique l'arrosage."
    },
    [ordered]@{
      Question = "Pourquoi les fleurs de poivron tombent-elles avant de faire des fruits ?"
      Answer = "La chute des fleurs vient souvent d'un stress combine : froid nocturne, chaleur excessive, manque d'eau ou arrosages irreguliers. Une exposition ensoleillee mais geree, plus un arrosage regulier, limitent ce probleme."
    }
  )
}

$howToSchemaMap = @{
  "guide-tomates-sur-son-balcon" = [ordered]@{
    Name = "Comment cultiver des tomates sur son balcon"
    Description = "Les etapes essentielles pour installer, arroser, entretenir et recolter des tomates en pot sur un balcon."
    Steps = @(
      [ordered]@{
        Name = "Choisir un pot stable et drainant"
        Text = "Selectionne un contenant d'au moins 30 cm de profondeur et de largeur, avec un bon drainage et une couche de billes d'argile ou de graviers au fond."
      },
      [ordered]@{
        Name = "Installer le plant au soleil"
        Text = "Place les tomates dans une zone tres ensoleillee, idealement exposee plein sud, tout en les protegant du vent et des heures les plus brulantes."
      },
      [ordered]@{
        Name = "Planter profondement et tuteurer"
        Text = "Plante apres les gelees en enterrant une partie de la tige jusqu'aux premieres feuilles, ajoute du compost et pose un tuteur solide des la plantation."
      },
      [ordered]@{
        Name = "Arroser regulierement et pailler"
        Text = "Arrose en profondeur plusieurs fois par semaine selon la chaleur, sans mouiller le feuillage, puis ajoute un paillage pour limiter l'evaporation."
      },
      [ordered]@{
        Name = "Entretenir la plante en cours de saison"
        Text = "Supprime les gourmands, apporte un engrais riche en potasse tous les 10 a 15 jours et griffe legerement la surface du terreau pour favoriser l'aeration."
      },
      [ordered]@{
        Name = "Recolter au bon moment"
        Text = "Cueille les tomates bien colorees, fermes et brillantes, puis surveille la fin de saison pour retirer les fleurs tardives et faire murir les derniers fruits."
      }
    )
  }
  "jardinage-en-lasagnes-sur-balcon" = [ordered]@{
    Name = "Comment creer une lasagne de culture sur un balcon"
    Description = "Une methode simple pour monter un bac fertile en superposant des matieres organiques sur un balcon."
    Steps = @(
      [ordered]@{
        Name = "Choisir un contenant profond"
        Text = "Prends un bac, une jardiniere ou un sac de culture d'au moins 40 cm de profondeur et verifie que le drainage est bien prevu."
      },
      [ordered]@{
        Name = "Poser la base drainante"
        Text = "Installe au fond une couche de billes d'argile ou de graviers, puis recouvre avec du carton humidifie."
      },
      [ordered]@{
        Name = "Alterner matieres brunes et vertes"
        Text = "Empile successivement des matieres brunes comme les feuilles mortes ou la paille et des matieres vertes comme les epluchures ou le marc de cafe."
      },
      [ordered]@{
        Name = "Terminer avec du compost mur"
        Text = "Ajoute une couche finale de 5 a 10 cm de compost ou de terreau bien mur pour accueillir les futures plantations."
      },
      [ordered]@{
        Name = "Humidifier l'ensemble"
        Text = "Arrose genereusement pour mouiller toutes les couches et amorcer la decomposition du melange."
      },
      [ordered]@{
        Name = "Planter et entretenir"
        Text = "Installe ensuite legumes, aromatiques ou fleurs adaptes au balcon, puis complete chaque annee avec de nouvelles matieres organiques."
      }
    )
  }
  "recuperer-eau-de-pluie-balcon" = [ordered]@{
    Name = "Comment recuperer l'eau de pluie sur un balcon sans gouttiere"
    Description = "Les etapes pour capter, stocker et reutiliser l'eau de pluie sur un balcon urbain."
    Steps = @(
      [ordered]@{
        Name = "Observer les zones de captation"
        Text = "Repere les surfaces exposees a la pluie comme la rambarde, une table, un pare-vue, une jardiniere ou un rebord."
      },
      [ordered]@{
        Name = "Choisir un systeme simple de collecte"
        Text = "Utilise une bache inclinee, un entonnoir suspendu, une surface de mobilier ou un pare-vue equipe d'une rigole pour canaliser l'eau."
      },
      [ordered]@{
        Name = "Diriger l'eau vers un recipient"
        Text = "Place un seau, un bidon ou une caisse plastique au point bas du systeme pour recueillir le ruissellement."
      },
      [ordered]@{
        Name = "Stocker l'eau proprement"
        Text = "Ferme ou couvre le contenant avec une moustiquaire ou une grille fine pour eviter moustiques, algues et salissures."
      },
      [ordered]@{
        Name = "Reutiliser l'eau pour le balcon"
        Text = "Utilise cette eau pour arroser, humidifier le compost ou preparer des purins, de preference avec un paillage pour limiter l'evaporation."
      }
    )
  }
  "diy-pots-pour-le-balcon" = [ordered]@{
    Name = "Comment fabriquer des pots de balcon avec des objets recycles"
    Description = "Une methode simple pour transformer des objets du quotidien en contenants pratiques pour les plantes."
    Steps = @(
      [ordered]@{
        Name = "Choisir un contenant sain a recycler"
        Text = "Selectionne une boite de conserve, une passoire, un seau, une brique alimentaire ou un autre objet propre, solide et adapte a un usage au jardin."
      },
      [ordered]@{
        Name = "Nettoyer et preparer le drainage"
        Text = "Lave le contenant, retire les residus et perce plusieurs trous au fond si necessaire pour evacuer l'eau."
      },
      [ordered]@{
        Name = "Ajouter une couche drainante"
        Text = "Dispose un peu de graviers ou de billes d'argile au fond pour limiter l'exces d'humidite autour des racines."
      },
      [ordered]@{
        Name = "Remplir de terreau et planter"
        Text = "Ajoute un terreau adapte a la plante choisie puis installe des aromatiques, des fleurs ou de petits legumes compatibles avec la taille du pot."
      },
      [ordered]@{
        Name = "Finaliser avec les bons controles"
        Text = "Verifie le poids, la resistance du materiau, l'absence de toxicite et, si tu veux, personnalise le contenant avec peinture, corde ou suspension."
      }
    )
  }
  "solutions-compostage-sur-balcon" = [ordered]@{
    Name = "Comment choisir une solution de compostage adaptee a un balcon"
    Description = "Les etapes pour mettre en place un compostage compact et propre sur un petit espace urbain."
    Steps = @(
      [ordered]@{
        Name = "Evaluer la place et les besoins"
        Text = "Observe la surface disponible sur le balcon et estime la quantite de dechets organiques que tu produis chaque semaine."
      },
      [ordered]@{
        Name = "Choisir le bon systeme"
        Text = "Selectionne un lombricomposteur, un bokashi, un composteur rotatif ou un mini composteur selon l'espace disponible et le niveau d'implication souhaite."
      },
      [ordered]@{
        Name = "Trier les dechets autorises"
        Text = "Ajoute les epluchures, marc de cafe, sachets de the sans plastique, feuilles mortes ou carton brun, et evite viandes, produits laitiers, huiles et excrements."
      },
      [ordered]@{
        Name = "Equilibrer les matieres"
        Text = "Alterner toujours les matieres vertes et les matieres brunes pour obtenir un compost plus aere, plus stable et sans odeur."
      },
      [ordered]@{
        Name = "Utiliser le compost au jardin"
        Text = "Recupere ensuite le compost ou le the de compost pour nourrir naturellement les plantes et le potager de balcon."
      }
    )
  }
  "guide-poivrons-sur-son-balcon" = [ordered]@{
    Name = "Comment cultiver des poivrons sur son balcon"
    Description = "Les etapes essentielles pour installer, nourrir et recolter des poivrons en pot sur un balcon ensoleille."
    Steps = @(
      [ordered]@{
        Name = "Choisir une variete compacte et un grand pot"
        Text = "Selectionne une variete adaptee a la culture en conteneur et installe-la dans un pot profond, stable et bien draine d'au moins 15 a 25 litres."
      },
      [ordered]@{
        Name = "Planter dans un substrat riche"
        Text = "Remplis le contenant avec un terreau potager souple et drainant, enrichi avec un peu de compost mur pour soutenir la croissance."
      },
      [ordered]@{
        Name = "Installer le plant au chaud"
        Text = "Place les poivrons en plein soleil, a l'abri du vent, puis plante seulement lorsque les nuits restent durablement au-dessus de 12 a 15 degres."
      },
      [ordered]@{
        Name = "Arroser regulierement et pailler"
        Text = "Maintiens le terreau legerement frais sans le detremper, puis ajoute un paillage pour stabiliser l'humidite dans le pot."
      },
      [ordered]@{
        Name = "Fertiliser a partir de la floraison"
        Text = "Quand les premieres fleurs apparaissent, apporte un engrais organique riche en potasse toutes les une a deux semaines et pose un tuteur si besoin."
      },
      [ordered]@{
        Name = "Recolter selon la couleur finale"
        Text = "Cueille les fruits verts pour une recolte precoce ou attends leur pleine coloration pour un gout plus sucre et une meilleure intensite aromatique."
      }
    )
  }
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
        -Headers @{ "User-Agent" = "Mozilla/5.0 (compatible; HydroFacileStatic/1.0)" }
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
    if ($caption -match '^(Go to |Instagram|Twitter|X$|HydroFacile$)') { continue }
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
      Name = "HydroFacile"
    }
  }

  if ($author -is [System.Array] -and $author.Count -gt 0) {
    $author = $author[0]
  }

  $authorType = if ($author.'@type') { [string]$author.'@type' } else { "Organization" }
  $authorName = if ($author.name) { [System.Net.WebUtility]::HtmlDecode([string]$author.name) } else { "HydroFacile" }

  return [PSCustomObject]@{
    Type = $authorType
    Name = $authorName
  }
}

function Get-ArticleOverride {
  param([string]$slug)

  if ([string]::IsNullOrWhiteSpace($slug)) { return $null }
  if (-not $articleOverrides.Contains($slug)) { return $null }
  return $articleOverrides[$slug]
}

function Apply-ArticleOverride {
  param([pscustomobject]$article)

  $override = Get-ArticleOverride $article.Slug
  if ($null -eq $override) {
    return $article
  }

  $data = [ordered]@{}
  foreach ($property in $article.PSObject.Properties) {
    $data[$property.Name] = $property.Value
  }

  $supportedKeys = @(
    "Title",
    "SeoTitle",
    "Description",
    "Intro",
    "ImageFileName",
    "ImageAlt",
    "DatePublished",
    "DateModified",
    "TimeRequired",
    "AuthorName",
    "AuthorType",
    "Category",
    "BodyHtml",
    "Faq",
    "HowTo"
  )

  foreach ($key in $supportedKeys) {
    if ($override.Contains($key)) {
      $data[$key] = $override[$key]
    }
  }

  if ($override.Contains("Description") -and -not $override.Contains("Intro")) {
    $data["Intro"] = $data["Description"]
  }

  if (-not $data["Intro"]) {
    $data["Intro"] = $data["Description"]
  }

  if ($data["ImageFileName"]) {
    $data["ImageCanonicalUrl"] = Get-ImageCanonicalUrl $data["ImageFileName"]
  }

  return [PSCustomObject]$data
}

function Get-ArticleSources {
  $ignoreFiles = @("index.html", "articles.html", "galerie.html")
  $articleSources = New-Object System.Collections.Generic.List[object]

  foreach ($file in Get-ChildItem -Path $rawDir -File | Sort-Object Name) {
    if ($ignoreFiles -contains $file.Name) { continue }

    $content = Get-Content -Raw -Encoding UTF8 $file.FullName
    $schema = Get-SchemaData $content
    if ($schema.'@type' -ne 'Article') { continue }

    if ($schema.url -notmatch '^https://(?:www\.)?hydrofacile\.fr/(?:articles/)?(?<slug>[^/?#]+)/?(?:[?#].*)?$') {
      throw "Impossible de determiner le slug pour $($file.Name)."
    }

    $slug = $matches["slug"]
    if (-not (Test-IsPrimaryArticle $slug)) { continue }

    $date = if ($schema.datePublished) { [DateTime]::Parse($schema.datePublished) } else { [DateTime]::MinValue }
    $authorData = Get-AuthorData -schema $schema -content $content -slug $slug
    $heroCaption = Get-HeroCaption $content
    $imageRemoteUrl = [string]$schema.image
    $imageFileName = Get-ImageFileName -url $imageRemoteUrl -slug $slug
    $rawCategory = if ($schema.articleSection) {
      if ($schema.articleSection -is [System.Array]) {
        [string]$schema.articleSection[0]
      } else {
        [string]$schema.articleSection
      }
    } else {
      "Article"
    }
    $category = Get-CanonicalArticleCategory `
      -slug $slug `
      -rawCategory ([System.Net.WebUtility]::HtmlDecode($rawCategory)) `
      -title ([System.Net.WebUtility]::HtmlDecode($schema.name)) `
      -description ([System.Net.WebUtility]::HtmlDecode($schema.description))

    $article = [PSCustomObject]@{
        SourcePath = $file.FullName
        SourceName = $file.Name
        Slug = $slug
        OutputName = Get-ArticleLegacyFileName ([PSCustomObject]@{ Slug = $slug })
        Title = [System.Net.WebUtility]::HtmlDecode($schema.name)
        SeoTitle = ""
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
        Intro = [System.Net.WebUtility]::HtmlDecode($schema.description)
        BodyHtml = ""
        Faq = $null
        HowTo = $null
      }

    $articleSources.Add((Apply-ArticleOverride $article))
  }

  return $articleSources | Sort-Object `
    @{ Expression = "DateSort"; Descending = $true }, `
    @{ Expression = "Title"; Descending = $false }
}

$articles = @(Get-ArticleSources)
$primaryArticles = @($articles | Where-Object { Test-IsPrimaryArticle $_.Slug })
if ($primaryArticles.Count -eq 0) {
  $primaryArticles = $articles
}
$slugMap = @{}
foreach ($article in $articles) {
  $slugMap[$article.Slug] = Get-ArticlePrettyHref -article $article -hrefPrefix "../"
}

Ensure-ArticleImages $articles

function Resolve-Link {
  param([string]$url)

  if ($url -match '^https://(?:www\.)?hydrofacile\.fr/(?:articles/)?([^/?#]+)') {
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

  if ($url -match '^(?<slug>[^/?#]+)\.html(?<suffix>[?#].*)?$') {
    $slug = $matches["slug"]
    $suffix = $matches["suffix"]
    if ($slugMap.ContainsKey($slug)) {
      return "$($slugMap[$slug])$suffix"
    }
  }

  if ($url -match '^index\.html(?<suffix>[?#].*)?$') {
    return "../$($matches["suffix"])"
  }

  if ($url -match '^\.\./index\.html(?<suffix>[?#].*)?$') {
    return "../../$($matches["suffix"])"
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

function Fix-InlineAnchorSpacing {
  param([string]$html)

  if ([string]::IsNullOrWhiteSpace($html)) { return "" }

  $fixed = [regex]::Replace($html, '(?<=[\p{L}\p{N}])<a\b', ' <a')
  $fixed = [regex]::Replace($fixed, '</a>(?=[\p{L}\p{N}])', '</a> ')

  return $fixed
}

function Normalize-PlainTextForMatch {
  param([string]$text)

  if ([string]::IsNullOrWhiteSpace($text)) { return "" }

  $normalized = [System.Net.WebUtility]::HtmlDecode($text).Trim().ToLowerInvariant()
  $normalized = $normalized.Replace("’", "'").Replace("œ", "oe")
  $normalized = [regex]::Replace($normalized, '\s+', ' ')

  return $normalized
}

function Convert-KeyFactsSection {
  param([string]$html)

  if ([string]::IsNullOrWhiteSpace($html)) { return "" }

  return [regex]::Replace($html, '(?is)(?<headingBlock><h2\b[^>]*>(?<heading>.*?)</h2>)\s*<p>(?<content>.*?)</p>', {
      param($m)

      $headingText = Normalize-PlainTextForMatch ([regex]::Replace($m.Groups["heading"].Value, '(?is)<[^>]+>', ''))
      if ($headingText -ne "ce qu'il faut savoir en un coup d'oeil") {
        return $m.Value
      }

      $lines = @(
        [regex]::Split($m.Groups["content"].Value, '(?i)<br\s*/?>') |
          ForEach-Object { (Fix-InlineAnchorSpacing $_).Trim() } |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
      )

      if ($lines.Count -lt 3) {
        return $m.Value
      }

      $items = @()
      $labelCount = 0

      foreach ($line in $lines) {
        $lineMatch = [regex]::Match($line, '^(?<label>[^:]{2,48})\s*:\s*(?<value>.+)$')

        if ($lineMatch.Success) {
          $label = [regex]::Replace($lineMatch.Groups["label"].Value, '(?is)<[^>]+>', '')
          $label = [System.Net.WebUtility]::HtmlDecode($label).Trim()
          $value = (Fix-InlineAnchorSpacing $lineMatch.Groups["value"].Value).Trim()

          if ($label -and $value) {
            $labelCount++
            $items += [PSCustomObject]@{
              IsFull = $false
              Label = $label
              Value = $value
            }
            continue
          }
        }

        $items += [PSCustomObject]@{
          IsFull = $true
          Label = ""
          Value = $line
        }
      }

      if ($labelCount -lt 3) {
        return $m.Value
      }

      $builder = New-Object System.Text.StringBuilder
      [void]$builder.AppendLine('            <div class="article-key-facts" role="list">')

      foreach ($item in $items) {
        if ($item.IsFull) {
          [void]$builder.AppendLine("              <div class=`"article-key-facts-item article-key-facts-item-full`" role=`"listitem`"><span>$($item.Value)</span></div>")
          continue
        }

        $safeLabel = HtmlEscape $item.Label
        [void]$builder.AppendLine("              <div class=`"article-key-facts-item`" role=`"listitem`"><strong>${safeLabel}&nbsp;: </strong><span>$($item.Value)</span></div>")
      }

      [void]$builder.Append('            </div>')

      return "$($m.Groups["headingBlock"].Value)`n$($builder.ToString())"
    })
}

function Normalize-BodyHtml {
  param([string]$html)

  if ([string]::IsNullOrWhiteSpace($html)) { return "" }

  $normalized = [regex]::Replace($html, '(?is)(\bhref=)(["'']?)(?<url>[^"''\s>]+)\2', {
      param($m)
      $quote = if ($m.Groups[2].Value) { $m.Groups[2].Value } else { '"' }
      $url = Resolve-Link ([System.Net.WebUtility]::HtmlDecode($m.Groups["url"].Value))
      return "$($m.Groups[1].Value)$quote$url$quote"
    })

  return Convert-KeyFactsSection (Fix-InlineAnchorSpacing $normalized)
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

  return (Fix-InlineAnchorSpacing $working).Trim()
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

  $bodyHtml = $builder.ToString().TrimEnd() -replace '(?s)<a href="(?<url>[^"]+)"(?<attrs>[^>]*)>(?<text>[^<]+)</a>\s*<a href="\k<url>"[^>]*>\k<url></a>', '<a href="${url}"${attrs}>${text}</a> '
  return Convert-KeyFactsSection $bodyHtml
}

function Ensure-AffiliateDisclosure {
  param([string]$bodyHtml)

  if ([string]::IsNullOrWhiteSpace($bodyHtml)) { return "" }
  if ($bodyHtml -match 'class="affiliate-disclosure"') { return $bodyHtml }

  $affiliatePattern = 'href="https?://(?:www\.)?(?:amzn\.to|amazon\.)'
  if ($bodyHtml -notmatch $affiliatePattern) { return $bodyHtml }

  $disclosureLine = '            <p class="affiliate-disclosure">Liens affiliés Amazon. En tant que Partenaire Amazon, je réalise un bénéfice sur les achats remplissant les conditions requises.</p>'
  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in ($bodyHtml -split "`r?`n")) {
    [void]$lines.Add($line)
  }

  $affiliateIndex = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match $affiliatePattern) {
      $affiliateIndex = $i
      break
    }
  }

  if ($affiliateIndex -lt 0) { return $bodyHtml }

  $insertIndex = $affiliateIndex
  for ($i = $affiliateIndex; $i -ge 0; $i--) {
    if ($lines[$i] -match '<(ul|ol)\b') {
      $insertIndex = $i
      break
    }

    if ($i -lt $affiliateIndex -and $lines[$i] -match '<(p|h2|h3)\b|</(ul|ol)>') {
      break
    }
  }

  $lines.Insert($insertIndex, $disclosureLine)
  return ($lines -join "`n")
}

function Get-JsonLdScriptTags {
  param([object[]]$objects)

  $scripts = New-Object System.Collections.Generic.List[string]
  foreach ($obj in $objects) {
    if ($null -eq $obj) { continue }
    $scripts.Add("  <script type=`"application/ld+json`">$($obj | ConvertTo-Json -Depth 10 -Compress)</script>")
  }

  return ($scripts -join "`n")
}

function Get-ArticleBreadcrumbSchema {
  param(
    [pscustomobject]$article,
    [string]$canonicalUrl
  )

  return [ordered]@{
    "@context" = "https://schema.org"
    "@type" = "BreadcrumbList"
    itemListElement = @(
      [ordered]@{
        "@type" = "ListItem"
        position = 1
        name = "Accueil"
        item = "$siteUrl/"
      },
      [ordered]@{
        "@type" = "ListItem"
        position = 2
        name = "Articles"
        item = "$siteUrl/articles/"
      },
      [ordered]@{
        "@type" = "ListItem"
        position = 3
        name = $article.Title
        item = $canonicalUrl
      }
    )
  }
}

function Get-ArticleFaqSchema {
  param([pscustomobject]$article)

  if (-not $article.Faq) {
    return $null
  }

  return [ordered]@{
    "@context" = "https://schema.org"
    "@type" = "FAQPage"
    mainEntity = @(
      $article.Faq | ForEach-Object {
        [ordered]@{
          "@type" = "Question"
          name = $_.Question
          acceptedAnswer = [ordered]@{
            "@type" = "Answer"
            text = $_.Answer
          }
        }
      }
    )
  }
}

function Get-ArticleHowToSchema {
  param([pscustomobject]$article)

  if (-not $article.HowTo) {
    return $null
  }

  $howTo = $article.HowTo
  $steps = @()
  $position = 1

  foreach ($step in $howTo.Steps) {
    $steps += [ordered]@{
        "@type" = "HowToStep"
        position = $position
        name = $step.Name
        text = $step.Text
      }
    $position += 1
  }

  $schema = [ordered]@{
    "@context" = "https://schema.org"
    "@type" = "HowTo"
    name = $howTo.Name
    description = $howTo.Description
    inLanguage = "fr"
    image = @($article.ImageCanonicalUrl)
    step = $steps
  }

  if ($article.TimeRequired) {
    $schema["totalTime"] = $article.TimeRequired
  }

  return $schema
}

function Build-ArticleHtml {
  param(
    [pscustomobject]$article,
    [object[]]$allArticles
  )

  $content = Get-Content -Raw -Encoding UTF8 $article.SourcePath
  $heroCaption = if ($article.ImageAlt) { $article.ImageAlt } else { Get-HeroCaption $content }
  $bodyHtml = if ($article.BodyHtml) { Normalize-BodyHtml ($article.BodyHtml.TrimEnd()) } else { Build-ArticleBody $content }
  $bodyHtml = Ensure-AffiliateDisclosure $bodyHtml
  $dateText = Convert-IsoDateToFrench $article.DatePublished
  $timeText = Convert-TimeRequired $article.TimeRequired
  $canonicalUrl = Get-ArticleCanonicalUrl $article
  $seoTitle = if ($article.SeoTitle) { $article.SeoTitle } else { $article.Title }
  $robotsContent = if (Test-IsPrimaryArticle $article.Slug) { "index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1" } else { "noindex,follow" }
  $heroImageSrc = Get-ImagePagePath -fileName $article.ImageFileName -pagePrefix "../../images/articles/"
  $heroImageDimensions = Get-ArticleImageDimensionAttributes $article.ImageFileName
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $relatedArticles = @(Get-RelatedArticles -article $article -allArticles $allArticles -count 3)

  $articleSchema = [ordered]@{
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
      name = $siteName
      logo = [ordered]@{
        "@type" = "ImageObject"
        url = $siteLogoUrl
      }
    }
  }
  $breadcrumbSchema = Get-ArticleBreadcrumbSchema -article $article -canonicalUrl $canonicalUrl
  $faqSchema = Get-ArticleFaqSchema -article $article
  $howToSchema = Get-ArticleHowToSchema -article $article
  $jsonLdScripts = Get-JsonLdScriptTags @($articleSchema, $breadcrumbSchema, $faqSchema, $howToSchema)

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
  $breadcrumbHtml = @"
        <nav class="breadcrumb-nav" aria-label="fil d'ariane">
          <ol class="breadcrumb">
            <li><a href="../../">Accueil</a></li>
            <li><a href="../">Articles</a></li>
            <li aria-current="page">$(HtmlEscape $article.Title)</li>
          </ol>
        </nav>
"@
  $relatedCardsHtml = if ($relatedArticles.Count -gt 0) {
    (($relatedArticles | ForEach-Object {
          Build-ArticleCardHtml -article $_ -hrefPrefix "../" -imagePrefix "../../images/articles/" -extraClass " related-card"
        }) -join "`n")
  } else { "" }
  $relatedSection = if ($relatedCardsHtml) {
@"
        <section class="related-section" aria-labelledby="related-articles-heading">
          <div class="section-heading section-heading-compact">
            <div>
              <h2 id="related-articles-heading">À lire aussi</h2>
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
  <title>$(HtmlEscape $seoTitle) | $siteName</title>
  <meta name="description" content="$(HtmlEscape $article.Description)">
  <meta name="robots" content="$robotsContent">
  <meta name="author" content="$(HtmlEscape $article.AuthorName)">
  <link rel="preload" as="image" href="$heroImageSrc" fetchpriority="high">
  <link rel="canonical" href="$canonicalUrl">
  <link rel="alternate" hreflang="fr" href="$canonicalUrl">
  <link rel="alternate" hreflang="x-default" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="article">
  <meta property="og:title" content="$(HtmlEscape $seoTitle) | $siteName">
  <meta property="og:description" content="$(HtmlEscape $article.Description)">
  <meta property="og:url" content="$canonicalUrl">
  <meta property="og:image" content="$($article.ImageCanonicalUrl)">
  <meta property="og:image:alt" content="$(HtmlEscape $heroCaption)">
  <meta property="article:published_time" content="$($article.DatePublished)">
  <meta property="article:modified_time" content="$($article.DateModified)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="$(HtmlEscape $seoTitle) | $siteName">
  <meta name="twitter:description" content="$(HtmlEscape $article.Description)">
  <meta name="twitter:image" content="$($article.ImageCanonicalUrl)">
  <meta name="twitter:image:alt" content="$(HtmlEscape $heroCaption)">
$jsonLdScripts
$tagManagerHead
  <link rel="icon" href="../../images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="../../images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../../images/apple-touch-icon.png">
  <link rel="manifest" href="../../site.webmanifest">
  <link rel="stylesheet" href="$articleDetailStylesheetHref">
</head>
<body class="article-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../../">
          <span class="brand-mark">
            <img class="brand-logo" src="../../images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../../">Accueil</a>
            <a href="../">Articles</a>
            <a href="../../contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="article-layout">
      <div class="article-shell">
        <div>
$breadcrumbHtml
        </div>
        <header class="article-header">
          <span class="eyebrow">$(HtmlEscape $article.Category)</span>
          <h1 class="article-title">$(HtmlEscape $article.Title)</h1>
          <div class="article-meta">
            $metaHtml
          </div>
          <p class="article-intro">$(HtmlEscape $article.Intro)</p>
        </header>

        <figure class="hero-image">
          <img src="$heroImageSrc" alt="$(HtmlEscape $heroCaption)" title="$(HtmlEscape $heroTitle)" loading="eager" decoding="async" fetchpriority="high"$heroImageDimensions>
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
                <li><a href="../">Retour &agrave; la liste des articles</a></li>
                <li><a href="../../">Retour &agrave; l'accueil</a></li>
                <li><a href="../../contact/">Contacter HydroFacile</a></li>
              </ul>
            </div>
          </aside>
        </div>
$relatedSection
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "../../")
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

  $category = Get-CanonicalArticleCategory -slug $article.Slug -rawCategory $article.Category -title $article.Title -description $article.Description
  $summary = Get-CardExcerpt $article.Description
  $href = Get-ArticlePrettyHref -article $article -hrefPrefix $hrefPrefix
  $imageSrc = Get-ImagePagePath -fileName $article.ImageFileName -pagePrefix $imagePrefix
  $imageDimensions = Get-ArticleImageDimensionAttributes $article.ImageFileName
  $className = "article-card$extraClass"

  return @"
          <article class="$className">
            <img src="$imageSrc" alt="$(HtmlEscape $article.ImageAlt)" title="$(HtmlEscape $article.ImageAlt)" loading="lazy" decoding="async"$imageDimensions>
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

  if ($allArticles.Count -eq 0) {
    $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
    $tagManagerHead = Get-TagManagerHeadHtml
    $tagManagerBody = Get-TagManagerBodyHtml
    $jsonLd = Get-JsonLdScriptTags @([ordered]@{
        "@context" = "https://schema.org"
        "@type" = "WebSite"
        name = $siteName
        url = "$siteUrl/"
        inLanguage = "fr"
        description = "HydroFacile prépare des guides clairs pour débuter en hydroponie en appartement, comprendre la culture sans terre et choisir un petit système simple."
        potentialAction = [ordered]@{
          "@type" = "SearchAction"
          target = "$siteUrl/articles/?q={search_term_string}"
          "query-input" = "required name=search_term_string"
        }
        publisher = [ordered]@{
          "@type" = "Organization"
          name = $siteName
          logo = [ordered]@{
            "@type" = "ImageObject"
            url = $siteLogoUrl
          }
        }
      })

    return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hydroponie débutant appartement | $siteName</title>
  <meta name="description" content="HydroFacile prépare des guides clairs pour débuter en hydroponie en appartement, comprendre la culture sans terre et choisir un petit système simple.">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <link rel="preload" as="image" href="images/articles/hydro-systeme-debutant.svg" fetchpriority="high">
  <link rel="canonical" href="$siteUrl/">
  <link rel="alternate" hreflang="fr" href="$siteUrl/">
  <link rel="alternate" hreflang="x-default" href="$siteUrl/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Hydroponie débutant appartement | $siteName">
  <meta property="og:description" content="HydroFacile prépare des guides clairs pour débuter en hydroponie en appartement, comprendre la culture sans terre et choisir un petit système simple.">
  <meta property="og:url" content="$siteUrl/">
  <meta property="og:image" content="$siteUrl/images/articles/hydro-systeme-debutant.svg">
  <meta property="og:image:alt" content="Petite installation hydroponique propre en intérieur">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Hydroponie débutant appartement | $siteName">
  <meta name="twitter:description" content="HydroFacile prépare des guides clairs pour débuter en hydroponie en appartement, comprendre la culture sans terre et choisir un petit système simple.">
  <meta name="twitter:image" content="$siteUrl/images/articles/hydro-systeme-debutant.svg">
  <meta name="twitter:image:alt" content="Petite installation hydroponique propre en intérieur">
$jsonLd
$tagManagerHead
  <link rel="icon" href="images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="images/apple-touch-icon.png">
  <link rel="manifest" href="site.webmanifest">
  <link rel="stylesheet" href="$rootStylesheetHref">
</head>
<body class="home-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="./">
          <span class="brand-mark">
            <img class="brand-logo" src="images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="./" aria-current="page">Accueil</a>
            <a href="articles/">Articles</a>
            <a href="contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main>
      <section class="hero hero-home">
        <div class="section-inner hero-grid">
          <div class="hero-copy">
            <div class="hero-copy-main" data-reveal>
              <span class="eyebrow hero-eyebrow">$siteName &middot; Hydroponie débutant</span>
              <h1>Comprendre l'hydroponie simplement, chez soi.</h1>
              <p>HydroFacile aide à débuter en appartement avec des explications claires, une approche propre et des repères simples pour choisir un petit système sans se compliquer.</p>
            </div>
            <div class="hero-copy-side">
              <div class="hero-actions" data-reveal style="--reveal-delay: 90ms;">
                <a class="button" href="contact/">Ouvrir le contact</a>
                <a class="button-secondary" href="articles/">Explorer les guides</a>
              </div>
              <div class="hero-support-note" data-reveal style="--reveal-delay: 160ms;">
                <span class="hero-support-chip">En clair</span>
                <strong>L'hydroponie, c'est faire pousser des plantes avec de l'eau enrichie et un support léger, sans terre classique.</strong>
                <p>Le but n'est pas d'ajouter du jargon. Ici, on cherche surtout à comprendre la méthode, débuter petit et prendre de bons réflexes dans un appartement.</p>
                <a class="text-link" href="articles/">Voir les prochains guides</a>
              </div>
              <div class="hero-stat-grid" data-reveal style="--reveal-delay: 220ms;">
                <article class="mini-stat">
                  <span class="mini-stat-label">Peu de place</span>
                  <strong>1 coin</strong>
                  <span class="mini-stat-copy">un plan de travail ou une étagère lumineuse peuvent suffire pour débuter.</span>
                </article>
                <article class="mini-stat">
                  <span class="mini-stat-label">Routine claire</span>
                  <strong>10 min</strong>
                  <span class="mini-stat-copy">une courte vérification régulière vaut mieux qu'une installation compliquée.</span>
                </article>
                <article class="mini-stat">
                  <span class="mini-stat-label">Approche</span>
                  <strong>Pas a pas</strong>
                  <span class="mini-stat-copy">comprendre l'eau, la lumière et les plantes sans jargon inutile.</span>
                </article>
              </div>
            </div>
          </div>

          <aside class="hero-panel" aria-label="Installation hydroponique débutant en appartement" data-reveal style="--reveal-delay: 120ms;">
            <figure class="home-visual">
              <div class="home-visual-stage">
                <img class="home-visual-main" src="images/articles/hydro-systeme-debutant.svg" alt="Petite installation hydroponique propre en intérieur" loading="eager" decoding="async" fetchpriority="high" width="1200" height="900">
              </div>
              <figcaption class="home-visual-note">
                <span class="home-visual-chip">Petit setup</span>
                <p>Une installation compacte, propre et facile à suivre reste souvent la meilleure porte d'entrée pour apprendre l'hydroponie chez soi.</p>
              </figcaption>
            </figure>
          </aside>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading" data-reveal>
            <div>
              <h2>Par où commencer</h2>
              <p>Trois points simples pour entrer dans l'hydroponie sans se sentir perdu.</p>
            </div>
          </div>
          <div class="home-path-grid" data-reveal-group>
            <article class="home-path-card" data-reveal style="--reveal-delay: 60ms;">
              <span class="eyebrow">Comprendre</span>
              <h3><a href="articles/">Voir comment la methode fonctionne</a></h3>
              <p>Eau, nutriments, lumière et support : l'idée devient simple quand chaque mot est expliqué clairement.</p>
              <a class="text-link" href="articles/">Voir les guides</a>
            </article>
            <article class="home-path-card" data-reveal style="--reveal-delay: 130ms;">
              <span class="eyebrow">Choisir</span>
              <h3><a href="contact/">Poser une question sur son futur setup</a></h3>
              <p>Un doute sur le réservoir, la lumière ou le format à choisir pour débuter en appartement ? La page contact sert de point d'entrée.</p>
              <a class="text-link" href="contact/">Aller au contact</a>
            </article>
            <article class="home-path-card" data-reveal style="--reveal-delay: 200ms;">
              <span class="eyebrow">Debuter</span>
              <h3><a href="contact/">Sugg&eacute;rer un sujet utile</a></h3>
              <p>Si un besoin revient souvent dans ton installation, la page contact permet de signaler les thèmes à couvrir en priorité.</p>
              <a class="text-link" href="contact/">Partager un besoin</a>
            </article>
          </div>
        </div>
      </section>

      <section class="section section-soft">
        <div class="section-inner">
          <div class="cta-strip" data-reveal>
            <div>
              <h2 class="page-title">Une base simple avant les premiers guides</h2>
              <p class="page-intro">
                HydroFacile pose les bases d'un site clair et rassurant pour apprendre l'hydroponie en appartement, avec peu de place et sans blabla.
              </p>
            </div>
            <a class="button" href="contact/">Ouvrir la page contact</a>
          </div>
        </div>
      </section>
    </main>

$(Get-SiteFooterHtml -pagePrefix "")
  </div>
</body>
</html>
"@
  }

  $featured = @($allArticles | Select-Object -First 6)
  $cardsHtml = (($featured | ForEach-Object -Begin { $cardIndex = 0 } -Process {
        $delay = 80 + ($cardIndex * 70)
        $cardIndex++
        (Build-ArticleCardHtml -article $_ -hrefPrefix "articles/" -imagePrefix "images/articles/") -replace '<article class="article-card">', "<article class=`"article-card`" data-reveal style=`"--reveal-delay: ${delay}ms;`">"
      }) -join "`n")
  $count = $allArticles.Count
  $featuredArticle = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "hydroponie-sans-pompe-appartement",
    "cultures-faciles-hydroponie-appartement",
    "lumiere-hydroponie-appartement"
  ) -fallbackIndex 0
  $featuredImage = if ($featuredArticle) { $featuredArticle.ImageCanonicalUrl } else { "" }
  $featuredImageSrc = if ($featuredArticle) { Get-ImagePagePath -fileName $featuredArticle.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $featuredImageDimensions = if ($featuredArticle) { Get-ArticleImageDimensionAttributes $featuredArticle.ImageFileName } else { "" }
  $featuredTitle = if ($featuredArticle) { $featuredArticle.Title } else { "Hydroponie simple en appartement" }
  $featuredImageAlt = if ($featuredArticle) { $featuredArticle.ImageAlt } else { "Petite installation hydroponique propre en intérieur" }
  $shareImage = if ($featuredArticle) { $featuredArticle.ImageCanonicalUrl } else { "$siteUrl/images/articles/hydro-systeme-debutant.svg" }
  $shareImageAlt = $featuredImageAlt
  $heroSecondary = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "cultures-faciles-hydroponie-appartement",
    "lumiere-hydroponie-appartement",
    "laitue-hydroponique-appartement"
  ) -fallbackIndex 1
  $heroSupportHref = "articles/hydroponie-sans-pompe-appartement/"
  $homeVisualDimensions = if ($featuredArticle) { Get-ArticleImageDimensionAttributes $featuredArticle.ImageFileName } else { " width=`"1200`" height=`"900`"" }
  $homeStats = @(
    [PSCustomObject]@{ Label = "Guides utiles"; Value = "$count"; Copy = "pour choisir un système simple et lancer tes premières cultures." },
    [PSCustomObject]@{ Label = "Repères clairs"; Value = "4"; Copy = "angles pour comprendre la lumière, l'eau, les nutriments et les variétés." },
    [PSCustomObject]@{ Label = "Pensé pour"; Value = "100 %"; Copy = "les appartements, les petits plans de travail et les coins lumineux." }
  )
  $statsHtml = (($homeStats | ForEach-Object {
@"
            <article class="mini-stat">
              <span class="mini-stat-label">$($_.Label)</span>
              <strong>$($_.Value)</strong>
              <span class="mini-stat-copy">$($_.Copy)</span>
            </article>
"@
      }) -join "`n")
  $startBlocks = @(
    [PSCustomObject]@{
      Label = "Comprendre"
      Title = "Pourquoi commencer sans pompe"
      Copy = "Le format le plus simple pour apprendre l'eau, l'air et la lumière sans ajouter de bruit ni de tuyaux."
      Href = "articles/hydroponie-sans-pompe-appartement/#pourquoi-sans-pompe"
      LinkLabel = "Voir le guide"
    },
    [PSCustomObject]@{
      Label = "Eclairer"
      Title = "Choisir entre fenêtre et lampe"
      Copy = "Une bonne lumière change tout en hydroponie appartement. Le but est d'avoir assez de régularité sans surinvestir."
      Href = "articles/lumiere-hydroponie-appartement/"
      LinkLabel = "Voir la lumière"
    },
    [PSCustomObject]@{
      Label = "Cultiver"
      Title = "Choisir les cultures les plus simples"
      Copy = "Laitue, basilic, menthe, ciboulette et jeunes pousses donnent vite des repères fiables dans un appartement."
      Href = "articles/cultures-faciles-hydroponie-appartement/"
      LinkLabel = "Voir les cultures"
    }
  )
  $startHtml = (($startBlocks | ForEach-Object -Begin { $startIndex = 0 } -Process {
      $delay = 60 + ($startIndex * 70)
      $startIndex++
      $href = $_.Href
@"
          <article class="home-path-card" data-reveal style="--reveal-delay: ${delay}ms;">
            <span class="eyebrow">$($_.Label)</span>
            <h3><a href="$href">$(HtmlEscape $_.Title)</a></h3>
            <p>$(HtmlEscape $_.Copy)</p>
            <a class="text-link" href="$href">$(HtmlEscape $_.LinkLabel)</a>
          </article>
"@
    }) -join "`n")
  $weeklyFallbackArticle = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "lumiere-hydroponie-appartement",
    "cultures-faciles-hydroponie-appartement",
    "laitue-hydroponique-appartement",
    "basilic-hydroponie-interieur",
    "nutriments-hydroponie-debutant",
    "nettoyer-systeme-hydroponique",
    "hydroponie-sans-pompe-appartement"
  ) -fallbackIndex 0
  $weeklyFeatureHref = if ($weeklyFallbackArticle) { Get-ArticlePrettyHref -article $weeklyFallbackArticle -hrefPrefix "articles/" } else { "articles/" }
  $weeklyFeatureImageSrc = if ($weeklyFallbackArticle) { Get-ImagePagePath -fileName $weeklyFallbackArticle.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $weeklyFeatureImageDimensions = if ($weeklyFallbackArticle) { Get-ArticleImageDimensionAttributes $weeklyFallbackArticle.ImageFileName } else { "" }
  $weeklyFeatureCategory = if ($weeklyFallbackArticle) { $weeklyFallbackArticle.Category } else { "À lire" }
  $weeklyFeatureTitle = if ($weeklyFallbackArticle) { $weeklyFallbackArticle.Title } else { "À découvrir cette semaine" }
  $weeklyFeatureDescription = if ($weeklyFallbackArticle) { Get-CardExcerpt $weeklyFallbackArticle.Description 178 } else { "Une sélection pratique choisie automatiquement selon la période de l'année." }
  $weeklyFeatureImageAlt = if ($weeklyFallbackArticle) { $weeklyFallbackArticle.ImageAlt } else { "Sélection d'article HydroFacile de la semaine" }
  $weeklyArticlesForJs = @(
    $allArticles | ForEach-Object {
      $imageDimensions = Get-ImageDimensions (Join-Path $imagesDir $_.ImageFileName)
      [ordered]@{
        slug = $_.Slug
        title = $_.Title
        description = $_.Description
        category = $_.Category
        href = Get-ArticlePrettyHref -article $_ -hrefPrefix "articles/"
        imageSrc = Get-ImagePagePath -fileName $_.ImageFileName -pagePrefix "images/articles/"
        imageAlt = $_.ImageAlt
        datePublished = $_.DatePublished
        width = if ($imageDimensions) { $imageDimensions.Width } else { $null }
        height = if ($imageDimensions) { $imageDimensions.Height } else { $null }
      }
    }
  )
  $weeklyArticlesJson = $weeklyArticlesForJs | ConvertTo-Json -Depth 5 -Compress
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $themeHtml = @"
          <article class="theme-card" data-reveal style="--reveal-delay: 60ms;">
            <span class="eyebrow">D&eacute;buter</span>
            <h3><a href="articles/#theme=debuter">Poser les bases sans se compliquer</a></h3>
            <p>Les guides pour comprendre la m&eacute;thode, choisir un format simple et &eacute;viter les erreurs du d&eacute;part.</p>
            <a class="text-link" href="articles/#theme=debuter">Voir les bases</a>
          </article>
          <article class="theme-card" data-reveal style="--reveal-delay: 130ms;">
            <span class="eyebrow">Mat&eacute;riel &amp; syst&egrave;mes</span>
            <h3><a href="articles/#theme=materiel-systemes">Construire un setup simple et propre</a></h3>
            <p>R&eacute;servoir, pots filet, substrat, nutriments et lumi&egrave;re : seulement les briques vraiment utiles pour un syst&egrave;me hydroponique d&eacute;butant.</p>
            <a class="text-link" href="articles/#theme=materiel-systemes">Voir le setup</a>
          </article>
          <article class="theme-card" data-reveal style="--reveal-delay: 200ms;">
            <span class="eyebrow">Cultures faciles</span>
            <h3><a href="articles/#theme=cultures-faciles">Choisir quoi lancer en premier</a></h3>
            <p>Laitues, basilic, aromatiques et tomates cerises: des cultures hydroponiques faciles pour prendre confiance &agrave; la maison.</p>
            <a class="text-link" href="articles/#theme=cultures-faciles">Voir les cultures</a>
          </article>
          <article class="theme-card" data-reveal style="--reveal-delay: 270ms;">
            <span class="eyebrow">Routine &amp; r&eacute;glages</span>
            <h3><a href="articles/#theme=routine-reglages">Garder une installation stable au quotidien</a></h3>
            <p>Calendrier, v&eacute;rifications simples et petits gestes pour garder une culture hydroponique facile, propre et rassurante.</p>
            <a class="text-link" href="articles/#theme=routine-reglages">Voir la routine</a>
          </article>
"@
  $editorialFeature = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "cultures-faciles-hydroponie-appartement",
    "laitue-hydroponique-appartement",
    "basilic-hydroponie-interieur",
    "hydroponie-sans-pompe-appartement"
  ) -fallbackIndex 0
  $editorialFeatureHref = if ($editorialFeature) { Get-ArticlePrettyHref -article $editorialFeature -hrefPrefix "articles/" } else { "articles/" }
  $editorialFeatureImageSrc = if ($editorialFeature) { Get-ImagePagePath -fileName $editorialFeature.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $editorialFeatureImageDimensions = if ($editorialFeature) { Get-ArticleImageDimensionAttributes $editorialFeature.ImageFileName } else { "" }
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $editorialList = @(
    $allArticles |
      Where-Object { $null -eq $editorialFeature -or $_.Slug -ne $editorialFeature.Slug } |
      Select-Object -First 3
  )
  $editorialListHtml = (($editorialList | ForEach-Object {
      $href = Get-ArticlePrettyHref -article $_ -hrefPrefix "articles/"
@"
            <article class="editorial-item">
              <span class="pill">$(HtmlEscape $_.Category)</span>
              <h3><a href="$href">$(HtmlEscape $_.Title)</a></h3>
              <p>$(HtmlEscape (Get-CardExcerpt $_.Description 118))</p>
            </article>
"@
    }) -join "`n")
  $jsonLd = Get-JsonLdScriptTags @([ordered]@{
      "@context" = "https://schema.org"
      "@type" = "WebSite"
      name = $siteName
      url = "$siteUrl/"
      inLanguage = "fr"
      description = $siteLongDescription
      potentialAction = [ordered]@{
        "@type" = "SearchAction"
        target = "$siteUrl/articles/?q={search_term_string}"
        "query-input" = "required name=search_term_string"
      }
      publisher = [ordered]@{
        "@type" = "Organization"
        name = $siteName
        logo = [ordered]@{
          "@type" = "ImageObject"
          url = $siteLogoUrl
        }
      }
    })

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Hydroponie débutant appartement | $siteName</title>
  <meta name="description" content="$siteLongDescription">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <link rel="preload" as="image" href="$featuredImageSrc" fetchpriority="high">
  <link rel="canonical" href="$siteUrl/">
  <link rel="alternate" hreflang="fr" href="$siteUrl/">
  <link rel="alternate" hreflang="x-default" href="$siteUrl/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Hydroponie débutant appartement | $siteName">
  <meta property="og:description" content="$siteLongDescription">
  <meta property="og:url" content="$siteUrl/">
  <meta property="og:image" content="$shareImage">
  <meta property="og:image:alt" content="$(HtmlEscape $shareImageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Hydroponie débutant appartement | $siteName">
  <meta name="twitter:description" content="$siteLongDescription">
  <meta name="twitter:image" content="$shareImage">
  <meta name="twitter:image:alt" content="$(HtmlEscape $shareImageAlt)">
$jsonLd
$tagManagerHead
  <link rel="icon" href="images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="images/apple-touch-icon.png">
  <link rel="manifest" href="site.webmanifest">
  <link rel="stylesheet" href="$rootStylesheetHref">
</head>
<body class="home-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="./">
          <span class="brand-mark">
            <img class="brand-logo" src="images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="./" aria-current="page">Accueil</a>
            <a href="articles/">Articles</a>
            <a href="contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main>
      <section class="hero hero-home">
        <div class="section-inner hero-grid">
          <div class="hero-copy">
            <div class="hero-copy-main" data-reveal>
              <span class="eyebrow hero-eyebrow">$siteName &middot; Hydroponie int&eacute;rieure</span>
              <h1>Hydroponie débutant en appartement, sans se compliquer.</h1>
              <p>Des guides clairs pour d&eacute;marrer un syst&egrave;me hydroponique simple, choisir les bonnes cultures et faire pousser en appartement sans jardin.</p>
            </div>
            <div class="hero-copy-side">
              <div class="hero-actions" data-reveal style="--reveal-delay: 90ms;">
                <a class="button" href="articles/">Explorer les guides</a>
                <a class="button-secondary" href="$heroSupportHref">D&eacute;marrer simplement</a>
              </div>
              <div class="hero-support-note" data-reveal style="--reveal-delay: 160ms;">
                <span class="hero-support-chip">Le bon r&eacute;flexe</span>
                <strong>Un petit r&eacute;servoir bien suivi vaut mieux qu'une installation compliqu&eacute;e.</strong>
                <p>Quelques plantes faciles, une routine stable et un setup propre suffisent souvent pour prendre confiance et comprendre vite ce qui fonctionne chez toi.</p>
                <a class="text-link" href="$heroSupportHref">Voir le guide d&eacute;butant</a>
              </div>
              <div class="hero-stat-grid" data-reveal style="--reveal-delay: 220ms;">
$statsHtml
              </div>
            </div>
          </div>

          <aside class="hero-panel" aria-label="Installation hydroponique d&eacute;butant en appartement" data-reveal style="--reveal-delay: 120ms;">
            <figure class="home-visual">
              <div class="home-visual-stage">
                <img class="home-visual-main" src="$featuredImageSrc" alt="$(HtmlEscape $featuredImageAlt)" title="$(HtmlEscape $featuredTitle)" loading="eager" decoding="async" fetchpriority="high"$homeVisualDimensions>
              </div>
              <figcaption class="home-visual-note">
                <span class="home-visual-chip">Setup d&eacute;butant</span>
                <p>Un coin lumineux, compact et propre pour lancer laitues, basilic et autres cultures faciles en hydroponie appartement.</p>
              </figcaption>
            </figure>
          </aside>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading" data-reveal>
            <div>
              <h2>Commencer l'hydroponie en appartement</h2>
              <p>Trois portes d'entr&eacute;e simples pour avancer sans jargon ni sur&eacute;quipement.</p>
            </div>
          </div>
          <div class="home-path-grid" data-reveal-group>
$startHtml
          </div>
        </div>
      </section>

      <section class="section section-soft">
        <div class="section-inner">
          <div class="section-heading" data-reveal>
            <div>
              <h2>Explorer les grands th&egrave;mes HydroFacile</h2>
              <p>Une structure claire pour retrouver vite la bonne info selon ton niveau et ton installation.</p>
            </div>
          </div>
          <div class="theme-grid">
$themeHtml
          </div>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading" data-reveal>
            <div>
              <h2>Guide recommand&eacute; maintenant</h2>
              <p>Le meilleur point d'entr&eacute;e pour construire une base hydroponie simple et coh&eacute;rente.</p>
            </div>
          </div>
          <div class="editorial-grid">
            <article class="editorial-feature" id="weekly-feature" data-reveal>
              <img id="weekly-feature-image" src="$weeklyFeatureImageSrc" alt="$(HtmlEscape $weeklyFeatureImageAlt)" title="$(HtmlEscape $weeklyFeatureImageAlt)" loading="lazy" decoding="async"$weeklyFeatureImageDimensions>
              <div class="editorial-feature-body">
                <span class="pill" id="weekly-feature-category">$(HtmlEscape $weeklyFeatureCategory)</span>
                <h3><a id="weekly-feature-title" href="$weeklyFeatureHref">$(HtmlEscape $weeklyFeatureTitle)</a></h3>
                <p id="weekly-feature-description">$(HtmlEscape $weeklyFeatureDescription)</p>
                <a class="text-link" id="weekly-feature-link" href="$weeklyFeatureHref">Lire l'article</a>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="cta-strip" data-reveal>
            <div>
              <h2 class="page-title">Construire une base solide</h2>
              <p class="page-intro">
                Mat&eacute;riel, cultures faciles, calendrier et rep&egrave;res d&eacute;butant :
                retrouve les contenus essentiels pour lancer un potager int&eacute;rieur hydroponique simple &agrave; vivre.
              </p>
            </div>
            <a class="button" href="articles/">Voir tous les articles</a>
          </div>
        </div>
      </section>
    </main>

$(Get-SiteFooterHtml -pagePrefix "")
  </div>
  <script>
    (() => {
      const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));

      if (!reduceMotion) {
        document.body.classList.add("home-reveal-ready");
        document.body.classList.add("reveal-ready");

        if ("IntersectionObserver" in window) {
          const revealObserver = new IntersectionObserver((entries, observer) => {
            entries.forEach((entry) => {
              if (!entry.isIntersecting) {
                return;
              }

              entry.target.classList.add("is-visible");
              observer.unobserve(entry.target);
            });
          }, {
            threshold: 0.18,
            rootMargin: "0px 0px -8% 0px"
          });

          revealItems.forEach((item) => revealObserver.observe(item));
        } else {
          revealItems.forEach((item) => item.classList.add("is-visible"));
        }
      } else {
        revealItems.forEach((item) => item.classList.add("is-visible"));
      }

      const weeklyArticles = $weeklyArticlesJson;
      if (!Array.isArray(weeklyArticles) || !weeklyArticles.length) {
        return;
      }

      const weeklyImage = document.getElementById("weekly-feature-image");
      const weeklyCategory = document.getElementById("weekly-feature-category");
      const weeklyTitle = document.getElementById("weekly-feature-title");
      const weeklyDescription = document.getElementById("weekly-feature-description");
      const weeklyLink = document.getElementById("weekly-feature-link");

      if (!weeklyImage || !weeklyCategory || !weeklyTitle || !weeklyDescription || !weeklyLink) {
        return;
      }

      const slugKeywords = {
        spring: ["printemps", "semis", "laitue", "laitues", "radis", "epinard", "epinards", "fraise", "fraises", "aromatiques", "calendrier"],
        summer: ["ete", "chaleur", "canicule", "tomate", "tomates", "poivron", "poivrons", "arrosage", "soleil", "eau"],
        autumn: ["automne", "compost", "paillage", "bulbes", "proteger", "recolte", "nuisibles", "pluie"],
        winter: ["hiver", "materiel", "planifier", "preparer", "lunaire", "interieur", "structure"]
      };

      const monthKeywords = {
        1: ["materiel", "planifier", "lunaire", "compost"],
        2: ["semis", "aromatiques", "laitue", "laitues"],
        3: ["semis", "radis", "laitue", "laitues", "fraise", "fraises"],
        4: ["tomate", "tomates", "radis", "fraises", "potager"],
        5: ["tomate", "tomates", "poivron", "poivrons", "aromatiques", "grimpantes"],
        6: ["canicule", "eau", "paillage", "poivrons", "tomates"],
        7: ["canicule", "soleil", "arrosage", "eau", "pollinisateurs"],
        8: ["canicule", "arrosage", "nuisibles", "eau", "recolte"],
        9: ["recolte", "compost", "petits-fruits", "potager"],
        10: ["compost", "paillage", "bulbes", "pluie"],
        11: ["compost", "materiel", "preparer", "structure"],
        12: ["materiel", "planifier", "lunaire", "durable"]
      };

      const now = new Date();
      const month = now.getMonth() + 1;
      const season = getSeason(month);
      const isoWeek = getIsoWeekNumber(now);
      const weekKey = now.getFullYear() + "-" + String(isoWeek).padStart(2, "0");

      const ranked = weeklyArticles
        .map((article) => ({
          article,
          score: getArticleScore(article, season, month)
        }))
        .sort((left, right) => {
          if (right.score !== left.score) {
            return right.score - left.score;
          }

          return new Date(right.article.datePublished || 0) - new Date(left.article.datePublished || 0);
        });

      const shortlist = ranked.slice(0, Math.min(6, ranked.length));
      const chosen = shortlist[hashString(weekKey) % shortlist.length].article;

      weeklyImage.src = chosen.imageSrc || weeklyImage.src;
      weeklyImage.alt = chosen.imageAlt || chosen.title || weeklyImage.alt;
      weeklyImage.title = chosen.imageAlt || chosen.title || weeklyImage.title;

      if (chosen.width) {
        weeklyImage.width = chosen.width;
      }

      if (chosen.height) {
        weeklyImage.height = chosen.height;
      }

      weeklyCategory.textContent = chosen.category || weeklyCategory.textContent;
      weeklyTitle.textContent = chosen.title || weeklyTitle.textContent;
      weeklyTitle.href = chosen.href || weeklyTitle.href;
      weeklyDescription.textContent = truncate(chosen.description || weeklyDescription.textContent, 178);
      weeklyLink.href = chosen.href || weeklyLink.href;

      function getSeason(currentMonth) {
        if (currentMonth >= 3 && currentMonth <= 5) {
          return "spring";
        }

        if (currentMonth >= 6 && currentMonth <= 8) {
          return "summer";
        }

        if (currentMonth >= 9 && currentMonth <= 11) {
          return "autumn";
        }

        return "winter";
      }

      function getIsoWeekNumber(date) {
        const utcDate = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const day = utcDate.getUTCDay() || 7;
        utcDate.setUTCDate(utcDate.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(utcDate.getUTCFullYear(), 0, 1));
        return Math.ceil((((utcDate - yearStart) / 86400000) + 1) / 7);
      }

      function getArticleScore(article, currentSeason, currentMonth) {
        const haystack = [article.slug || "", article.title || "", article.description || "", article.category || ""].join(" ").toLowerCase();
        let score = 0;

        (slugKeywords[currentSeason] || []).forEach((keyword) => {
          if (haystack.includes(keyword)) {
            score += 4;
          }
        });

        (monthKeywords[currentMonth] || []).forEach((keyword) => {
          if (haystack.includes(keyword)) {
            score += 3;
          }
        });

        const publishedAt = Date.parse(article.datePublished || "");
        if (!Number.isNaN(publishedAt)) {
          const ageInDays = Math.max(0, (Date.now() - publishedAt) / 86400000);
          score += Math.max(0, 6 - Math.floor(ageInDays / 120));
        }

        if (/guide|calendrier|hydro|culture|debut/i.test(haystack)) {
          score += 1;
        }

        return score;
      }

      function truncate(text, maxLength) {
        if (!text || text.length <= maxLength) {
          return text;
        }

        return text.slice(0, maxLength - 1).trimEnd() + "…";
      }

      function hashString(value) {
        return Array.from(value).reduce((hash, character) => ((hash * 31) + character.charCodeAt(0)) >>> 0, 7);
      }
    })();
  </script>
</body>
</html>
"@
}

function Build-ArticlesIndexHtml {
  param([object[]]$allArticles)

  if ($allArticles.Count -eq 0) {
    $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
    $tagManagerHead = Get-TagManagerHeadHtml
    $tagManagerBody = Get-TagManagerBodyHtml
    $jsonLd = Get-JsonLdScriptTags @([ordered]@{
        "@context" = "https://schema.org"
        "@type" = "CollectionPage"
      name = "Guides hydroponie appartement | $siteName"
        url = "$siteUrl/articles/"
        inLanguage = "fr"
        description = "HydroFacile prépare une base de guides pour débuter en hydroponie en appartement, choisir un système simple et lancer des cultures faciles en intérieur."
        isPartOf = [ordered]@{
          "@type" = "WebSite"
          name = $siteName
          url = "$siteUrl/"
        }
      })

    return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Guides hydroponie appartement | $siteName</title>
  <meta name="description" content="HydroFacile prépare une base de guides pour débuter en hydroponie en appartement, choisir un système simple et lancer des cultures faciles en intérieur.">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <link rel="canonical" href="$siteUrl/articles/">
  <link rel="alternate" hreflang="fr" href="$siteUrl/articles/">
  <link rel="alternate" hreflang="x-default" href="$siteUrl/articles/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Guides hydroponie appartement | $siteName">
  <meta property="og:description" content="HydroFacile prépare une base de guides pour débuter en hydroponie en appartement, choisir un système simple et lancer des cultures faciles en intérieur.">
  <meta property="og:url" content="$siteUrl/articles/">
  <meta property="og:image" content="$siteUrl/images/articles/hydro-systeme-debutant.svg">
  <meta property="og:image:alt" content="Petite installation hydroponique propre en intérieur">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Guides hydroponie appartement | $siteName">
  <meta name="twitter:description" content="HydroFacile prépare une base de guides pour débuter en hydroponie en appartement, choisir un système simple et lancer des cultures faciles en intérieur.">
  <meta name="twitter:image" content="$siteUrl/images/articles/hydro-systeme-debutant.svg">
  <meta name="twitter:image:alt" content="Petite installation hydroponique propre en intérieur">
$jsonLd
$tagManagerHead
  <link rel="icon" href="../images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="../images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="manifest" href="../site.webmanifest">
  <link rel="stylesheet" href="$articleStylesheetHref">
</head>
<body class="articles-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../">Accueil</a>
            <a href="./" aria-current="page">Articles</a>
            <a href="../contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="section">
      <div class="section-inner">
        <div class="page-hero" data-reveal>
          <div class="page-hero-copy">
            <h1 class="page-title">Guides hydroponie pour débuter en appartement</h1>
            <p class="page-intro">
              Cette section rassemblera des contenus simples pour comprendre la culture sans terre, choisir un petit système et débuter avec des plantes faciles, même dans peu d'espace.
            </p>
          </div>
        </div>

        <section class="search-panel" data-reveal style="--reveal-delay: 60ms;">
          <strong class="search-label">Bientôt ici</strong>
          <p class="page-intro">Des guides pratiques sur le fonctionnement de l'hydroponie, le matériel vraiment utile, la lumière, les nutriments expliqués simplement et les cultures les plus faciles pour commencer.</p>
          <div class="hero-actions">
            <a class="button" href="../contact/">Contacter HydroFacile</a>
            <a class="button-secondary" href="../">Retour a l'accueil</a>
          </div>
        </section>
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "../")
  </div>
</body>
</html>
"@
  }

  $cardsHtml = (($allArticles | ForEach-Object -Begin { $cardIndex = 0 } -Process {
        $delay = [Math]::Min(70 + ($cardIndex * 45), 520)
        $cardIndex++
        (Build-ArticleCardHtml -article $_ -hrefPrefix "" -imagePrefix "../images/articles/") -replace '<article class="article-card">', "<article class=`"article-card`" data-reveal style=`"--reveal-delay: ${delay}ms;`">"
      }) -join "`n")
  $count = $allArticles.Count
  $heroImage = if ($allArticles.Count -gt 0) { $allArticles[0].ImageCanonicalUrl } else { "" }
  $heroImageAlt = if ($allArticles.Count -gt 0) { $allArticles[0].ImageAlt } else { "Guides HydroFacile pour débuter en hydroponie en appartement" }
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $jsonLd = Get-JsonLdScriptTags @([ordered]@{
      "@context" = "https://schema.org"
      "@type" = "CollectionPage"
      name = "Guides hydroponie appartement | $siteName"
      url = "$siteUrl/articles/"
      inLanguage = "fr"
      description = "Retrouve les guides HydroFacile pour débuter en hydroponie en appartement : système simple, cultures faciles, lumière, nutriments et potager intérieur hydroponique."
      isPartOf = [ordered]@{
        "@type" = "WebSite"
        name = $siteName
        url = "$siteUrl/"
      }
    })

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Guides hydroponie appartement | $siteName</title>
  <meta name="description" content="Retrouve les guides HydroFacile pour débuter en hydroponie en appartement : système simple, cultures faciles, lumière, nutriments et potager intérieur hydroponique.">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <link rel="canonical" href="$siteUrl/articles/">
  <link rel="alternate" hreflang="fr" href="$siteUrl/articles/">
  <link rel="alternate" hreflang="x-default" href="$siteUrl/articles/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Guides hydroponie appartement | $siteName">
  <meta property="og:description" content="Retrouve les guides HydroFacile pour débuter en hydroponie en appartement : système simple, cultures faciles, lumière, nutriments et potager intérieur hydroponique.">
  <meta property="og:url" content="$siteUrl/articles/">
  <meta property="og:image" content="$heroImage">
  <meta property="og:image:alt" content="$(HtmlEscape $heroImageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Guides hydroponie appartement | $siteName">
  <meta name="twitter:description" content="Retrouve les guides HydroFacile pour débuter en hydroponie en appartement : système simple, cultures faciles, lumière, nutriments et potager intérieur hydroponique.">
  <meta name="twitter:image" content="$heroImage">
  <meta name="twitter:image:alt" content="$(HtmlEscape $heroImageAlt)">
$jsonLd
$tagManagerHead
  <link rel="icon" href="../images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="../images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="manifest" href="../site.webmanifest">
  <link rel="stylesheet" href="$articleStylesheetHref">
</head>
<body class="articles-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../">Accueil</a>
            <a href="./" aria-current="page">Articles</a>
            <a href="../contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="section">
      <div class="section-inner">
        <div class="page-hero" data-reveal>
          <div class="page-hero-copy">
            <h1 class="page-title">Guides hydroponie pour d&eacute;buter en appartement</h1>
            <p class="page-intro">
              Une base claire pour comprendre la culture hydroponique facile, choisir un syst&egrave;me hydroponique d&eacute;butant et r&eacute;ussir un potager int&eacute;rieur hydroponique simple &agrave; maintenir.
            </p>
          </div>

          <section class="search-panel search-panel-compact" aria-label="Recherche d'articles" data-reveal style="--reveal-delay: 60ms;">
            <label class="search-label sr-only" for="article-search">Rechercher un article</label>
            <input
              class="search-input"
              id="article-search"
              type="search"
              name="q"
              placeholder="Rechercher un guide hydroponie"
              autocomplete="off">
          </section>
        </div>

        <section class="theme-filter-panel" aria-label="Filtrer les articles par thème" data-reveal style="--reveal-delay: 110ms;">
          <div class="theme-filter-list" id="article-theme-filters"></div>
        </section>

        <p class="search-empty" id="search-empty" hidden>Aucun article ne correspond &agrave; cette recherche.</p>

        <div class="cards" id="article-list">
$cardsHtml
        </div>

        <div class="article-list-actions" id="article-list-actions" hidden>
          <button class="button-secondary article-list-toggle" id="article-list-toggle" type="button" aria-controls="article-list" aria-expanded="false">
            Voir plus
          </button>
        </div>
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "../")
  </div>
  <script>
    (() => {
      const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      const revealItems = Array.from(document.querySelectorAll("[data-reveal]"));
      const searchInput = document.getElementById("article-search");
      const articleCards = Array.from(document.querySelectorAll("#article-list .article-card"));
      const themeFilterList = document.getElementById("article-theme-filters");
      const articleListActions = document.getElementById("article-list-actions");
      const articleListToggle = document.getElementById("article-list-toggle");
      const emptyState = document.getElementById("search-empty");
      const currentUrl = new URL(window.location.href);
      const currentHashParams = new URLSearchParams(currentUrl.hash.startsWith("#") ? currentUrl.hash.slice(1) : "");
      const currentPath = currentUrl.pathname;
      const previewRowStep = 2;
      let visibleRowCount = previewRowStep;
      let articleListFullyRevealed = false;
      let previewRefreshFrame = 0;
      let activeTheme = "all";

      const initReveal = () => {
        if (!revealItems.length) {
          return;
        }

        if (reduceMotion) {
          revealItems.forEach((item) => item.classList.add("is-visible"));
          return;
        }

        document.body.classList.add("reveal-ready");

        if (!("IntersectionObserver" in window)) {
          revealItems.forEach((item) => item.classList.add("is-visible"));
          return;
        }

        const observer = new IntersectionObserver((entries) => {
          entries.forEach((entry) => {
            if (!entry.isIntersecting) {
              return;
            }

            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          });
        }, {
          rootMargin: "0px 0px -8% 0px",
          threshold: 0.12
        });

        revealItems.forEach((item) => observer.observe(item));
      };

      const normalizeText = (value) =>
        value
          .toLowerCase()
          .normalize("NFD")
          .replace(/[\u0300-\u036f]/g, "");

      const slugifyTheme = (value) =>
        normalizeText(value)
          .replace(/[^a-z0-9]+/g, "-")
          .replace(/^-+|-+$/g, "");

      const getSearchTokens = (value) =>
        normalizeText(value)
          .split(/\s+/)
          .filter(Boolean);

      const getCardThemeLabel = (card) => {
        const themePill = card.querySelector(".pill");
        return themePill ? themePill.textContent.trim() : "";
      };

      const getCardTitleText = (card) => {
        const titleLink = card.querySelector("h3 a");
        return titleLink ? normalizeText(titleLink.textContent) : "";
      };

      const resetArticlePreview = () => {
        visibleRowCount = previewRowStep;
        articleListFullyRevealed = false;
      };

      const articleThemeOptions = [
        { slug: "all", label: "Tous" }
      ];

      articleCards.forEach((card) => {
        const themeLabel = getCardThemeLabel(card);
        const themeSlug = slugifyTheme(themeLabel);
        const themePill = card.querySelector(".pill");

        if (themeSlug === "") {
          return;
        }

        card.dataset.theme = themeSlug;

        if (!articleThemeOptions.some((option) => option.slug === themeSlug)) {
          articleThemeOptions.push({
            slug: themeSlug,
            label: themeLabel
          });
        }

        if (themePill) {
          themePill.dataset.themeFilter = themeSlug;
          themePill.classList.add("pill-filter-trigger");
          themePill.setAttribute("role", "button");
          themePill.tabIndex = 0;
          themePill.setAttribute("aria-label", "Afficher les articles du thème " + themeLabel);
        }
      });

      const themeButtonsBySlug = new Map();

      articleThemeOptions.forEach((themeOption) => {
        const themeButton = document.createElement("button");
        themeButton.type = "button";
        themeButton.className = "theme-filter-button";
        themeButton.dataset.themeFilter = themeOption.slug;
        themeButton.textContent = themeOption.label;
        themeButton.setAttribute("aria-pressed", "false");
        themeFilterList.appendChild(themeButton);
        themeButtonsBySlug.set(themeOption.slug, themeButton);
      });

      const themeFilterButtons = Array.from(themeButtonsBySlug.values());

      const updateThemeFilterButtons = () => {
        themeFilterButtons.forEach((button) => {
          const isActive = button.dataset.themeFilter === activeTheme;
          button.classList.toggle("is-active", isActive);
          button.setAttribute("aria-pressed", String(isActive));
        });
      };

      const getMatchedCards = () => articleCards.filter((card) => !card.hidden);

      const updateArticlePreview = () => {
        const matchedCards = getMatchedCards();
        const hasSearchQuery = searchInput.value.trim() !== "";
        let rowIndex = 0;
        let lastRowTop = null;
        let hiddenCount = 0;

        articleCards.forEach((card) => {
          card.classList.remove("article-card-collapsed");
        });

        if (matchedCards.length === 0 || articleListFullyRevealed || hasSearchQuery) {
          articleListActions.hidden = true;
          articleListToggle.setAttribute("aria-expanded", String(articleListFullyRevealed || hasSearchQuery));
          return;
        }

        matchedCards.forEach((card) => {
          const cardTop = Math.round(card.offsetTop);

          if (lastRowTop === null || Math.abs(cardTop - lastRowTop) > 1) {
            rowIndex += 1;
            lastRowTop = cardTop;
          }

          const shouldCollapse = rowIndex > visibleRowCount;
          card.classList.toggle("article-card-collapsed", shouldCollapse);

          if (shouldCollapse) {
            hiddenCount += 1;
          }
        });

        articleListFullyRevealed = hiddenCount === 0;
        articleListActions.hidden = articleListFullyRevealed;
        articleListToggle.setAttribute("aria-expanded", String(articleListFullyRevealed));
      };

      const requestArticlePreviewRefresh = () => {
        if (previewRefreshFrame !== 0) {
          window.cancelAnimationFrame(previewRefreshFrame);
        }

        previewRefreshFrame = window.requestAnimationFrame(() => {
          previewRefreshFrame = 0;
          updateArticlePreview();
        });
      };

      const syncFilterParams = () => {
        const rawQuery = searchInput.value.trim();
        const nextHashParams = new URLSearchParams();

        if (rawQuery !== "") {
          nextHashParams.set("q", rawQuery);
        }

        if (activeTheme !== "all") {
          nextHashParams.set("theme", activeTheme);
        }

        const nextHash = nextHashParams.toString();
        window.history.replaceState({}, "", currentPath + (nextHash ? "#" + nextHash : ""));
      };

      const filterArticles = () => {
        const queryTokens = getSearchTokens(searchInput.value.trim());
        let visibleCount = 0;

        articleCards.forEach((card) => {
          const searchableTitle = getCardTitleText(card);
          const matchesTheme = activeTheme === "all" || card.dataset.theme === activeTheme;
          const matchesQuery = queryTokens.length === 0 || queryTokens.every((token) => searchableTitle.includes(token));
          const matches = matchesTheme && matchesQuery;
          card.hidden = !matches;

          if (matches) {
            visibleCount += 1;
          }
        });

        emptyState.hidden = visibleCount !== 0;
        requestArticlePreviewRefresh();
      };

      const applyThemeFilter = (themeSlug) => {
        if (!themeButtonsBySlug.has(themeSlug)) {
          return;
        }

        activeTheme = themeSlug;
        resetArticlePreview();
        updateThemeFilterButtons();
        filterArticles();
        syncFilterParams();
      };

      const initialQuery = currentHashParams.get("q");
      const initialTheme = currentHashParams.get("theme");

      if (initialQuery) {
        searchInput.value = initialQuery;
      }

      if (initialTheme && themeButtonsBySlug.has(initialTheme)) {
        activeTheme = initialTheme;
      }

      updateThemeFilterButtons();
      filterArticles();
      initReveal();

      searchInput.addEventListener("input", () => {
        resetArticlePreview();
        filterArticles();
        syncFilterParams();
      });

      themeFilterList.addEventListener("click", (event) => {
        const targetButton = event.target.closest("[data-theme-filter]");

        if (!targetButton) {
          return;
        }

        applyThemeFilter(targetButton.dataset.themeFilter);
      });

      document.addEventListener("click", (event) => {
        const targetPill = event.target.closest("#article-list .pill-filter-trigger");

        if (!targetPill) {
          return;
        }

        applyThemeFilter(targetPill.dataset.themeFilter);
      });

      document.addEventListener("keydown", (event) => {
        const targetPill = event.target.closest("#article-list .pill-filter-trigger");

        if (!targetPill || (event.key !== "Enter" && event.key !== " ")) {
          return;
        }

        event.preventDefault();
        applyThemeFilter(targetPill.dataset.themeFilter);
      });

      articleListToggle.addEventListener("click", () => {
        visibleRowCount += previewRowStep;
        requestArticlePreviewRefresh();
      });

      window.addEventListener("resize", requestArticlePreviewRefresh);
      window.addEventListener("load", requestArticlePreviewRefresh, { once: true });
    })();
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

function Build-PrivacyPageHtml {
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $canonicalUrl = "$siteUrl/politique-confidentialite/"

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Politique de confidentialit&eacute; | $siteName</title>
  <meta name="description" content="Informations sur la mesure d'audience, les cookies et le formulaire de contact utilisés sur $siteName.">
  <meta name="robots" content="noindex,nofollow">
  <link rel="canonical" href="$canonicalUrl">
  <link rel="alternate" hreflang="fr" href="$canonicalUrl">
  <link rel="alternate" hreflang="x-default" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Politique de confidentialit&eacute; | $siteName">
  <meta property="og:description" content="Informations sur la mesure d'audience, les cookies et le formulaire de contact utilisés sur $siteName.">
  <meta property="og:url" content="$canonicalUrl">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Politique de confidentialit&eacute; | $siteName">
  <meta name="twitter:description" content="Informations sur la mesure d'audience, les cookies et le formulaire de contact utilisés sur $siteName.">
$tagManagerHead
  <link rel="icon" href="../images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="../images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="manifest" href="../site.webmanifest">
  <link rel="stylesheet" href="../css/style.min.css">
</head>
<body class="legal-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../">Accueil</a>
            <a href="../articles/">Articles</a>
            <a href="../contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="article-layout">
      <div class="article-shell">
        <div>
          <nav class="breadcrumb-nav" aria-label="fil d'ariane">
            <ol class="breadcrumb">
              <li><a href="../">Accueil</a></li>
              <li aria-current="page">Politique de confidentialit&eacute;</li>
            </ol>
          </nav>
        </div>

        <section class="page-hero">
          <div class="page-hero-copy">
            <span class="eyebrow">Confidentialit&eacute;</span>
            <h1 class="page-title">Politique de confidentialit&eacute;</h1>
            <p class="page-intro">
              Cette page r&eacute;sume les informations utiles sur le formulaire de contact, les donn&eacute;es techniques
              et les services tiers susceptibles d'&ecirc;tre impliqu&eacute;s lorsque tu consultes $siteName.
            </p>
          </div>

          <aside class="checklist utility-panel">
            <h2>En bref</h2>
            <ul class="article-list">
              <li>$siteName est un site &eacute;ditorial autour de l'hydroponie pour d&eacute;butants en appartement.</li>
              <li>Le site ne charge pas actuellement d'outil de mesure d'audience ni de suivi publicitaire.</li>
              <li>Le formulaire de contact transmet les messages via FormSubmit vers l'adresse de contact du site.</li>
              <li>Les liens sortants et services tiers &eacute;ventuels suivent leurs propres r&egrave;gles.</li>
            </ul>
          </aside>
        </section>

        <article class="article-prose">
          <h2>Donn&eacute;es de navigation</h2>
          <p>
            Lorsque tu visites $siteName, des informations techniques usuelles peuvent &ecirc;tre trait&eacute;es&nbsp;:
            pages consult&eacute;es, date et heure de visite, appareil, navigateur, langue, provenance de la visite ou
            donn&eacute;es de performance. Elles servent surtout &agrave; comprendre l'usage du site et &agrave; l'am&eacute;liorer.
          </p>

          <h2>Mesure d'audience</h2>
          <p>
            Aucun outil de mesure d'audience ou de suivi marketing n'est actuellement charg&eacute; sur $siteName.
            Si cela change plus tard, cette page sera mise &agrave; jour pour d&eacute;crire les services concern&eacute;s.
          </p>

          <h2>Cookies et technologies proches</h2>
          <p>
            Le site peut utiliser des cookies strictement n&eacute;cessaires &agrave; son fonctionnement ou &agrave; certains services tiers.
            Leur pr&eacute;sence d&eacute;pend notamment de ton navigateur, de l'h&eacute;bergement et des services effectivement utilis&eacute;s.
          </p>

          <h2>Formulaire de contact</h2>
          <p>
            Lorsque tu utilises la page contact, les donn&eacute;es saisies dans le formulaire comme le nom, l'adresse email,
            l'objet et le message sont transmises &agrave; FormSubmit, le service utilis&eacute; pour acheminer les demandes vers
            l'adresse de contact de $siteName.
          </p>

          <h2>Liens et services tiers</h2>
          <p>
            Le site peut proposer des liens vers des plateformes ou services externes. Lorsque tu quittes $siteName
            ou que tu utilises un service tiers comme FormSubmit, leurs propres politiques de confidentialit&eacute; peuvent aussi s'appliquer.
          </p>

          <h2>&Eacute;volution de cette page</h2>
          <p>
            Cette page pourra &ecirc;tre mise &agrave; jour si le site ajoute de nouveaux outils, de nouveaux formulaires
            ou d'autres services tiers. La version affich&eacute;e ici est celle qui fait foi sur le site publi&eacute;.
          </p>
        </article>
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "../")
  </div>
</body>
</html>
"@
}

function Build-ContactPageHtml {
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $canonicalUrl = "$siteUrl/contact/"
  $contactThanksUrl = "$siteUrl/contact/merci/"

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Contact | $siteName</title>
  <meta name="description" content="Pose une question à $siteName via un formulaire simple directement depuis le site.">
  <meta name="robots" content="index,follow">
  <link rel="canonical" href="$canonicalUrl">
  <link rel="alternate" hreflang="fr" href="$canonicalUrl">
  <link rel="alternate" hreflang="x-default" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Contact | $siteName">
  <meta property="og:description" content="Pose une question à $siteName via un formulaire simple directement depuis le site.">
  <meta property="og:url" content="$canonicalUrl">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Contact | $siteName">
  <meta name="twitter:description" content="Pose une question à $siteName via un formulaire simple directement depuis le site.">
$tagManagerHead
  <link rel="icon" href="../images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="../images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="manifest" href="../site.webmanifest">
  <link rel="stylesheet" href="../css/style.min.css">
</head>
<body class="contact-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../">Accueil</a>
            <a href="../articles/">Articles</a>
            <a href="./" aria-current="page">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="article-layout">
      <div class="article-shell">
        <div>
          <nav class="breadcrumb-nav" aria-label="fil d'ariane">
            <ol class="breadcrumb">
              <li><a href="../">Accueil</a></li>
              <li aria-current="page">Contact</li>
            </ol>
          </nav>
        </div>

        <section class="page-hero">
          <div class="page-hero-copy">
            <h1 class="page-title">Poser une question simplement</h1>
            <p class="page-intro">
              Une question sur un guide, un doute sur ton installation ou une suggestion de sujet ? Le formulaire ci-dessous permet d'envoyer un message directement depuis le site.
            </p>
            <p class="page-intro">Les messages sont transmis à l'adresse de contact du site via FormSubmit.</p>
          </div>

          <aside class="checklist utility-panel">
            <h2>Dans ton message</h2>
            <ul class="article-list">
              <li>Ajoute le lien du guide concerné si ta question porte sur un article précis.</li>
              <li>Indique ton espace, ta lumière et le type de système si tu bloques sur un setup.</li>
              <li>Précise si c'est une question, une suggestion ou une correction.</li>
            </ul>
          </aside>
        </section>

        <section class="card contact-card">
          <div class="card-body">
            <form class="contact-form" action="$siteContactFormAction" method="POST" accept-charset="UTF-8">
              <input type="hidden" id="contact-next" name="_next" value="$contactThanksUrl">
              <input type="hidden" name="_subject" value="Nouveau message depuis HydroFacile">
              <input type="hidden" name="_template" value="table">
              <input type="hidden" id="contact-url" name="_url" value="$canonicalUrl">

              <label class="form-honeypot" for="contact-company">Ne pas remplir ce champ</label>
              <input class="form-honeypot" id="contact-company" type="text" name="_honey" tabindex="-1" autocomplete="off">

              <div class="contact-form-grid">
                <div class="form-field">
                  <label for="contact-name">Nom</label>
                  <input id="contact-name" type="text" name="name" autocomplete="name" required>
                </div>

                <div class="form-field">
                  <label for="contact-email">Email</label>
                  <input id="contact-email" type="email" name="email" autocomplete="email" required>
                </div>

                <div class="form-field form-field-full">
                  <label for="contact-topic">Objet</label>
                  <input id="contact-topic" type="text" name="topic" autocomplete="off" placeholder="Exemple : question sur un système débutant">
                </div>

                <div class="form-field form-field-full">
                  <label for="contact-message">Message</label>
                  <textarea id="contact-message" name="message" placeholder="Décris ta question ou ton besoin en quelques lignes." required></textarea>
                </div>
              </div>

              <div class="hero-actions">
                <button class="button" type="submit">Envoyer le message</button>
              </div>
              <p class="form-helper">Après envoi, tu seras redirigé vers une page de confirmation sur le site.</p>
            </form>
          </div>
        </section>
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "../")
  </div>
  <script>
    (() => {
      const nextInput = document.getElementById("contact-next");
      const urlInput = document.getElementById("contact-url");

      if (!nextInput || !urlInput) {
        return;
      }

      if (!/^https?:$/i.test(window.location.protocol)) {
        return;
      }

      const currentUrl = new URL(window.location.href);
      currentUrl.search = "";
      currentUrl.hash = "";

      const thanksUrl = new URL("./merci/", currentUrl.href);

      nextInput.value = thanksUrl.href;
      urlInput.value = currentUrl.href;
    })();
  </script>
</body>
</html>
"@
}

function Build-ContactThanksPageHtml {
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $canonicalUrl = "$siteUrl/contact/merci/"

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Message envoy&eacute; | $siteName</title>
  <meta name="description" content="Confirmation d'envoi du formulaire de contact $siteName.">
  <meta name="robots" content="noindex,nofollow">
  <link rel="canonical" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Message envoy&eacute; | $siteName">
  <meta property="og:description" content="Confirmation d'envoi du formulaire de contact $siteName.">
  <meta property="og:url" content="$canonicalUrl">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Message envoy&eacute; | $siteName">
  <meta name="twitter:description" content="Confirmation d'envoi du formulaire de contact $siteName.">
$tagManagerHead
  <link rel="icon" href="../../images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="../../images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="../../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../../images/apple-touch-icon.png">
  <link rel="manifest" href="../../site.webmanifest">
  <link rel="stylesheet" href="../../css/style.min.css">
</head>
<body class="contact-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../../">
          <span class="brand-mark">
            <img class="brand-logo" src="../../images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../../">Accueil</a>
            <a href="../../articles/">Articles</a>
            <a href="../../contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="article-layout">
      <div class="article-shell">
        <section class="page-hero">
          <div class="page-hero-copy">
            <span class="eyebrow">Message envoy&eacute;</span>
            <h1 class="page-title">Merci, ton message a bien &eacute;t&eacute; transmis.</h1>
            <p class="page-intro">
              Nous avons bien re&ccedil;u ta demande via le formulaire de contact. Tu peux revenir aux guides ou envoyer un autre message si besoin.
            </p>
            <div class="hero-actions">
              <a class="button" href="../../contact/">Retour au contact</a>
              <a class="button-secondary" href="../../articles/">Voir les guides</a>
            </div>
          </div>

          <aside class="checklist utility-panel">
            <h2>Bon à savoir</h2>
            <ul class="article-list">
              <li>Si tu n'as pas tout dit, tu peux renvoyer un message depuis la page contact.</li>
              <li>Les guides HydroFacile restent disponibles pendant l'attente d'une réponse.</li>
            </ul>
          </aside>
        </section>
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "../../")
  </div>
</body>
</html>
"@
}

function Build-404Html {
  $logoDimensions = Get-RootImageDimensionAttributes $siteLogoPath
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $canonicalUrl = "$siteUrl/404.html"

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Page introuvable | $siteName</title>
  <meta name="description" content="La page demand&eacute;e n'est pas disponible. Repars depuis l'accueil $siteName, la page contact ou la section guides.">
  <meta name="robots" content="noindex,follow">
  <link rel="canonical" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="$siteName">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Page introuvable | $siteName">
  <meta property="og:description" content="La page demand&eacute;e n'est pas disponible. Repars depuis l'accueil $siteName, la page contact ou la section guides.">
  <meta property="og:url" content="$canonicalUrl">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Page introuvable | $siteName">
  <meta name="twitter:description" content="La page demand&eacute;e n'est pas disponible. Repars depuis l'accueil $siteName, la page contact ou la section guides.">
$tagManagerHead
  <link rel="icon" href="images/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="16x16" href="images/favicon-16.png">
  <link rel="icon" type="image/png" sizes="32x32" href="images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="images/apple-touch-icon.png">
  <link rel="manifest" href="site.webmanifest">
  <link rel="stylesheet" href="$rootStylesheetHref">
</head>
<body class="not-found-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="./">
          <span class="brand-mark">
            <img class="brand-logo" src="images/logo-site.png" alt="Logo $siteName"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="./">Accueil</a>
            <a href="articles/">Articles</a>
            <a href="contact/">Contact</a>
          </nav>
        </div>
      </div>
    </header>

    <main class="section">
      <div class="section-inner">
        <section class="page-hero">
          <div class="page-hero-copy">
            <span class="eyebrow">404</span>
            <h1 class="page-title">Page introuvable</h1>
            <p class="page-intro">
              Cette adresse ne m&egrave;ne &agrave; aucune page disponible. Tu peux revenir &agrave; l'accueil, ouvrir la page contact
              ou passer par la section guides pour repartir simplement.
            </p>
            <div class="hero-actions">
              <a class="button" href="./">Retour &agrave; l'accueil</a>
              <a class="button-secondary" href="articles/">Voir les guides</a>
            </div>
          </div>

          <aside class="checklist utility-panel">
            <h2>Tu peux essayer</h2>
            <ul class="article-list">
              <li>Revenir &agrave; l'accueil pour retrouver les bases de l'hydroponie en appartement.</li>
              <li>Ouvrir la page contact pour signaler un besoin, une suggestion ou une erreur sur le site.</li>
              <li>Passer par la section guides pour suivre l'arriv&eacute;e des prochains contenus.</li>
            </ul>
            <a class="text-link" href="contact/">Ouvrir le contact</a>
          </aside>
        </section>
      </div>
    </main>

$(Get-SiteFooterHtml -pagePrefix "")
  </div>
</body>
</html>
"@
}

function Build-SitemapXml {
  param([object[]]$allArticles)

  $today = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
  $entries = New-Object System.Collections.Generic.List[string]

  function New-SitemapImageNode {
    param(
      [string]$imageUrl,
      [string]$caption
    )

    if ([string]::IsNullOrWhiteSpace($imageUrl)) {
      return ""
    }

    $captionNode = if ([string]::IsNullOrWhiteSpace($caption)) {
      ""
    } else {
      "<image:caption>$(Escape-Xml $caption)</image:caption>"
    }

    return "<image:image><image:loc>$(Escape-Xml $imageUrl)</image:loc>$captionNode</image:image>"
  }

  function New-SitemapUrlNode {
    param(
      [string]$loc,
      [string]$lastmod,
      [string]$priority,
      [string]$imageUrl = "",
      [string]$imageCaption = ""
    )

    $imageNode = New-SitemapImageNode -imageUrl $imageUrl -caption $imageCaption
    return "<url><loc>$(Escape-Xml $loc)</loc><priority>$priority</priority><lastmod>$(Escape-Xml $lastmod)</lastmod>$imageNode</url>"
  }

  $homeFeatured = $allArticles | Select-Object -First 1
  $homeImageUrl = if ($homeFeatured) { $homeFeatured.ImageCanonicalUrl } else { "" }
  $homeImageCaption = if ($homeFeatured) { $homeFeatured.ImageAlt } else { "" }
  $entries.Add((New-SitemapUrlNode -loc "$siteUrl/" -priority "1.0" -lastmod $today -imageUrl $homeImageUrl -imageCaption $homeImageCaption))
  $entries.Add((New-SitemapUrlNode -loc "$siteUrl/articles/" -priority "0.9" -lastmod $today -imageUrl $homeImageUrl -imageCaption $homeImageCaption))
  if (Test-Path (Join-Path $root "contact.html")) {
    $contactLoc = if (Test-Path (Join-Path $root "contact\index.html")) { "$siteUrl/contact/" } else { "$siteUrl/contact.html" }
    $entries.Add((New-SitemapUrlNode -loc $contactLoc -priority "0.5" -lastmod $today))
  }
  if (Test-Path (Join-Path $root "galerie.html")) {
    $galleryLoc = if (Test-Path (Join-Path $root "galerie\index.html")) { "$siteUrl/galerie/" } else { "$siteUrl/galerie.html" }
    $entries.Add((New-SitemapUrlNode -loc $galleryLoc -priority "0.5" -lastmod $today -imageUrl "$siteUrl/images/articles/hydro-systeme-debutant.svg" -imageCaption "Installation hydroponique débutant en appartement"))
  }

  foreach ($article in $allArticles) {
    $lastmod = if ($article.DateModified) { $article.DateModified } else { $article.DatePublished }
    $entries.Add((New-SitemapUrlNode -loc (Get-ArticleCanonicalUrl $article) -priority "0.7" -lastmod $lastmod -imageUrl $article.ImageCanonicalUrl -imageCaption $article.ImageAlt))
  }

  $body = ($entries -join "`n")
  return "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`" xmlns:image=`"http://www.google.com/schemas/sitemap-image/1.1`">`n$body`n</urlset>"
}

function Build-RobotsTxt {
  return @"
User-agent: *
Allow: /
Disallow: /backups/
Disallow: /raw-singlefile/
Disallow: /scripts/
Disallow: /.edge-profile/
Disallow: /.edge-profile-gallery/
Disallow: /articles/article-template.html
Disallow: /SEO-AUDIT.md
Disallow: /readme.md
Disallow: /publish.bat
Disallow: /prompt%20codex.txt

Sitemap: $siteUrl/sitemap.xml
"@
}

foreach ($article in $articles) {
  $articleOutDir = Join-Path $articlesDir $article.Slug
  $outPath = Join-Path $articleOutDir "index.html"
  $legacyRootDir = Join-Path $root $article.Slug
  $relatedPool = if (Test-IsPrimaryArticle $article.Slug) { $primaryArticles } else { $articles }
  $html = Build-ArticleHtml -article $article -allArticles $relatedPool
  $redirectHtml = Get-RedirectHtml -targetUrl (Get-ArticleCanonicalUrl $article) -title "$($article.Title) | $siteName" -description "Cette page a été déplacée vers sa nouvelle adresse."
  New-Item -ItemType Directory -Path $articleOutDir -Force | Out-Null
  New-Item -ItemType Directory -Path $legacyRootDir -Force | Out-Null
  Set-Content -Path $outPath -Value $html -Encoding UTF8
  Set-Content -Path (Join-Path $articlesDir $article.OutputName) -Value $redirectHtml -Encoding UTF8
  Set-Content -Path (Join-Path $legacyRootDir "index.html") -Value $redirectHtml -Encoding UTF8
  Write-Output "Rebuilt articles/$($article.Slug)/index.html, legacy redirect $($article.OutputName) and root redirect /$($article.Slug)/"
}

Write-MinifiedStylesheet

Set-Content -Path (Join-Path $articlesDir "index.html") -Value (Build-ArticlesIndexHtml $primaryArticles) -Encoding UTF8
Set-Content -Path (Join-Path $root "404.html") -Value (Build-404Html) -Encoding UTF8

$privacyDir = Join-Path $root "politique-confidentialite"
New-Item -ItemType Directory -Path $privacyDir -Force | Out-Null
Set-Content -Path (Join-Path $privacyDir "index.html") -Value (Build-PrivacyPageHtml) -Encoding UTF8
Set-Content -Path (Join-Path $root "politique-confidentialite.html") -Value (Get-RedirectHtml -targetUrl "$siteUrl/politique-confidentialite/" -title "Politique de confidentialité | $siteName" -description "Cette page a été déplacée vers sa nouvelle adresse.") -Encoding UTF8

$contactDir = Join-Path $root "contact"
New-Item -ItemType Directory -Path $contactDir -Force | Out-Null
Set-Content -Path (Join-Path $contactDir "index.html") -Value (Build-ContactPageHtml) -Encoding UTF8
New-Item -ItemType Directory -Path (Join-Path $contactDir "merci") -Force | Out-Null
Set-Content -Path (Join-Path $contactDir "merci\index.html") -Value (Build-ContactThanksPageHtml) -Encoding UTF8
Set-Content -Path (Join-Path $root "contact.html") -Value (Get-RedirectHtml -targetUrl "$siteUrl/contact/" -title "Contact | $siteName" -description "Cette page a été déplacée vers sa nouvelle adresse.") -Encoding UTF8

$homePath = Join-Path $root "index.html"
$homeStatus = "Homepage preserved as-is (use -RebuildHome to regenerate it)"
$homeBackupStatus = ""

if ($RebuildHome -or -not (Test-Path $homePath)) {
  if ($RebuildHome -and (Test-Path $homePath)) {
    $homeBackupDir = Join-Path $root "backups\homepage"
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $homeBackupPath = Join-Path $homeBackupDir "index-$timestamp.html"
    New-Item -ItemType Directory -Path $homeBackupDir -Force | Out-Null
    Copy-Item -Path $homePath -Destination $homeBackupPath -Force
    $homeBackupStatus = "Homepage backup created: $homeBackupPath"
  }

  Set-Content -Path $homePath -Value (Build-HomeHtml $primaryArticles) -Encoding UTF8
  $homeStatus = if ($RebuildHome) { "Homepage regenerated from the script" } else { "Homepage created from the script" }
}

Set-Content -Path (Join-Path $root "sitemap.xml") -Value (Build-SitemapXml $primaryArticles) -Encoding UTF8
Set-Content -Path (Join-Path $root "robots.txt") -Value (Build-RobotsTxt) -Encoding UTF8

Write-Output "Updated style.min.css, articles index, 404.html, contact, politique-confidentialite.html, sitemap.xml and robots.txt"
if ($homeBackupStatus) {
  Write-Output $homeBackupStatus
}
Write-Output $homeStatus
