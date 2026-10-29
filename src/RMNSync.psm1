<#
    RMNSync.psm1 — Fonctions de synchronisation des données RMN.
    Compatible Windows PowerShell 5.1 et PowerShell 7.
    Toute valeur propre à un utilisateur vient du fichier de configuration.
#>

Set-StrictMode -Version 2.0

$script:FichierJournal = $null

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

function Expand-RmnChemin {
    param([Parameter(Mandatory)][string]$Chemin)
    [Environment]::ExpandEnvironmentVariables($Chemin)
}

function Join-RmnChemin {
    <# Assemble deux segments sans dépendre du lecteur (fonctionne avec les chemins UNC partout). #>
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)][string]$Enfant)
    $sep = [string][IO.Path]::DirectorySeparatorChar
    if ($Base -match '\\') { $sep = '\' }
    $Base.TrimEnd('\', '/') + $sep + $Enfant.TrimStart('\', '/')
}

function Read-RmnConfig {
    <#
    .SYNOPSIS
        Lit et valide le fichier JSON, applique les valeurs par défaut,
        développe les variables d'environnement et construit la liste des sources.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Chemin)

    if (-not (Test-Path -LiteralPath $Chemin)) {
        throw "Fichier de configuration introuvable : $Chemin"
    }
    try {
        $brut = Get-Content -LiteralPath $Chemin -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Configuration JSON invalide ($Chemin) : $($_.Exception.Message)"
    }

    $defauts = [ordered]@{
        PrefixeEchantillon                   = $null
        Groupe                               = ''
        RacineReseau                         = ''
        Appareils                            = @()
        Destination                          = $null
        ModeleNomExperience                  = '^(?<Parent>{Prefixe}-[^-]+)-(?<Experience>\d+)$'
        FormatDossierLocal                   = '{Nom}_{Frequence}'
        DelaiApresDetectionSecondes          = 3
        StabiliteSecondes                    = 60
        FichiersRequis                       = @()
        IntervalleVerificationReseauSecondes = 30
        BalayagePeriodiqueMinutes            = 10
        DossierJournaux                      = '%LOCALAPPDATA%\RMN\Logs'
        JoursConservationJournaux            = 30
    }

    $cfg = [ordered]@{}
    foreach ($cle in $defauts.Keys) {
        $valeur = $defauts[$cle]
        if ($brut.PSObject.Properties.Name -contains $cle -and $null -ne $brut.$cle) {
            $valeur = $brut.$cle
        }
        $cfg[$cle] = $valeur
    }

    foreach ($obligatoire in 'PrefixeEchantillon', 'Destination') {
        if ([string]::IsNullOrWhiteSpace([string]$cfg[$obligatoire])) {
            throw "Valeur obligatoire manquante dans la configuration : $obligatoire"
        }
    }
    if (@($cfg.Appareils).Count -eq 0) {
        throw "La configuration doit définir au moins un appareil dans 'Appareils'."
    }

    $cfg.Destination     = Expand-RmnChemin $cfg.Destination
    $cfg.DossierJournaux = Expand-RmnChemin $cfg.DossierJournaux

    $prefixeEchappe = [regex]::Escape([string]$cfg.PrefixeEchantillon)
    $cfg.ModeleNomExperience = ([string]$cfg.ModeleNomExperience).Replace('{Prefixe}', $prefixeEchappe)
    try { [void][regex]::new($cfg.ModeleNomExperience) } catch {
        throw "ModeleNomExperience n'est pas une expression régulière valide : $($cfg.ModeleNomExperience)"
    }

    $sources = @()
    foreach ($app in @($cfg.Appareils)) {
        if ([string]::IsNullOrWhiteSpace([string]$app.Frequence)) {
            throw "Chaque appareil doit avoir une 'Frequence'."
        }
        $chemin = $null
        if ($app.PSObject.Properties.Name -contains 'Chemin' -and $app.Chemin) {
            $chemin = Expand-RmnChemin $app.Chemin
        } elseif ($app.PSObject.Properties.Name -contains 'Dossier' -and $app.Dossier) {
            if ([string]::IsNullOrWhiteSpace([string]$cfg.RacineReseau)) {
                throw "RacineReseau est requise quand un appareil utilise 'Dossier' plutôt que 'Chemin'."
            }
            $chemin = Join-RmnChemin (Expand-RmnChemin $cfg.RacineReseau) $app.Dossier
            if ($cfg.Groupe) { $chemin = Join-RmnChemin $chemin $cfg.Groupe }
        } else {
            throw "L'appareil $($app.Frequence) doit définir 'Chemin' ou 'Dossier'."
        }
        $sources += [pscustomobject]@{ Chemin = $chemin; Frequence = [string]$app.Frequence }
    }
    $cfg.Sources = $sources

    [pscustomobject]$cfg
}

# ---------------------------------------------------------------------------
# Journal
# ---------------------------------------------------------------------------

function Initialize-RmnJournal {
    param([Parameter(Mandatory)]$Config)
    if (-not (Test-Path -LiteralPath $Config.DossierJournaux)) {
        New-Item -ItemType Directory -Path $Config.DossierJournaux -Force | Out-Null
    }
    $script:FichierJournal = Join-Path $Config.DossierJournaux ("RMN_{0:yyyy-MM-dd}.log" -f (Get-Date))

    # Nettoyage des anciens journaux (uniquement les fichiers RMN_*.log de ce dossier)
    $limite = (Get-Date).AddDays(-[int]$Config.JoursConservationJournaux)
    Get-ChildItem -LiteralPath $Config.DossierJournaux -Filter 'RMN_*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limite } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Write-RmnJournal {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'AVERT', 'ERREUR')][string]$Niveau = 'INFO'
    )
    $ligne = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Niveau, $Message
    Write-Host $ligne
    if ($script:FichierJournal) {
        try { Add-Content -LiteralPath $script:FichierJournal -Value $ligne -Encoding UTF8 } catch { }
    }
}

