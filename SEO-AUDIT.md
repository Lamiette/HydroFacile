# SEO Audit — HydroFacile

**Date:** 2026-04-04  
**Site:** `https://hydrofacile.fr`  
**Stack:** site statique HTML genere via `scripts/rebuild_articles.ps1`

## Structure actuelle

- Accueil : [index.html](c:/Users/Lamiette/Documents/Hydroponie/index.html)
- Index articles : [articles/index.html](c:/Users/Lamiette/Documents/Hydroponie/articles/index.html)
- Galerie : [galerie/index.html](c:/Users/Lamiette/Documents/Hydroponie/galerie/index.html)
- Pages article : `articles/<slug>/index.html`
- Generation SEO : [scripts/rebuild_articles.ps1](c:/Users/Lamiette/Documents/Hydroponie/scripts/rebuild_articles.ps1)
- Contenu editorial : [scripts/article-overrides.ps1](c:/Users/Lamiette/Documents/Hydroponie/scripts/article-overrides.ps1)

## Ajustements appliques

- Titles et meta descriptions harmonises autour de `hydroponie debutant appartement`, `systeme hydroponique simple` et `potager interieur hydroponique`
- H1 de l'accueil et de l'index articles rendus plus naturels et plus SEO
- Ajout de H2 plus clairs sur l'index articles pour mieux structurer la page
- Maillage interne renforce dans le footer avec de vrais liens vers les hubs utiles
- Maillage interne renforce sur les pages article avec un lien vers la galerie
- Cartes thematiques de la home reliees a des ancres reelles du guide public au lieu d'envoyer vers des filtres vides
- Filtres de themes sur la page articles limites aux categories effectivement publiees
- `robots.txt` durci pour bloquer les dossiers et fichiers techniques

## Categories editoriales recommandees

Base conseillee pour HydroFacile :

1. `debuter`
   - intention : comprendre la methode et eviter les erreurs de depart
   - exemples : `hydroponie-sans-pompe-appartement`, `erreurs-hydroponie-debutant`

2. `systemes-materiel`
   - intention : choisir le bon setup, la lumiere et les outils utiles
   - exemples : `lumiere-hydroponie-appartement`, `nutriments-hydroponie-debutant`

3. `cultures-faciles`
   - intention : choisir quoi lancer en premier
   - exemples : `laitue-hydroponique-appartement`, `basilic-hydroponie-interieur`

4. `routine-reglages`
   - intention : stabiliser l'installation dans le temps
   - exemples : `nettoyer-systeme-hydroponique`, `changer-solution-nutritive-hydroponie`

## Conventions d'URL recommandees

Regle simple :

- toujours sous `/articles/`
- slug en minuscules
- mots relies par des tirets
- une intention de recherche claire par URL
- pas de mots vides inutiles

Exemples propres :

- `/articles/hydroponie-sans-pompe-appartement/`
- `/articles/lumiere-hydroponie-appartement/`
- `/articles/nutriments-hydroponie-debutant/`
- `/articles/laitue-hydroponique-appartement/`
- `/articles/basilic-hydroponie-interieur/`
- `/articles/nettoyer-systeme-hydroponique/`

## Logique de maillage recommandee

- Accueil : renvoyer vers le guide pivot le plus utile du moment
- Guide pivot : renvoyer vers `materiel`, `plantes faciles`, `routine`
- Articles secondaires : toujours remonter vers le guide pivot et l'index articles
- Galerie : servir de page de projection visuelle et pousser vers les guides debutant

Schema conseille :

- Home -> guide pivot
- Guide pivot -> article materiel, article lumiere, article laitue, article basilic, article routine
- Chaque article satellite -> guide pivot + index articles + galerie

## Sitemap et robots

### Sitemap

Garder uniquement :

- l'accueil
- l'index articles
- la galerie
- les pages article canoniques

Ne pas y mettre :

- templates
- redirects legacy
- fichiers techniques
- notes internes

### Robots

Bloquer le crawl des repertoires techniques :

- `/backups/`
- `/raw-singlefile/`
- `/scripts/`
- profils locaux
- fichiers markdown, batch ou prompts non editoriaux

## Priorites SEO suivantes

1. Creer 3 articles satellites autour du guide pivot :
   - `lumiere-hydroponie-appartement`
   - `laitue-hydroponique-appartement`
   - `nettoyer-systeme-hydroponique`

2. Ajouter ensuite un second hub :
   - `cultures-faciles-hydroponie-appartement`

3. Quand il y aura assez de contenu, creer de vraies pages categories indexables si besoin :
   - `/categorie/debuter/`
   - `/categorie/systemes-materiel/`
   - `/categorie/cultures-faciles/`
   - `/categorie/routine-reglages/`

Pour l'instant, la base SEO du site est saine pour un lancement progressif avec un guide pivot et une architecture simple.
