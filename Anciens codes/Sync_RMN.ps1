# 1. Définition des sources (Chemin réseau + Fréquence associée)
# On utilise un tableau de paires clés/valeurs pour lier chaque dossier à ses MHz
$sources = @(
    @{ Chemin = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS\RMN300DATA\Voyer"; Freq = "300" },
    @{ Chemin = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS\RMN400DATA\Voyer"; Freq = "400" },
    @{ Chemin = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS\RMN500DATA\Voyer"; Freq = "500" }
)

$destination = "C:\Users\emili\OneDrive\RMN"

# Expression régulière : Format de base EB1212-XX-XX ou EB1212-XXX-XX
$modeleRegex = "^EB1212-\d{2,3}-\d{2}"

# 2. Vérification et création du dossier principal de destination
if (-Not (Test-Path -Path $destination)) {
    Write-Host "Création du dossier principal : $destination" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $destination | Out-Null
}

# 3. Boucle à travers chaque source
foreach ($sourceItem in $sources) {
    # On extrait le chemin et la fréquence de notre tableau
    $source = $sourceItem.Chemin
    $freq = $sourceItem.Freq

    Write-Host "Scan du répertoire : $source ($freq MHz)" -ForegroundColor Yellow

    if (Test-Path -Path $source) {
        
        $dossiersTrouves = Get-ChildItem -Path $source -Directory -Filter "EB1212*"
        $compteur = 0

        foreach ($dossier in $dossiersTrouves) {
            # Si le nom du dossier est valide selon notre format...
            if ($dossier.Name -match $modeleRegex) {
                $compteur++
                
                # Le nom de base propre (ex: EB1212-051-01)
                $nomBase = $matches[0]
                
                # Le nom du dossier parent (ex: EB1212-051)
                $nomParent = $nomBase.Substring(0, $nomBase.LastIndexOf('-'))
                
                # Le NOUVEAU nom du sous-dossier avec les MHz (ex: EB1212-051-01_300MHz)
                $nomFinalAvecFreq = "${nomBase}_${freq}MHz"
                
                # Construction des chemins de destination
                $cheminDossierParent = Join-Path -Path $destination -ChildPath $nomParent
                $cheminDossierFinal = Join-Path -Path $cheminDossierParent -ChildPath $nomFinalAvecFreq
                
                Write-Host "  -> Classement : $($dossier.Name) => $nomParent\$nomFinalAvecFreq" -ForegroundColor Green
                
                # 1. Création du parent (EB1212-051)
                if (-not (Test-Path -Path $cheminDossierParent)) {
                    New-Item -ItemType Directory -Path $cheminDossierParent | Out-Null
                }
                
                # 2. Création de l'enfant avec la fréquence (EB1212-051-01_300MHz)
                if (-not (Test-Path -Path $cheminDossierFinal)) {
                    New-Item -ItemType Directory -Path $cheminDossierFinal | Out-Null
                }
                
                # 3. Copie du contenu
                Copy-Item -Path "$($dossier.FullName)\*" -Destination $cheminDossierFinal -Recurse -Force
            }
        }
        
        if ($compteur -eq 0) {
            Write-Host "  -> Aucun dossier au format valide trouvé ici." -ForegroundColor Gray
        }

    } else {
        Write-Warning "Le chemin source n'est pas accessible. ($source)"
    }
}

Write-Host "Transfert terminé ! Votre arborescence RMN est parfaitement classée." -ForegroundColor Cyan