# ---------------------------------------------------------------------------
# Logique pure (testable sans réseau)
# ---------------------------------------------------------------------------

function Get-RmnExperience {
    <# Analyse un nom de dossier. Retourne $null s'il ne correspond pas au modèle. #>
    param(
        [Parameter(Mandatory)][string]$Nom,
        [Parameter(Mandatory)]$Config
    )
    $m = [regex]::Match($Nom, $Config.ModeleNomExperience)
    if (-not $m.Success) { return $null }
    $parent = $Nom
    if ($m.Groups['Parent'].Success) { $parent = $m.Groups['Parent'].Value }
    [pscustomobject]@{
        Nom        = $Nom
        Parent     = $parent
        Experience = $(if ($m.Groups['Experience'].Success) { $m.Groups['Experience'].Value } else { '' })
    }
}

function Get-RmnDestination {
    param(
        [Parameter(Mandatory)]$Experience,
        [Parameter(Mandatory)][string]$Frequence,
        [Parameter(Mandatory)]$Config
    )
    $nomLocal = [string]$Config.FormatDossierLocal
    $nomLocal = $nomLocal.Replace('{Nom}', $Experience.Nom).Replace('{Parent}', $Experience.Parent)
    $nomLocal = $nomLocal.Replace('{Experience}', $Experience.Experience).Replace('{Frequence}', $Frequence)
    Join-RmnChemin (Join-RmnChemin $Config.Destination $Experience.Parent) $nomLocal
}

function Test-RmnExperiencePrete {
    <#
    .SYNOPSIS
        Une expérience est prête quand les fichiers requis existent et qu'aucun
        fichier n'a été modifié depuis StabiliteSecondes (acquisition terminée).
    #>
    param(
        [Parameter(Mandatory)][string]$Chemin,
        [Parameter(Mandatory)]$Config
    )
    foreach ($requis in @($Config.FichiersRequis)) {
        if (-not $requis) { continue }
        $alternatives = ([string]$requis).Split('|')
        $trouve = $false
        foreach ($alt in $alternatives) {
            if (Test-Path -LiteralPath (Join-Path $Chemin $alt)) { $trouve = $true; break }
        }
        if (-not $trouve) { return $false }
    }
    $recent = Get-ChildItem -LiteralPath $Chemin -Recurse -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $recent) { return $false }
    $age = ([datetime]::UtcNow - $recent.LastWriteTimeUtc).TotalSeconds
    return ($age -ge [double]$Config.StabiliteSecondes)
}

# ---------------------------------------------------------------------------
# Copie
# ---------------------------------------------------------------------------

function Copy-RmnExperience {
    <#
    .SYNOPSIS
        Copie dans un dossier temporaire « .partiel » puis renomme.
        Une copie interrompue ne laisse donc jamais un dossier final incomplet
        (qui serait ensuite ignoré pour toujours). Rien n'est écrasé.
    #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if (Test-Path -LiteralPath $Destination) { return $false }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $temporaire = "$Destination.partiel"

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        & $robocopy.Source $Source $temporaire /E /COPY:DAT /R:2 /W:5 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy a échoué (code $LASTEXITCODE)" }
    } else {
        if (-not (Test-Path -LiteralPath $temporaire)) {
            New-Item -ItemType Directory -Path $temporaire -Force | Out-Null
        }
        Get-ChildItem -LiteralPath $Source -Force |
            Copy-Item -Destination $temporaire -Recurse -Force -ErrorAction Stop
    }

    Rename-Item -LiteralPath $temporaire -NewName (Split-Path -Leaf $Destination) -ErrorAction Stop
    return $true
}

