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
$siteUrl = "https://ecobalcon.com"
# GA4 is intended to be wired through GTM to avoid duplicate pageview tracking.
$googleAnalyticsMeasurementId = "G-L952X34SHR"
$googleTagManagerId = "GTM-MFRVPVFQ"
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
  if ([string]::IsNullOrWhiteSpace($googleTagManagerId)) { return "" }

  return @"
  <!-- Google Tag Manager -->
  <script>(function(w,d,s,l,i){w[l]=w[l]||[];w[l].push({'gtm.start':new Date().getTime(),event:'gtm.js'});var f=d.getElementsByTagName(s)[0],j=d.createElement(s),dl=l!='dataLayer'?'&l='+l:'';j.async=true;j.src='https://www.googletagmanager.com/gtm.js?id='+i+dl;f.parentNode.insertBefore(j,f);})(window,document,'script','dataLayer','$googleTagManagerId');</script>
  <!-- End Google Tag Manager -->
"@
}

function Get-TagManagerBodyHtml {
  if ([string]::IsNullOrWhiteSpace($googleTagManagerId)) { return "" }

  return @"
  <!-- Google Tag Manager (noscript) -->
  <noscript><iframe src="https://www.googletagmanager.com/ns.html?id=$googleTagManagerId" height="0" width="0" style="display:none;visibility:hidden"></iframe></noscript>
  <!-- End Google Tag Manager (noscript) -->
"@
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
    [string]$title = "Redirection | EcoBalcon",
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

  $image = [System.Drawing.Image]::FromFile($fullPath)
  try {
    $dimensions = [PSCustomObject]@{
      Width = $image.Width
      Height = $image.Height
    }
  } finally {
    $image.Dispose()
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
            <strong>EcoBalcon</strong>
            <p>Astuces pour jardiner en milieu urbain.</p>
          </div>
          <div class="footer-social" aria-label="R&eacute;seaux sociaux">
            <a class="footer-social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="footer-social-link" href="https://x.com/Eco_Balcon" target="_blank" rel="noopener noreferrer" aria-label="X">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <path d="M4 4l16 16"></path>
                <path d="M20 4L4 20"></path>
              </svg>
            </a>
          </div>
        </div>
        <div class="footer-side">
          <strong>Sur le site</strong>
          <ul class="footer-list">
            <li>Potager de balcon et cultures faciles</li>
            <li>Plantes adapt&eacute;es au soleil comme &agrave; l'ombre</li>
            <li>Gestes sobres pour l'eau, le compost et la biodiversit&eacute;</li>
          </ul>
        </div>
        <div class="footer-legal">&copy; 2026. Tous droits r&eacute;serv&eacute;s.</div>
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
    "guide-poivrons-sur-son-balcon" = "Fiches Techniques"
    "guide-tomates-sur-son-balcon" = "Fiches Techniques"
    "guide-epinards-sur-son-balcon" = "Fiches Techniques"
    "guide-fraises-sur-son-balcon" = "Fiches Techniques"
    "guide-radis-sur-son-balcon" = "Fiches Techniques"
    "guide-laitues-sur-son-balcon" = "Fiches Techniques"
    "tomates-cerises-balcon" = "Fiches Techniques"
    "potager-balcon-eau-de-cuisson" = "Plantes & semis"
    "pommes-de-terre-balcon" = "Plantes & semis"
    "petits-fruits-en-pot" = "Plantes & semis"
    "fleurs-comestibles-melliferes-balcon" = "Plantes & semis"
    "plantes-pour-un-balcon-plein-soleil" = "Plantes & semis"
    "balcon-a-lombre-plantes-et-culture" = "Plantes & semis"
    "legumes-faciles-a-cultiver" = "Plantes & semis"
    "calendrier-du-jardin-de-balcon" = "Plantes & semis"
    "plantes-aromatiques-sur-balcon" = "Plantes & semis"
    "balcon-durable-plantes" = "Plantes & semis"
    "balcon-pour-pollinisateurs" = "Plantes & semis"
    "jardinage-en-lasagnes-sur-balcon" = "Entretien & astuces"
    "plantes-qui-survivent-a-la-canicule" = "Entretien & astuces"
    "reduction-consommation-eau-balcon" = "Entretien & astuces"
    "insectes-utiles-sur-un-balcon" = "Entretien & astuces"
    "calendrier-lunaire-balcon" = "Entretien & astuces"
    "jardiner-sur-un-balcon" = "Entretien & astuces"
    "paillage-sur-balcon-ecolo" = "Entretien & astuces"
    "proteger-son-balcon-des-nuisibles-naturellement" = "Entretien & astuces"
    "utilisation-compost-sur-balcon" = "Entretien & astuces"
    "jardin-sur-balcon-astuces" = "Entretien & astuces"
    "erreurs-jardiner-sur-un-balcon" = "Entretien & astuces"
    "meilleures-plantes-grimpantes-en-ville" = "Aménagement du balcon"
    "recuperer-eau-de-pluie-balcon" = "Aménagement du balcon"
    "diy-pots-pour-le-balcon" = "Aménagement du balcon"
    "le-materiel-essentiel-pour-commencer" = "Aménagement du balcon"
    "solutions-compostage-sur-balcon" = "Aménagement du balcon"
  }

  if ($categoryBySlug.ContainsKey($slug)) {
    return $categoryBySlug[$slug]
  }

  $normalizedCategory = Normalize-ArticleCategoryToken $rawCategory
  switch ($normalizedCategory) {
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

    if ($schema.url -notmatch '^https://ecobalcon\.com/(?<slug>[^/?#]+)') {
      throw "Impossible de determiner le slug pour $($file.Name)."
    }

    $slug = $matches["slug"]
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
$slugMap = @{}
foreach ($article in $articles) {
  $slugMap[$article.Slug] = Get-ArticlePrettyHref -article $article -hrefPrefix "../"
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

  if ($article.Faq) {
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

  if (-not $faqSchemaMap.ContainsKey($article.Slug)) {
    return $null
  }

  return [ordered]@{
    "@context" = "https://schema.org"
    "@type" = "FAQPage"
    mainEntity = @(
      $faqSchemaMap[$article.Slug] | ForEach-Object {
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

  $howTo = $null

  if ($article.HowTo) {
    $howTo = $article.HowTo
  } elseif ($howToSchemaMap.ContainsKey($article.Slug)) {
    $howTo = $howToSchemaMap[$article.Slug]
  } else {
    return $null
  }

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
  $bodyHtml = if ($article.BodyHtml) { $article.BodyHtml.TrimEnd() } else { Build-ArticleBody $content }
  $bodyHtml = Ensure-AffiliateDisclosure $bodyHtml
  $dateText = Convert-IsoDateToFrench $article.DatePublished
  $timeText = Convert-TimeRequired $article.TimeRequired
  $canonicalUrl = Get-ArticleCanonicalUrl $article
  $seoTitle = if ($article.SeoTitle) { $article.SeoTitle } else { $article.Title }
  $heroImageSrc = Get-ImagePagePath -fileName $article.ImageFileName -pagePrefix "../../images/articles/"
  $heroImageDimensions = Get-ArticleImageDimensionAttributes $article.ImageFileName
  $logoDimensions = Get-RootImageDimensionAttributes "images\logo-site.png"
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
      name = "EcoBalcon"
      logo = [ordered]@{
        "@type" = "ImageObject"
        url = "$siteUrl/images/logo-site.png"
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
  <title>$(HtmlEscape $seoTitle) | EcoBalcon</title>
  <meta name="description" content="$(HtmlEscape $article.Description)">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <meta name="author" content="$(HtmlEscape $article.AuthorName)">
  <link rel="preload" as="image" href="$heroImageSrc" fetchpriority="high">
  <link rel="canonical" href="$canonicalUrl">
  <link rel="alternate" hreflang="fr" href="$canonicalUrl">
  <link rel="alternate" hreflang="x-default" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="article">
  <meta property="og:title" content="$(HtmlEscape $seoTitle) | EcoBalcon">
  <meta property="og:description" content="$(HtmlEscape $article.Description)">
  <meta property="og:url" content="$canonicalUrl">
  <meta property="og:image" content="$($article.ImageCanonicalUrl)">
  <meta property="og:image:alt" content="$(HtmlEscape $heroCaption)">
  <meta property="article:published_time" content="$($article.DatePublished)">
  <meta property="article:modified_time" content="$($article.DateModified)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="$(HtmlEscape $seoTitle) | EcoBalcon">
  <meta name="twitter:description" content="$(HtmlEscape $article.Description)">
  <meta name="twitter:image" content="$($article.ImageCanonicalUrl)">
  <meta name="twitter:image:alt" content="$(HtmlEscape $heroCaption)">
$jsonLdScripts
$tagManagerHead
  <link rel="icon" type="image/png" sizes="32x32" href="../../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../../images/apple-touch-icon.png">
  <link rel="stylesheet" href="$articleDetailStylesheetHref">
</head>
<body class="article-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../../">
          <span class="brand-mark">
            <img class="brand-logo" src="../../images/logo-site.png" alt="Logo EcoBalcon"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../../">Accueil</a>
            <a href="../">Articles</a>
            <a href="../../galerie/">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/Eco_Balcon" target="_blank" rel="noopener noreferrer" aria-label="X">
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

  $featured = @($allArticles | Select-Object -First 6)
  $cardsHtml = (($featured | ForEach-Object -Begin { $cardIndex = 0 } -Process {
        $delay = 80 + ($cardIndex * 70)
        $cardIndex++
        (Build-ArticleCardHtml -article $_ -hrefPrefix "articles/" -imagePrefix "images/articles/") -replace '<article class="article-card">', "<article class=`"article-card`" data-reveal style=`"--reveal-delay: ${delay}ms;`">"
      }) -join "`n")
  $count = $allArticles.Count
  $featuredArticle = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "jardinage-en-lasagnes-sur-balcon",
    "jardiner-sur-un-balcon",
    "jardin-sur-balcon-astuces"
  ) -fallbackIndex 0
  $featuredImage = if ($featuredArticle) { $featuredArticle.ImageCanonicalUrl } else { "" }
  $featuredImageSrc = if ($featuredArticle) { Get-ImagePagePath -fileName $featuredArticle.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $featuredImageDimensions = if ($featuredArticle) { Get-ArticleImageDimensionAttributes $featuredArticle.ImageFileName } else { "" }
  $featuredTitle = if ($featuredArticle) { $featuredArticle.Title } else { "Jardinage urbain sur balcon" }
  $featuredImageAlt = if ($featuredArticle) { $featuredArticle.ImageAlt } else { "Balcon potager et jardinage urbain" }
  $shareImage = "$siteUrl/images/cette-semaine-home.jpg"
  $shareImageAlt = "Balcon ensoleillé avec plusieurs plantes en pot et jardinières"
  $heroSecondary = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "plantes-qui-survivent-a-la-canicule",
    "reduction-consommation-eau-balcon",
    "guide-tomates-sur-son-balcon"
  ) -fallbackIndex 1
  $heroSupportHref = "articles/jardin-sur-balcon-astuces/"
  $homeVisualDimensions = " width=`"1024`" height=`"1536`""
  $homeStats = @(
    [PSCustomObject]@{ Label = "Guides utiles"; Value = "$count"; Copy = "pour planter, arroser, récolter et aménager." },
    [PSCustomObject]@{ Label = "Repères clairs"; Value = "4"; Copy = "grands thèmes pour vite trouver le bon conseil." },
    [PSCustomObject]@{ Label = "Pensé pour"; Value = "100 %"; Copy = "la ville, les pots, les rebords et les balcons." }
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
      Label = "Débuter"
      Title = "Poser les bonnes bases"
      Copy = "Un point de départ simple pour installer un balcon agréable et éviter les erreurs classiques."
      Href = "articles/jardin-sur-balcon-astuces/"
      LinkLabel = "Voir les bases"
    },
    [PSCustomObject]@{
      Label = "Planter"
      Title = "Choisir des cultures faciles"
      Copy = "Des fiches pratiques pour cultiver sur balcon simplement, sans compliquer les choses."
      Href = "articles/guide-tomates-sur-son-balcon/"
      LinkLabel = "Voir les cultures"
    },
    [PSCustomObject]@{
      Label = "Préserver"
      Title = "Entretenir un balcon plus écolo"
      Copy = "Arrosage, paillage, récupération d’eau et gestes utiles pour un balcon facile à vivre au quotidien."
      Href = "articles/reduction-consommation-eau-balcon/"
      LinkLabel = "Voir les astuces"
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
    "plantes-qui-survivent-a-la-canicule",
    "guide-poivrons-sur-son-balcon",
    "guide-laitues-sur-son-balcon",
    "calendrier-du-jardin-de-balcon",
    "jardin-sur-balcon-astuces"
  ) -fallbackIndex 0
  $weeklyFeatureHref = if ($weeklyFallbackArticle) { Get-ArticlePrettyHref -article $weeklyFallbackArticle -hrefPrefix "articles/" } else { "articles/" }
  $weeklyFeatureImageSrc = if ($weeklyFallbackArticle) { Get-ImagePagePath -fileName $weeklyFallbackArticle.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $weeklyFeatureImageDimensions = if ($weeklyFallbackArticle) { Get-ArticleImageDimensionAttributes $weeklyFallbackArticle.ImageFileName } else { "" }
  $weeklyFeatureCategory = if ($weeklyFallbackArticle) { $weeklyFallbackArticle.Category } else { "À lire" }
  $weeklyFeatureTitle = if ($weeklyFallbackArticle) { $weeklyFallbackArticle.Title } else { "À découvrir cette semaine" }
  $weeklyFeatureDescription = if ($weeklyFallbackArticle) { Get-CardExcerpt $weeklyFallbackArticle.Description 178 } else { "Une sélection pratique choisie automatiquement selon la période de l'année." }
  $weeklyFeatureImageAlt = if ($weeklyFallbackArticle) { $weeklyFallbackArticle.ImageAlt } else { "Sélection d'article EcoBalcon de la semaine" }
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
            <span class="eyebrow">Fiches Techniques</span>
            <h3><a href="articles/#theme=fiches-techniques">Trouver un guide culture pas &agrave; pas</a></h3>
            <p>Les fiches les plus concr&egrave;tes pour cultiver tomates, poivrons, laitues, radis, fraises et autres cultures de balcon.</p>
            <a class="text-link" href="articles/#theme=fiches-techniques">Voir les fiches</a>
          </article>
          <article class="theme-card" data-reveal style="--reveal-delay: 130ms;">
            <span class="eyebrow">Plantes &amp; semis</span>
            <h3><a href="articles/#theme=plantes-semis">Choisir quoi planter selon son balcon</a></h3>
            <p>Des s&eacute;lections de plantes, de l&eacute;gumes, d’aromatiques et d’id&eacute;es de culture selon l’exposition et les envies.</p>
            <a class="text-link" href="articles/#theme=plantes-semis">Voir les plantations</a>
          </article>
          <article class="theme-card" data-reveal style="--reveal-delay: 200ms;">
            <span class="eyebrow">Entretien &amp; astuces</span>
            <h3><a href="articles/#theme=entretien-astuces">Mieux entretenir son balcon au quotidien</a></h3>
            <p>Arrosage, paillage, compost, nuisibles, chaleur et gestes simples pour garder un balcon sain et facile &agrave; vivre.</p>
            <a class="text-link" href="articles/#theme=entretien-astuces">Voir les astuces</a>
          </article>
          <article class="theme-card" data-reveal style="--reveal-delay: 270ms;">
            <span class="eyebrow">Am&eacute;nagement du balcon</span>
            <h3><a href="articles/#theme=amenagement-du-balcon">Am&eacute;nager un espace plus pratique</a></h3>
            <p>Mat&eacute;riel, pots, compostage, r&eacute;cup&eacute;ration d’eau, plantes grimpantes et astuces pour organiser le balcon.</p>
            <a class="text-link" href="articles/#theme=amenagement-du-balcon">Voir les am&eacute;nagements</a>
          </article>
"@
  $editorialFeature = Get-PreferredArticle -allArticles $allArticles -preferredSlugs @(
    "plantes-qui-survivent-a-la-canicule",
    "potager-balcon-eau-de-cuisson",
    "jardinage-en-lasagnes-sur-balcon"
  ) -fallbackIndex 0
  $editorialFeatureHref = if ($editorialFeature) { Get-ArticlePrettyHref -article $editorialFeature -hrefPrefix "articles/" } else { "articles/" }
  $editorialFeatureImageSrc = if ($editorialFeature) { Get-ImagePagePath -fileName $editorialFeature.ImageFileName -pagePrefix "images/articles/" } else { "" }
  $editorialFeatureImageDimensions = if ($editorialFeature) { Get-ArticleImageDimensionAttributes $editorialFeature.ImageFileName } else { "" }
  $logoDimensions = Get-RootImageDimensionAttributes "images\logo-site.png"
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
      name = "EcoBalcon"
      url = "$siteUrl/"
      inLanguage = "fr"
      description = "EcoBalcon partage des conseils pratiques pour jardiner sur balcon, économiser l'eau, choisir les bonnes plantes et réussir un petit potager urbain."
      potentialAction = [ordered]@{
        "@type" = "SearchAction"
        target = "$siteUrl/articles/?q={search_term_string}"
        "query-input" = "required name=search_term_string"
      }
      publisher = [ordered]@{
        "@type" = "Organization"
        name = "EcoBalcon"
        logo = [ordered]@{
          "@type" = "ImageObject"
          url = "$siteUrl/images/logo-site.png"
        }
      }
    })

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EcoBalcon | Jardinage urbain sur balcon</title>
  <meta name="description" content="EcoBalcon partage des conseils pratiques pour jardiner sur balcon, économiser l'eau, choisir les bonnes plantes et réussir un petit potager urbain.">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <link rel="preload" as="image" href="images/balcon-soleil.webp" fetchpriority="high">
  <link rel="canonical" href="$siteUrl/">
  <link rel="alternate" hreflang="fr" href="$siteUrl/">
  <link rel="alternate" hreflang="x-default" href="$siteUrl/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="website">
  <meta property="og:title" content="EcoBalcon | Jardinage urbain sur balcon">
  <meta property="og:description" content="EcoBalcon partage des conseils pratiques pour jardiner sur balcon, économiser l'eau, choisir les bonnes plantes et réussir un petit potager urbain.">
  <meta property="og:url" content="$siteUrl/">
  <meta property="og:image" content="$shareImage">
  <meta property="og:image:alt" content="$(HtmlEscape $shareImageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="EcoBalcon | Jardinage urbain sur balcon">
  <meta name="twitter:description" content="EcoBalcon partage des conseils pratiques pour jardiner sur balcon, économiser l'eau, choisir les bonnes plantes et réussir un petit potager urbain.">
  <meta name="twitter:image" content="$shareImage">
  <meta name="twitter:image:alt" content="$(HtmlEscape $shareImageAlt)">
$jsonLd
$tagManagerHead
  <link rel="icon" type="image/png" sizes="32x32" href="images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="images/apple-touch-icon.png">
  <link rel="stylesheet" href="$rootStylesheetHref">
</head>
<body class="home-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="./">
          <span class="brand-mark">
            <img class="brand-logo" src="images/logo-site.png" alt="Logo EcoBalcon"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="./" aria-current="page">Accueil</a>
            <a href="articles/">Articles</a>
            <a href="galerie/">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/Eco_Balcon" target="_blank" rel="noopener noreferrer" aria-label="X">
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
            <div class="hero-copy-main" data-reveal>
              <span class="eyebrow hero-eyebrow">EcoBalcon &middot; Jardinage sur balcon</span>
              <h1>Le balcon devient un jardin &agrave; vivre.</h1>
              <p>Des conseils simples pour jardiner sur un balcon, lancer un potager urbain et faire vivre les petits espaces.</p>
            </div>
            <div class="hero-copy-side">
              <div class="hero-actions" data-reveal style="--reveal-delay: 90ms;">
                <a class="button" href="articles/">Explorer les guides</a>
                <a class="button-secondary" href="$heroSupportHref">Commencer avec les bases</a>
              </div>
              <div class="hero-support-note" data-reveal style="--reveal-delay: 160ms;">
                <span class="hero-support-chip">Le bon d&eacute;part</span>
                <strong>Mieux vaut commencer simple, puis laisser le balcon prendre sa place.</strong>
                <p>Deux ou trois cultures bien suivies suffisent souvent pour trouver le bon rythme, observer la lumi&egrave;re et prendre plaisir &agrave; jardiner.</p>
                <a class="text-link" href="$heroSupportHref">Voir les bases</a>
              </div>
              <div class="hero-stat-grid" data-reveal style="--reveal-delay: 220ms;">
$statsHtml
              </div>
            </div>
          </div>

          <aside class="hero-panel" aria-label="Balcon v&eacute;g&eacute;tal en ville" data-reveal style="--reveal-delay: 120ms;">
            <figure class="home-visual">
              <div class="home-visual-stage">
                <img class="home-visual-main" src="images/balcon-soleil.webp" alt="Balcon ensoleill&eacute; avec jardini&egrave;res, fleurs, l&eacute;gumes et arrosoir en pleine lumi&egrave;re" title="Balcon ensoleill&eacute; avec jardini&egrave;res, fleurs, l&eacute;gumes et arrosoir en pleine lumi&egrave;re" loading="eager" decoding="async" fetchpriority="high"$homeVisualDimensions>
              </div>
              <figcaption class="home-visual-note">
                <span class="home-visual-chip">Balcon vivant</span>
                <p>Un coin lumineux, vivant et simple &agrave; cultiver au rythme des saisons.</p>
              </figcaption>
            </figure>
          </aside>
        </div>
      </section>

      <section class="section">
        <div class="section-inner">
          <div class="section-heading" data-reveal>
            <div>
              <h2>Commencer ici</h2>
              <p>Trois mani&egrave;res simples de commencer selon tes envies.</p>
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
          <div class="section-heading" data-reveal>
            <div>
              <h2>&Agrave; lire cette semaine</h2>
              <p>Retrouvez ici une s&eacute;lection d'articles pratiques &agrave; lire en ce moment.</p>
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
              <h2 class="page-title">Explorer les articles</h2>
              <p class="page-intro">
                Potager, chaleur, &eacute;conomies d’eau, biodiversit&eacute;, fleurs utiles et fiches pratiques :
                retrouvez tous les contenus au m&ecirc;me endroit.
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

        if (/guide|calendrier|astuces|balcon/i.test(haystack)) {
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

  $cardsHtml = (($allArticles | ForEach-Object -Begin { $cardIndex = 0 } -Process {
        $delay = [Math]::Min(70 + ($cardIndex * 45), 520)
        $cardIndex++
        (Build-ArticleCardHtml -article $_ -hrefPrefix "" -imagePrefix "../images/articles/") -replace '<article class="article-card">', "<article class=`"article-card`" data-reveal style=`"--reveal-delay: ${delay}ms;`">"
      }) -join "`n")
  $count = $allArticles.Count
  $heroImage = if ($allArticles.Count -gt 0) { $allArticles[0].ImageCanonicalUrl } else { "" }
  $heroImageAlt = if ($allArticles.Count -gt 0) { $allArticles[0].ImageAlt } else { "Articles EcoBalcon autour du jardinage sur balcon" }
  $logoDimensions = Get-RootImageDimensionAttributes "images\logo-site.png"
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $jsonLd = Get-JsonLdScriptTags @([ordered]@{
      "@context" = "https://schema.org"
      "@type" = "CollectionPage"
      name = "Conseils et guides jardinage sur balcon | EcoBalcon"
      url = "$siteUrl/articles/"
      inLanguage = "fr"
      description = "Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes écolo."
      isPartOf = [ordered]@{
        "@type" = "WebSite"
        name = "EcoBalcon"
        url = "$siteUrl/"
      }
    })

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Conseils et guides jardinage sur balcon | EcoBalcon</title>
  <meta name="description" content="Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes écolo.">
  <meta name="robots" content="index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1">
  <link rel="canonical" href="$siteUrl/articles/">
  <link rel="alternate" hreflang="fr" href="$siteUrl/articles/">
  <link rel="alternate" hreflang="x-default" href="$siteUrl/articles/">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Conseils et guides jardinage sur balcon | EcoBalcon">
  <meta property="og:description" content="Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes écolo.">
  <meta property="og:url" content="$siteUrl/articles/">
  <meta property="og:image" content="$heroImage">
  <meta property="og:image:alt" content="$(HtmlEscape $heroImageAlt)">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="Conseils et guides jardinage sur balcon | EcoBalcon">
  <meta name="twitter:description" content="Retrouve les articles EcoBalcon autour du jardinage sur balcon, du potager urbain, des plantes utiles et des gestes écolo.">
  <meta name="twitter:image" content="$heroImage">
  <meta name="twitter:image:alt" content="$(HtmlEscape $heroImageAlt)">
$jsonLd
$tagManagerHead
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="stylesheet" href="$articleStylesheetHref">
</head>
<body class="articles-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo EcoBalcon"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../">Accueil</a>
            <a href="./" aria-current="page">Articles</a>
            <a href="../galerie/">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/Eco_Balcon" target="_blank" rel="noopener noreferrer" aria-label="X">
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
        <div class="page-hero" data-reveal>
          <div class="page-hero-copy">
            <h1 class="page-title">Tout pour jardiner facilement sur un balcon</h1>
            <p class="page-intro">
              Des conseils simples et concrets pour am&eacute;nager son balcon, choisir les bonnes plantes et cr&eacute;er un petit coin de verdure facile &agrave; entretenir.
            </p>
          </div>

          <section class="search-panel search-panel-compact" aria-label="Recherche d'articles" data-reveal style="--reveal-delay: 60ms;">
            <label class="search-label sr-only" for="article-search">Rechercher un article</label>
            <input
              class="search-input"
              id="article-search"
              type="search"
              name="q"
              placeholder="Rechercher un article"
              autocomplete="off">
          </section>
        </div>

        <section class="theme-filter-panel" aria-label="Filtrer les articles par thème" data-reveal style="--reveal-delay: 90ms;">
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
        { slug: "all", label: "Tous" },
        { slug: "fiches-techniques", label: "Fiches Techniques" },
        { slug: "plantes-semis", label: "Plantes & semis" },
        { slug: "entretien-astuces", label: "Entretien & astuces" },
        { slug: "amenagement-du-balcon", label: "Aménagement du balcon" }
      ];

      articleCards.forEach((card) => {
        const themeLabel = getCardThemeLabel(card);
        const themeSlug = slugifyTheme(themeLabel);
        const themePill = card.querySelector(".pill");

        if (themeSlug === "") {
          return;
        }

        card.dataset.theme = themeSlug;

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
  $logoDimensions = Get-RootImageDimensionAttributes "images\logo-site.png"
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $canonicalUrl = "$siteUrl/politique-confidentialite/"

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Politique de confidentialit&eacute; | EcoBalcon</title>
  <meta name="description" content="Informations sur la mesure d'audience, les cookies et les donn&eacute;es de navigation utilis&eacute;s sur EcoBalcon.">
  <meta name="robots" content="noindex,nofollow">
  <link rel="canonical" href="$canonicalUrl">
  <link rel="alternate" hreflang="fr" href="$canonicalUrl">
  <link rel="alternate" hreflang="x-default" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Politique de confidentialit&eacute; | EcoBalcon">
  <meta property="og:description" content="Informations sur la mesure d'audience, les cookies et les donn&eacute;es de navigation utilis&eacute;s sur EcoBalcon.">
  <meta property="og:url" content="$canonicalUrl">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Politique de confidentialit&eacute; | EcoBalcon">
  <meta name="twitter:description" content="Informations sur la mesure d'audience, les cookies et les donn&eacute;es de navigation utilis&eacute;s sur EcoBalcon.">
$tagManagerHead
  <link rel="icon" type="image/png" sizes="32x32" href="../images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="../images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="../images/apple-touch-icon.png">
  <link rel="stylesheet" href="../css/style.min.css">
</head>
<body class="legal-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="../">
          <span class="brand-mark">
            <img class="brand-logo" src="../images/logo-site.png" alt="Logo EcoBalcon"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="../">Accueil</a>
            <a href="../articles/">Articles</a>
            <a href="../galerie/">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/Eco_Balcon" target="_blank" rel="noopener noreferrer" aria-label="X">
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
              Cette page r&eacute;sume les informations utiles sur la mesure d'audience, les cookies et les donn&eacute;es techniques
              susceptibles d'&ecirc;tre trait&eacute;es lorsque tu consultes EcoBalcon.
            </p>
          </div>

          <aside class="checklist utility-panel">
            <h2>En bref</h2>
            <ul class="article-list">
              <li>EcoBalcon est un site &eacute;ditorial autour du jardinage sur balcon.</li>
              <li>Le site utilise Google Tag Manager et peut activer Google Analytics 4 pour la mesure d'audience.</li>
              <li>Il n'y a pas d'espace membre ni de compte utilisateur &agrave; cr&eacute;er sur le site.</li>
              <li>Les liens vers des services tiers comme Instagram ou X suivent leurs propres r&egrave;gles.</li>
            </ul>
          </aside>
        </section>

        <article class="article-prose">
          <h2>Donn&eacute;es de navigation</h2>
          <p>
            Lorsque tu visites EcoBalcon, des informations techniques usuelles peuvent &ecirc;tre trait&eacute;es&nbsp;:
            pages consult&eacute;es, date et heure de visite, appareil, navigateur, langue, provenance de la visite ou
            donn&eacute;es de performance. Elles servent surtout &agrave; comprendre l'usage du site et &agrave; l'am&eacute;liorer.
          </p>

          <h2>Mesure d'audience</h2>
          <p>
            EcoBalcon utilise Google Tag Manager (<code>GTM-MFRVPVFQ</code>) pour piloter ses balises. Selon la configuration
            active du conteneur, Google Analytics 4 (<code>G-L952X34SHR</code>) peut &ecirc;tre utilis&eacute; pour mesurer l'audience,
            observer les pages vues et mieux comprendre les parcours de navigation.
          </p>

          <h2>Cookies et technologies proches</h2>
          <p>
            Certaines balises ou outils de mesure peuvent d&eacute;poser des cookies ou utiliser des technologies similaires.
            Leur fonctionnement d&eacute;pend des outils activ&eacute;s, des r&eacute;glages du navigateur et, le cas &eacute;ch&eacute;ant,
            des param&egrave;tres de consentement mis en place sur le site.
          </p>

          <h2>Liens et services tiers</h2>
          <p>
            Le site propose des liens vers des plateformes externes, notamment Instagram et X. Lorsque tu quittes EcoBalcon
            pour consulter ces services, leurs propres politiques de confidentialit&eacute; s'appliquent.
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

function Build-404Html {
  $logoDimensions = Get-RootImageDimensionAttributes "images\logo-site.png"
  $tagManagerHead = Get-TagManagerHeadHtml
  $tagManagerBody = Get-TagManagerBodyHtml
  $canonicalUrl = "$siteUrl/404.html"

  return @"
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Page introuvable | EcoBalcon</title>
  <meta name="description" content="La page demand&eacute;e est introuvable. Reviens &agrave; l'accueil EcoBalcon ou explore les articles et la galerie.">
  <meta name="robots" content="noindex,follow">
  <link rel="canonical" href="$canonicalUrl">
  <meta property="og:locale" content="fr_FR">
  <meta property="og:site_name" content="EcoBalcon">
  <meta property="og:type" content="website">
  <meta property="og:title" content="Page introuvable | EcoBalcon">
  <meta property="og:description" content="La page demand&eacute;e est introuvable. Reviens &agrave; l'accueil EcoBalcon ou explore les articles et la galerie.">
  <meta property="og:url" content="$canonicalUrl">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Page introuvable | EcoBalcon">
  <meta name="twitter:description" content="La page demand&eacute;e est introuvable. Reviens &agrave; l'accueil EcoBalcon ou explore les articles et la galerie.">
$tagManagerHead
  <link rel="icon" type="image/png" sizes="32x32" href="images/favicon-32.png">
  <link rel="icon" type="image/png" sizes="192x192" href="images/favicon-192.png">
  <link rel="apple-touch-icon" sizes="180x180" href="images/apple-touch-icon.png">
  <link rel="stylesheet" href="$rootStylesheetHref">
</head>
<body class="not-found-page">
$tagManagerBody
  <div class="site-shell">
    <header class="site-header">
      <div class="header-inner">
        <a class="brand" href="./">
          <span class="brand-mark">
            <img class="brand-logo" src="images/logo-site.png" alt="Logo EcoBalcon"$logoDimensions>
          </span>
        </a>
        <div class="header-actions">
          <nav class="site-nav" aria-label="Navigation principale">
            <a href="./">Accueil</a>
            <a href="articles/">Articles</a>
            <a href="galerie/">Galerie</a>
          </nav>
          <div class="social-nav" aria-label="R&eacute;seaux sociaux">
            <a class="social-link" href="https://www.instagram.com/eco_balcon/" target="_blank" rel="noopener noreferrer" aria-label="Instagram">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
                <rect x="3" y="3" width="18" height="18" rx="5"></rect>
                <circle cx="12" cy="12" r="4.2"></circle>
                <circle cx="17.4" cy="6.6" r="1"></circle>
              </svg>
            </a>
            <a class="social-link" href="https://x.com/Eco_Balcon" target="_blank" rel="noopener noreferrer" aria-label="X">
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
        <section class="page-hero">
          <div class="page-hero-copy">
            <span class="eyebrow">404</span>
            <h1 class="page-title">Page introuvable</h1>
            <p class="page-intro">
              L'adresse demand&eacute;e ne correspond &agrave; aucune page active du site. Tu peux revenir &agrave; l'accueil
              ou repartir depuis les articles pour retrouver le bon contenu.
            </p>
            <div class="hero-actions">
              <a class="button" href="./">Retour &agrave; l'accueil</a>
              <a class="button-secondary" href="articles/">Voir les articles</a>
            </div>
          </div>

          <aside class="checklist utility-panel">
            <h2>Tu peux essayer</h2>
            <ul class="article-list">
              <li>Revenir &agrave; l'accueil pour repartir des contenus principaux.</li>
              <li>Parcourir les guides et fiches techniques depuis la liste des articles.</li>
              <li>Ouvrir la galerie pour retrouver des inspirations balcon.</li>
            </ul>
            <a class="text-link" href="galerie/">Voir la galerie</a>
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
  if (Test-Path (Join-Path $root "galerie.html")) {
    $galleryLoc = if (Test-Path (Join-Path $root "galerie\index.html")) { "$siteUrl/galerie/" } else { "$siteUrl/galerie.html" }
    $entries.Add((New-SitemapUrlNode -loc $galleryLoc -priority "0.5" -lastmod $today -imageUrl "$siteUrl/images/articles/canicule-balcon-mxBXq1QqyeTR1PLZ.webp" -imageCaption "Balcon plante en plein soleil"))
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

Sitemap: $siteUrl/sitemap.xml
"@
}

foreach ($article in $articles) {
  $articleOutDir = Join-Path $articlesDir $article.Slug
  $outPath = Join-Path $articleOutDir "index.html"
  $html = Build-ArticleHtml -article $article -allArticles $articles
  $redirectHtml = Get-RedirectHtml -targetUrl (Get-ArticleCanonicalUrl $article) -title "$($article.Title) | EcoBalcon" -description "Cette page a été déplacée vers sa nouvelle adresse."
  New-Item -ItemType Directory -Path $articleOutDir -Force | Out-Null
  Set-Content -Path $outPath -Value $html -Encoding UTF8
  Set-Content -Path (Join-Path $articlesDir $article.OutputName) -Value $redirectHtml -Encoding UTF8
  Write-Output "Rebuilt articles/$($article.Slug)/index.html and legacy redirect $($article.OutputName)"
}

Write-MinifiedStylesheet

Set-Content -Path (Join-Path $articlesDir "index.html") -Value (Build-ArticlesIndexHtml $articles) -Encoding UTF8
Set-Content -Path (Join-Path $root "404.html") -Value (Build-404Html) -Encoding UTF8

$privacyDir = Join-Path $root "politique-confidentialite"
New-Item -ItemType Directory -Path $privacyDir -Force | Out-Null
Set-Content -Path (Join-Path $privacyDir "index.html") -Value (Build-PrivacyPageHtml) -Encoding UTF8
Set-Content -Path (Join-Path $root "politique-confidentialite.html") -Value (Get-RedirectHtml -targetUrl "$siteUrl/politique-confidentialite/" -title "Politique de confidentialite | EcoBalcon" -description "Cette page a ete deplacee vers sa nouvelle adresse.") -Encoding UTF8

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

  Set-Content -Path $homePath -Value (Build-HomeHtml $articles) -Encoding UTF8
  $homeStatus = if ($RebuildHome) { "Homepage regenerated from the script" } else { "Homepage created from the script" }
}

Set-Content -Path (Join-Path $root "sitemap.xml") -Value (Build-SitemapXml $articles) -Encoding UTF8
Set-Content -Path (Join-Path $root "robots.txt") -Value (Build-RobotsTxt) -Encoding UTF8

Write-Output "Updated style.min.css, articles index, 404.html, politique-confidentialite.html, sitemap.xml and robots.txt"
if ($homeBackupStatus) {
  Write-Output $homeBackupStatus
}
Write-Output $homeStatus
