# ==========================================
# CONFIGURATION GÉNÉRALE
# ==========================================
$sources = @(
    @{ Chemin = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS\RMN300DATA\Voyer"; Freq = "300" },
    @{ Chemin = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS\RMN400DATA\Voyer"; Freq = "400" },
    @{ Chemin = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS\RMN500DATA\Voyer"; Freq = "500" }
)

$destination = "C:\Users\EMBAI9\OneDrive\RMN"
$serveurPrincipal = "\\ul.ca\fsg\CHM\RMN-LCMS-GCMS"
$modeleRegex = "^EB1212-\d{2,3}-\d{2}"

# Variables globales pour gérer les événements en arrière-plan
$global:DeclencherSync = $false
$global:watchers = @()
$global:jobs = @()

# ==========================================
# FONCTION 1 : LA SYNCHRONISATION OPTIMISÉE
# ==========================================
function Executer-SynchronisationComplete {
    Write-Host "`n[SYNC] Démarrage du balayage..." -ForegroundColor Cyan

    if (-Not (Test-Path -Path $destination)) {
        New-Item -ItemType Directory -Path $destination | Out-Null
    }

    foreach ($sourceItem in $sources) {
        $source = $sourceItem.Chemin
        $freq = $sourceItem.Freq

        if (Test-Path -Path $source) {
            $dossiersTrouves = Get-ChildItem -Path $source -Directory -Filter "EB1212*"
            
            foreach ($dossier in $dossiersTrouves) {
                if ($dossier.Name -match $modeleRegex) {
                    $nomBase = $matches[0]
                    $nomParent = $nomBase.Substring(0, $nomBase.LastIndexOf('-'))
                    $nomFinalAvecFreq = "${nomBase}_${freq}MHz"
                    
                    $cheminDossierParent = Join-Path -Path $destination -ChildPath $nomParent
                    $cheminDossierFinal = Join-Path -Path $cheminDossierParent -ChildPath $nomFinalAvecFreq
                    
                    # --- L'OPTIMISATION ---
                    if (Test-Path -Path $cheminDossierFinal) {
                        # Ignore silencieusement les dossiers déjà copiés
                        continue
                    }
                    
                    Write-Host "  -> NOUVEAU ! Copie : $($dossier.Name) => $nomParent\$nomFinalAvecFreq" -ForegroundColor Green
                    
                    if (-not (Test-Path -Path $cheminDossierParent)) {
                        New-Item -ItemType Directory -Path $cheminDossierParent | Out-Null
                    }
                    if (-not (Test-Path -Path $cheminDossierFinal)) {
                        New-Item -ItemType Directory -Path $cheminDossierFinal | Out-Null
                    }
                    
                    # Copie du contenu
                    Copy-Item -Path "$($dossier.FullName)\*" -Destination $cheminDossierFinal -Recurse -Force
                }
            }
        }
    }
    Write-Host "[SYNC] Balayage terminé. Tout est à jour.`n" -ForegroundColor Cyan
}

# ==========================================
# FONCTION 2 : DÉMARRER L'ÉCOUTE EN DIRECT
# ==========================================
function Demarrer-Watcher {
    Write-Host "[WATCHER] Démarrage de l'écoute en temps réel..." -ForegroundColor Magenta
    
    foreach ($sourceItem in $sources) {
        if (Test-Path $sourceItem.Chemin) {
            $watcher = New-Object System.IO.FileSystemWatcher
            $watcher.Path = $sourceItem.Chemin
            $watcher.Filter = "EB1212*"
            $watcher.IncludeSubdirectories = $false
            $watcher.EnableRaisingEvents = $true

            # L'action lève simplement le drapeau pour dire à la boucle principale de travailler
            $action = {
                Write-Host "`n[ALERTE] Nouveau dossier détecté sur le réseau !" -ForegroundColor Yellow
                $global:DeclencherSync = $true
            }

            # On enregistre l'événement de création de dossier
            $job = Register-ObjectEvent $watcher "Created" -Action $action
            
            $global:watchers += $watcher
            $global:jobs += $job
        }
    }
}

# ==========================================
# FONCTION 3 : ARRÊTER L'ÉCOUTE PROPREMENT
# ==========================================
function Arreter-Watcher {
    Write-Host "[WATCHER] Arrêt de l'écoute et nettoyage..." -ForegroundColor DarkRed
    foreach ($job in $global:jobs) {
        Unregister-Event -SourceIdentifier $job.Name
        Remove-Job -Job $job
    }
    foreach ($watcher in $global:watchers) {
        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()
    }
    $global:watchers = @()
    $global:jobs = @()
}

# ==========================================
# LE CONTRÔLEUR PRINCIPAL (La Boucle d'état)
# ==========================================
Write-Host "Démarrage du système de surveillance RMN..." -ForegroundColor White
$etaitConnecte = $false

try {
    while ($true) {
        # Vérifie si le dossier racine de l'Université est accessible
        $actuellementConnecte = Test-Path -Path $serveurPrincipal

        if ($actuellementConnecte -and -not $etaitConnecte) {
            # ÉVÉNEMENT : Reconnexion
            Write-Host "`n>>> CONNEXION DÉTECTÉE <<<" -ForegroundColor Green
            
            # 1. Rattrapage complet
            Executer-SynchronisationComplete
            
            # 2. Lancement du temps réel
            Demarrer-Watcher
            
            $etaitConnecte = $true
        }
        elseif (-not $actuellementConnecte -and $etaitConnecte) {
            # ÉVÉNEMENT : Perte de réseau
            Write-Host "`n>>> PERTE DE CONNEXION DÉTECTÉE <<<" -ForegroundColor Red
            Arreter-Watcher
            Write-Host "En attente du réseau..." -ForegroundColor Gray
            
            $etaitConnecte = $false
        }
        elseif ($actuellementConnecte -and $etaitConnecte) {
            # ÉVÉNEMENT : Connecté et le drapeau a été levé par le Watcher
            if ($global:DeclencherSync) {
                # On attend 3 secondes pour laisser le temps au serveur de finir de créer le dossier
                Start-Sleep -Seconds 3 
                Executer-SynchronisationComplete
                $global:DeclencherSync = $false
            }
            Start-Sleep -Seconds 2
        }
        else {
            # Toujours hors ligne, on attend en silence
            Start-Sleep -Seconds 10
        }
    }
}
finally {
    # Si vous fermez le script (Ctrl+C), cette section s'assure de nettoyer la mémoire de Windows
    Arreter-Watcher
    Write-Host "Script terminé proprement." -ForegroundColor White
}