function Sync-RmnExperience {
    <#
    .SYNOPSIS
        Traite un dossier source. Retourne 'Copie', 'Existe', 'EnAttente', 'Ignore' ou 'Erreur'.
    #>
    param(
        [Parameter(Mandatory)][string]$CheminSource,
        [Parameter(Mandatory)][string]$Frequence,
        [Parameter(Mandatory)]$Config
    )
    $nom = Split-Path -Leaf $CheminSource
    $exp = Get-RmnExperience -Nom $nom -Config $Config
    if (-not $exp) { return 'Ignore' }

    $dest = Get-RmnDestination -Experience $exp -Frequence $Frequence -Config $Config
    if (Test-Path -LiteralPath $dest) { return 'Existe' }
    if (-not (Test-RmnExperiencePrete -Chemin $CheminSource -Config $Config)) { return 'EnAttente' }

    try {
        if (Copy-RmnExperience -Source $CheminSource -Destination $dest) {
            Write-RmnJournal "Copié : $nom ($Frequence) -> $dest"
            return 'Copie'
        }
        return 'Existe'
    } catch {
        Write-RmnJournal "Échec de copie de $nom ($Frequence) : $($_.Exception.Message)" 'ERREUR'
        return 'Erreur'
    }
}

function Invoke-RmnBalayage {
    <# Balaye une source (ou toutes) et retourne un résumé des résultats. #>
    param(
        [Parameter(Mandatory)]$Config,
        $Sources = $null
    )
    if (-not $Sources) { $Sources = $Config.Sources }
    $bilan = @{ Copie = 0; Existe = 0; EnAttente = 0; Ignore = 0; Erreur = 0 }

    foreach ($src in @($Sources)) {
        if (-not (Test-Path -LiteralPath $src.Chemin)) {
            Write-RmnJournal "Source inaccessible : $($src.Chemin)" 'AVERT'
            continue
        }
        $dossiers = Get-ChildItem -LiteralPath $src.Chemin -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike '*.partiel' }
        foreach ($d in $dossiers) {
            $r = Sync-RmnExperience -CheminSource $d.FullName -Frequence $src.Frequence -Config $Config
            $bilan[$r]++
        }
    }
    Write-RmnJournal ("Balayage : {0} copiée(s), {1} déjà présente(s), {2} en attente, {3} erreur(s)" -f `
        $bilan.Copie, $bilan.Existe, $bilan.EnAttente, $bilan.Erreur)
    [pscustomobject]$bilan
}

# ---------------------------------------------------------------------------
# Surveillance continue
# ---------------------------------------------------------------------------

function Start-RmnSurveillance {
    <#
    .SYNOPSIS
        Boucle principale : balayage initial, FileSystemWatcher par source,
        gestion des pertes réseau source par source, balayage périodique de rattrapage.
    #>
    param([Parameter(Mandatory)]$Config)

    $etat = @{}            # index source -> watcher
    $enAttente = @{}       # chemin source -> @{ Frequence; Echeance }
    $prochainBalayage = (Get-Date).AddMinutes([double]$Config.BalayagePeriodiqueMinutes)
    $prochaineVerif = Get-Date

    try {
        while ($true) {
            $maintenant = Get-Date

            # 1. État du réseau, source par source
            if ($maintenant -ge $prochaineVerif) {
                for ($i = 0; $i -lt @($Config.Sources).Count; $i++) {
                    $src = @($Config.Sources)[$i]
                    $accessible = Test-Path -LiteralPath $src.Chemin
                    if ($accessible -and -not $etat.ContainsKey($i)) {
                        Write-RmnJournal "Source disponible : $($src.Chemin) ($($src.Frequence))"
                        Invoke-RmnBalayage -Config $Config -Sources @($src) | Out-Null
                        $etat[$i] = New-RmnWatcher -Source $src -Index $i
                    } elseif (-not $accessible -and $etat.ContainsKey($i)) {
                        Write-RmnJournal "Connexion perdue : $($src.Chemin)" 'AVERT'
                        Remove-RmnWatcher -Index $i -Watcher $etat[$i]
                        $etat.Remove($i)
                    }
                }
                $prochaineVerif = $maintenant.AddSeconds([double]$Config.IntervalleVerificationReseauSecondes)
            }

            # 2. Événements des watchers
            $evt = Wait-Event -Timeout 2
            while ($evt) {
                if ($evt.SourceIdentifier -like 'RMN_Cree_*' -or $evt.SourceIdentifier -like 'RMN_Renomme_*') {
                    $chemin = $evt.SourceEventArgs.FullPath
                    if (-not $enAttente.ContainsKey($chemin)) {
                        $enAttente[$chemin] = @{
                            Frequence = $evt.MessageData
                            Echeance  = (Get-Date).AddSeconds([double]$Config.DelaiApresDetectionSecondes)
                        }
                    }
                } elseif ($evt.SourceIdentifier -like 'RMN_Erreur_*') {
                    $i = [int]($evt.SourceIdentifier -replace '^RMN_Erreur_', '')
                    Write-RmnJournal "Erreur du watcher ($($evt.MessageData)) : réinitialisation" 'AVERT'
                    if ($etat.ContainsKey($i)) { Remove-RmnWatcher -Index $i -Watcher $etat[$i]; $etat.Remove($i) }
                    $prochaineVerif = Get-Date
                }
                Remove-Event -EventIdentifier $evt.EventIdentifier -ErrorAction SilentlyContinue
                $evt = Get-Event -ErrorAction SilentlyContinue | Where-Object { $_.SourceIdentifier -like 'RMN_*' } | Select-Object -First 1
            }

            # 3. Dossiers détectés arrivés à échéance
            foreach ($chemin in @($enAttente.Keys)) {
                $item = $enAttente[$chemin]
                if ((Get-Date) -lt $item.Echeance) { continue }
                if (-not (Test-Path -LiteralPath $chemin -PathType Container)) { $enAttente.Remove($chemin); continue }
                $r = Sync-RmnExperience -CheminSource $chemin -Frequence $item.Frequence -Config $Config
                if ($r -eq 'EnAttente') {
                    $item.Echeance = (Get-Date).AddSeconds([math]::Max(15, [double]$Config.StabiliteSecondes / 2))
                } else {
                    $enAttente.Remove($chemin)
                }
            }

            # 4. Balayage périodique de rattrapage (événements manqués sur partage réseau)
            if ((Get-Date) -ge $prochainBalayage) {
                $actives = @()
                foreach ($i in $etat.Keys) { $actives += @($Config.Sources)[$i] }
                if ($actives.Count -gt 0) { Invoke-RmnBalayage -Config $Config -Sources $actives | Out-Null }
                $prochainBalayage = (Get-Date).AddMinutes([double]$Config.BalayagePeriodiqueMinutes)
            }
        }
    } finally {
        foreach ($i in @($etat.Keys)) { Remove-RmnWatcher -Index $i -Watcher $etat[$i] }
        Write-RmnJournal 'Surveillance arrêtée.'
    }
}

function New-RmnWatcher {
    param([Parameter(Mandatory)]$Source, [Parameter(Mandatory)][int]$Index)
    $w = New-Object System.IO.FileSystemWatcher
    $w.Path = $Source.Chemin
    $w.IncludeSubdirectories = $false
    $w.NotifyFilter = [System.IO.NotifyFilters]::DirectoryName
    $w.InternalBufferSize = 65536
    Register-ObjectEvent -InputObject $w -EventName Created -SourceIdentifier "RMN_Cree_$Index" -MessageData $Source.Frequence | Out-Null
    Register-ObjectEvent -InputObject $w -EventName Renamed -SourceIdentifier "RMN_Renomme_$Index" -MessageData $Source.Frequence | Out-Null
    Register-ObjectEvent -InputObject $w -EventName Error   -SourceIdentifier "RMN_Erreur_$Index" -MessageData $Source.Chemin | Out-Null
    $w.EnableRaisingEvents = $true
    Write-RmnJournal "Surveillance active : $($Source.Chemin)"
    $w
}

function Remove-RmnWatcher {
    param([Parameter(Mandatory)][int]$Index, $Watcher)
    foreach ($type in 'Cree', 'Renomme', 'Erreur') {
        Unregister-Event -SourceIdentifier "RMN_${type}_$Index" -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier "RMN_${type}_$Index" -ErrorAction SilentlyContinue | Remove-Event
    }
    if ($Watcher) {
        try { $Watcher.EnableRaisingEvents = $false } catch { }
        $Watcher.Dispose()
    }
}

Export-ModuleMember -Function Read-RmnConfig, Initialize-RmnJournal, Write-RmnJournal, Get-RmnExperience, `
    Get-RmnDestination, Test-RmnExperiencePrete, Copy-RmnExperience, Sync-RmnExperience, `
    Invoke-RmnBalayage, Start-RmnSurveillance
