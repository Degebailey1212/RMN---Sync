<#
.SYNOPSIS
    Écoute les dossiers RMN du réseau et met à jour automatiquement la copie locale.

.DESCRIPTION
    Clic droit > « Exécuter avec PowerShell » :
        vérifie l'accès au réseau, propose d'installer le démarrage automatique
        (ouverture et déverrouillage de session), puis lance l'écoute en arrière-plan.

    Fonctionnement de l'écoute :
      - Chaque dossier d'expérience (ex. EB1212-071-36…) est copié vers
        Destination\EB1212-071\EB1212-071-36_400MHz, comme l'ancien script.
      - La copie est INCRÉMENTALE : seuls les fichiers nouveaux ou plus récents sont copiés.
        Une expérience ajoutée 8 h plus tard dans le même dossier est donc récupérée.
      - Pendant une acquisition, le dossier est recopié au moins toutes les 10 minutes ;
        une copie finale est faite dès qu'il est calme depuis 60 secondes.
      - Les dossiers modifiés depuis moins de 48 h sont revérifiés toutes les 10 minutes
        (rattrapage si un événement réseau a été manqué).
      - Rien n'est jamais supprimé, ni sur le réseau ni en local. Un fichier local plus
        récent que celui du réseau (ex. retraité dans TopSpin) n'est pas écrasé.

    Paramètres internes :
      -Ecoute   boucle d'écoute (utilisée par la tâche planifiée, sans fenêtre)
      -UneFois  une mise à jour complète immédiate, puis arrêt (utilisée par Mise_a_jour_RMN.ps1)
#>
[CmdletBinding()]
param(
    [switch]$Ecoute,
    [switch]$UneFois,
    # Réglages avancés (tests) : laissez vides en utilisation normale
    [string]$RacineReseau,
    [string]$Destination,
    [int]$CalmeSecondes,
    [int]$VerifReseauSecondes
)

# =====================================================================
#  CONFIGURATION — la seule partie à modifier pour un autre utilisateur
# =====================================================================
$Config = @{
    Prefixe             = 'EB1212'
    Groupe              = 'Voyer'
    RacineReseau        = '\\ul.ca\fsg\CHM\RMN-LCMS-GCMS'
    Appareils           = @(
        @{ Dossier = 'RMN300DATA'; Freq = '300' },
        @{ Dossier = 'RMN400DATA'; Freq = '400' },
        @{ Dossier = 'RMN500DATA'; Freq = '500' }
    )
    Destination         = "$env:USERPROFILE\OneDrive\RMN"
    SuiviHeures         = 48   # un dossier modifié depuis moins de 48 h reste revérifié
    CalmeSecondes       = 60   # copie finale après 60 s sans activité dans le dossier
    CopieMaxMinutes     = 10   # pendant une longue acquisition : copie au moins toutes les 10 min
    BalayageMinutes     = 10   # rattrapage périodique des dossiers récents
    VerifReseauSecondes = 30   # vérification de la connexion réseau
    NomTache            = 'RMN - Ecoute et mise a jour'
    AncienneTache       = 'Master_code_RMN_watcher+Sync'
}
# =====================================================================

if ($RacineReseau)        { $Config.RacineReseau = $RacineReseau }
if ($Destination)         { $Config.Destination = $Destination }
if ($CalmeSecondes)       { $Config.CalmeSecondes = $CalmeSecondes }
if ($VerifReseauSecondes) { $Config.VerifReseauSecondes = $VerifReseauSecondes }

$script:ModeleRegex = '^' + [regex]::Escape($Config.Prefixe) + '-\d{2,3}-\d{2}'
$script:Sources = @(foreach ($app in $Config.Appareils) {
    [pscustomobject]@{
        Chemin = [IO.Path]::Combine($Config.RacineReseau, $app.Dossier, $Config.Groupe)
        Freq   = $app.Freq
    }
})
$script:Robocopy = $null
$cmdRobocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
if ($cmdRobocopy) { $script:Robocopy = $cmdRobocopy.Source }
$script:TotalExperiences = 0
$script:TotalFichiers = 0

$baseLocale = $env:LOCALAPPDATA
if (-not $baseLocale) { $baseLocale = [IO.Path]::GetTempPath() }
$script:DossierJournaux = [IO.Path]::Combine($baseLocale, 'RMN', 'Logs')
$script:Journal = $null

# ---------------------------------------------------------------------
#  Outils
# ---------------------------------------------------------------------

function Write-Journal {
    param([string]$Message, [string]$Couleur = 'Gray')
    $ligne = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $Message
    Write-Host $ligne -ForegroundColor $Couleur
    if ($script:Journal) {
        try { Add-Content -LiteralPath $script:Journal -Value $ligne -Encoding UTF8 } catch { }
    }
}

function Initialize-Journal {
    param([string]$Nom)
    if (-not (Test-Path -LiteralPath $script:DossierJournaux)) {
        New-Item -ItemType Directory -Path $script:DossierJournaux -Force | Out-Null
    }
    $script:Journal = Join-Path $script:DossierJournaux ('{0}_{1:yyyy-MM-dd}.log' -f $Nom, (Get-Date))
    $limite = (Get-Date).AddDays(-30)
    Get-ChildItem -LiteralPath $script:DossierJournaux -Filter 'RMN_*.log' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limite } | Remove-Item -Force -ErrorAction SilentlyContinue
}

function Get-Verrou {
    # Empêche deux copies du même mode de tourner en même temps.
    param([string]$Nom)
    $m = New-Object System.Threading.Mutex($false, $Nom)
    $ok = $false
    try { $ok = $m.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $ok = $true }
    if ($ok) { return $m }
    $m.Dispose()
    return $null
}

function Get-Destination {
    # Même règle que l'ancien script : on garde le DÉBUT du nom (EB1212-071-36),
    # le dossier parent est EB1212-071 et on ajoute la fréquence.
    param([string]$Nom, [string]$Freq)
    if (-not ($Nom -match $script:ModeleRegex)) { return $null }
    $base = $Matches[0]
    $parent = $base.Substring(0, $base.LastIndexOf('-'))
    return [IO.Path]::Combine($Config.Destination, $parent, ('{0}_{1}MHz' -f $base, $Freq))
}

function Copy-Incrementale {
    # Copie de secours sans robocopy (hors Windows) : fichiers absents ou plus récents seulement.
    param([string]$Source, [string]$Cible)
    $n = 0
    $longueur = $Source.TrimEnd('\', '/').Length
    foreach ($f in Get-ChildItem -LiteralPath $Source -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $relatif = $f.FullName.Substring($longueur).TrimStart('\', '/')
        $chemin = Join-Path $Cible $relatif
        $existant = Get-Item -LiteralPath $chemin -ErrorAction SilentlyContinue
        if (-not $existant -or $f.LastWriteTimeUtc -gt $existant.LastWriteTimeUtc) {
            $dossier = Split-Path -Parent $chemin
            if (-not (Test-Path -LiteralPath $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
            Copy-Item -LiteralPath $f.FullName -Destination $chemin -Force
            $n++
        }
    }
    if (-not (Test-Path -LiteralPath $Cible)) { New-Item -ItemType Directory -Path $Cible -Force | Out-Null }
    return $n
}

function Sync-Experience {
    # Met à jour un dossier d'expérience. Retourne $true si tout s'est bien passé.
    param([string]$Chemin, [string]$Freq)
    $nom = Split-Path -Leaf $Chemin
    $cible = Get-Destination -Nom $nom -Freq $Freq
    if (-not $cible) { return $true }
    $nouveau = -not (Test-Path -LiteralPath $cible)
    $n = 0
    if ($script:Robocopy) {
        # /E sous-dossiers, /XO ne remplace jamais un fichier local plus récent,
        # /XX ne touche pas aux fichiers présents seulement en local. Aucune suppression.
        $sortie = & $script:Robocopy $Chemin $cible /E /XO /XX /R:2 /W:5 /NP /NJH /NJS /NDL /NC /NS 2>&1
        $code = $LASTEXITCODE
        if ($code -ge 8) {
            Write-Journal ("ERREUR de copie (robocopy {0}) : {1} - nouvel essai plus tard" -f $code, $nom) 'Red'
            return $false
        }
        if ($code -band 1) { $n = @($sortie | Where-Object { "$_".Trim() }).Count }
    } else {
        try { $n = Copy-Incrementale -Source $Chemin -Cible $cible }
        catch {
            Write-Journal ("ERREUR de copie : {0} - {1}" -f $nom, $_.Exception.Message) 'Red'
            return $false
        }
    }
    if ($n -gt 0) {
        $etat = 'MIS À JOUR'
        if ($nouveau) { $etat = 'NOUVEAU' }
        $court = $cible.Substring($Config.Destination.Length).TrimStart('\', '/')
        Write-Journal ('{0} : {1} -> {2} ({3} fichier(s))' -f $etat, $nom, $court, $n) 'Green'
        $script:TotalExperiences++
        $script:TotalFichiers += $n
    }
    return $true
}

function Invoke-Balayage {
    # -Complet : vérifie toutes les expériences.
    # Sinon : seulement celles absentes en local ou modifiées depuis SuiviHeures.
    param([switch]$Complet, $Sources = $script:Sources)
    $limite = (Get-Date).AddHours(-$Config.SuiviHeures)
    foreach ($src in @($Sources)) {
        if (-not (Test-Path -LiteralPath $src.Chemin)) {
            Write-Journal "Source inaccessible : $($src.Chemin)" 'Yellow'
            continue
        }
        $dossiers = Get-ChildItem -LiteralPath $src.Chemin -Directory -Filter "$($Config.Prefixe)*" -ErrorAction SilentlyContinue
        foreach ($d in $dossiers) {
            $cible = Get-Destination -Nom $d.Name -Freq $src.Freq
            if (-not $cible) { continue }
            if ($Complet -or $d.LastWriteTime -gt $limite -or -not (Test-Path -LiteralPath $cible)) {
                Sync-Experience -Chemin $d.FullName -Freq $src.Freq | Out-Null
            }
        }
    }
}

# ---------------------------------------------------------------------
#  Écoute en temps réel
# ---------------------------------------------------------------------

function New-Ecouteur {
    param($Source, [int]$Index)
    $w = New-Object System.IO.FileSystemWatcher
    $w.Path = $Source.Chemin
    $w.IncludeSubdirectories = $true   # voit aussi les nouvelles expériences DANS un dossier existant
    $w.NotifyFilter = [System.IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
    $w.InternalBufferSize = 65536
    foreach ($type in 'Created', 'Changed', 'Renamed', 'Error') {
        Register-ObjectEvent -InputObject $w -EventName $type -SourceIdentifier ('RMN_{0}_{1}' -f $type, $Index) -MessageData $Index | Out-Null
    }
    $w.EnableRaisingEvents = $true
    Write-Journal "Écoute active : $($Source.Chemin) ($($Source.Freq) MHz)" 'Cyan'
    return $w
}

function Remove-Ecouteur {
    param([int]$Index, $Ecouteur)
    foreach ($type in 'Created', 'Changed', 'Renamed', 'Error') {
        $id = 'RMN_{0}_{1}' -f $type, $Index
        Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue
        Get-Event -SourceIdentifier $id -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    }
    if ($Ecouteur) {
        try { $Ecouteur.EnableRaisingEvents = $false } catch { }
        $Ecouteur.Dispose()
    }
}

function Start-Ecoute {
    $ecouteurs = @{}          # index de source -> FileSystemWatcher
    $actifs = @{}             # dossier réseau -> activité récente
    $prochaineVerif = Get-Date
    $prochainBalayage = (Get-Date).AddMinutes($Config.BalayageMinutes)

    try {
        while ($true) {
            # 1. Connexion réseau, appareil par appareil
            if ((Get-Date) -ge $prochaineVerif) {
                for ($i = 0; $i -lt $script:Sources.Count; $i++) {
                    $src = $script:Sources[$i]
                    $accessible = Test-Path -LiteralPath $src.Chemin
                    if ($accessible -and -not $ecouteurs.ContainsKey($i)) {
                        Write-Journal "Connexion : $($src.Chemin)" 'Green'
                        Invoke-Balayage -Sources @($src)
                        $ecouteurs[$i] = New-Ecouteur -Source $src -Index $i
                    } elseif (-not $accessible -and $ecouteurs.ContainsKey($i)) {
                        Write-Journal "Connexion perdue : $($src.Chemin) - en attente du réseau" 'Yellow'
                        Remove-Ecouteur -Index $i -Ecouteur $ecouteurs[$i]
                        $ecouteurs.Remove($i)
                    }
                }
                $prochaineVerif = (Get-Date).AddSeconds($Config.VerifReseauSecondes)
            }

            # 2. Événements : on note quel dossier d'expérience bouge
            $null = Wait-Event -Timeout 2
            foreach ($e in @(Get-Event -ErrorAction SilentlyContinue)) {
                $sid = [string]$e.SourceIdentifier
                if ($sid -like 'RMN_Error_*') {
                    $i = [int]$e.MessageData
                    Write-Journal 'Écoute interrompue par le réseau : redémarrage' 'Yellow'
                    if ($ecouteurs.ContainsKey($i)) {
                        Remove-Ecouteur -Index $i -Ecouteur $ecouteurs[$i]
                        $ecouteurs.Remove($i)
                    }
                    $prochaineVerif = Get-Date
                } elseif ($sid -like 'RMN_*') {
                    $i = [int]$e.MessageData
                    $src = $script:Sources[$i]
                    $chemin = [string]$e.SourceEventArgs.FullPath
                    if ($chemin.Length -gt $src.Chemin.Length) {
                        $relatif = $chemin.Substring($src.Chemin.Length).TrimStart('\', '/')
                        $nom = ($relatif -split '[\\/]')[0]
                        if ($nom -and (Get-Destination -Nom $nom -Freq $src.Freq)) {
                            $cle = [IO.Path]::Combine($src.Chemin, $nom)
                            if ($actifs.ContainsKey($cle)) {
                                $actifs[$cle].Activite = Get-Date
                            } else {
                                Write-Journal "Activité détectée : $nom ($($src.Freq) MHz)"
                                $actifs[$cle] = @{ Freq = $src.Freq; Activite = (Get-Date); DerniereCopie = (Get-Date) }
                            }
                        }
                    }
                }
                Remove-Event -EventIdentifier $e.EventIdentifier -ErrorAction SilentlyContinue
            }

            # 3. Copie des dossiers actifs : quand ils se calment, ou régulièrement pendant une longue acquisition
            foreach ($cle in @($actifs.Keys)) {
                $a = $actifs[$cle]
                $maintenant = Get-Date
                $calme = ($maintenant - $a.Activite).TotalSeconds -ge $Config.CalmeSecondes
                $longue = ($maintenant - $a.DerniereCopie).TotalMinutes -ge $Config.CopieMaxMinutes
                if ($calme -or $longue) {
                    $ok = $true
                    if (Test-Path -LiteralPath $cle) { $ok = Sync-Experience -Chemin $cle -Freq $a.Freq }
                    $a.DerniereCopie = Get-Date
                    if ($calme -and $ok) { $actifs.Remove($cle) }
                }
            }

            # 4. Rattrapage périodique des dossiers récents
            if ((Get-Date) -ge $prochainBalayage) {
                $connectees = @()
                foreach ($i in @($ecouteurs.Keys)) { $connectees += $script:Sources[$i] }
                if ($connectees.Count -gt 0) { Invoke-Balayage -Sources $connectees }
                $prochainBalayage = (Get-Date).AddMinutes($Config.BalayageMinutes)
            }
        }
    } finally {
        foreach ($i in @($ecouteurs.Keys)) { Remove-Ecouteur -Index $i -Ecouteur $ecouteurs[$i] }
        Write-Journal 'Écoute arrêtée.'
    }
}

# ---------------------------------------------------------------------
#  Démarrage automatique (Planificateur de tâches)
# ---------------------------------------------------------------------

function Install-Tache {
    $utilisateur = "$env:USERDOMAIN\$env:USERNAME"
    $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Ecoute' -f $PSCommandPath
    $action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $PSScriptRoot

    $ouverture = New-ScheduledTaskTrigger -AtLogOn -User $utilisateur
    $classe = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger'
    $deverrouillage = New-CimInstance -CimClass $classe -ClientOnly
    $deverrouillage.StateChange = 8   # déverrouillage de session
    $deverrouillage.UserId = $utilisateur
    $deverrouillage.Enabled = $true

    $reglages = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
    $principal = New-ScheduledTaskPrincipal -UserId $utilisateur -LogonType Interactive -RunLevel Limited

    Register-ScheduledTask -TaskName $Config.NomTache -Action $action -Trigger @($ouverture, $deverrouillage) `
        -Settings $reglages -Principal $principal -Force -Description 'Écoute RMN et mise à jour automatique (Code MAJ).' | Out-Null
    Write-Host "  Tâche « $($Config.NomTache) » installée." -ForegroundColor Green

    $ancienne = Get-ScheduledTask -TaskName $Config.AncienneTache -ErrorAction SilentlyContinue
    if ($ancienne) {
        Stop-ScheduledTask -TaskName $Config.AncienneTache -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskName $Config.AncienneTache | Out-Null
        Write-Host "  Ancienne tâche « $($Config.AncienneTache) » arrêtée et désactivée (non supprimée)." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------
#  Point d'entrée
# ---------------------------------------------------------------------

$nomUtilisateur = ([string]$env:USERNAME) -replace '[^\w-]', '_'

if ($UneFois) {
    Initialize-Journal -Nom 'RMN_MiseAJour'
    $verrou = Get-Verrou -Nom "RMN-MiseAJour-$nomUtilisateur"
    if (-not $verrou) { Write-Journal 'Une mise à jour est déjà en cours.' 'Yellow'; return }
    try {
        Write-Journal "Mise à jour complète vers $($Config.Destination)..." 'Cyan'
        Invoke-Balayage -Complet
        Write-Journal ('Mise à jour terminée : {0} expérience(s) mise(s) à jour, {1} fichier(s) copié(s).' -f $script:TotalExperiences, $script:TotalFichiers) 'Cyan'
    } finally { $verrou.ReleaseMutex(); $verrou.Dispose() }
    return
}

if ($Ecoute) {
    Initialize-Journal -Nom 'RMN_Ecoute'
    $verrou = Get-Verrou -Nom "RMN-Ecoute-$nomUtilisateur"
    if (-not $verrou) { Write-Journal 'L''écoute est déjà active : ce lancement s''arrête.'; return }
    try {
        Write-Journal "Démarrage de l'écoute (PowerShell $($PSVersionTable.PSVersion)) vers $($Config.Destination)" 'Cyan'
        Start-Ecoute
    } finally { $verrou.ReleaseMutex(); $verrou.Dispose() }
    return
}

# Lancement manuel (clic droit > Exécuter avec PowerShell)
Write-Host ''
Write-Host '=== RMN : écoute et mise à jour automatique ===' -ForegroundColor Cyan
Write-Host "Destination : $($Config.Destination)"
foreach ($src in $script:Sources) {
    if (Test-Path -LiteralPath $src.Chemin) { Write-Host "  OK            $($src.Freq) MHz  $($src.Chemin)" -ForegroundColor Green }
    else { Write-Host "  INACCESSIBLE  $($src.Freq) MHz  $($src.Chemin)" -ForegroundColor Yellow }
}
Write-Host ''

$test = Get-Verrou -Nom "RMN-Ecoute-$nomUtilisateur"
$enCours = $true
if ($test) { $enCours = $false; $test.ReleaseMutex(); $test.Dispose() }
$tache = Get-ScheduledTask -TaskName $Config.NomTache -ErrorAction SilentlyContinue
$autoOk = ($tache -and $tache.State -ne 'Disabled')

if ($enCours) { Write-Host 'Écoute en ce moment          : EN MARCHE' -ForegroundColor Green }
else          { Write-Host 'Écoute en ce moment          : ARRÊTÉE' -ForegroundColor Yellow }
if ($autoOk)  { Write-Host 'Démarrage automatique        : INSTALLÉ' -ForegroundColor Green }
else          { Write-Host 'Démarrage automatique        : NON INSTALLÉ' -ForegroundColor Yellow }
Write-Host ''

if (-not $autoOk) {
    $reponse = Read-Host "Installer le démarrage automatique (ouverture et déverrouillage de session) ? (o/n)"
    if ($reponse -match '^[oOyY]') {
        Install-Tache
        $tache = Get-ScheduledTask -TaskName $Config.NomTache -ErrorAction SilentlyContinue
        $autoOk = ($tache -and $tache.State -ne 'Disabled')
    }
}

if (-not $enCours) {
    if ($autoOk) {
        Start-ScheduledTask -TaskName $Config.NomTache
    } else {
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Start-Process -FilePath $exe -WindowStyle Hidden -ArgumentList @(
            '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
            '-File', ('"{0}"' -f $PSCommandPath), '-Ecoute')
    }
    Write-Host 'Écoute démarrée en arrière-plan.' -ForegroundColor Green
}
Write-Host ''
if ($autoOk) { Write-Host "Tout est en place : l'écoute redémarrera seule à chaque ouverture et déverrouillage de session." -ForegroundColor Green }
else { Write-Host "Attention : sans démarrage automatique, l'écoute s'arrêtera au prochain redémarrage." -ForegroundColor Yellow }
Write-Host "Journal : $script:DossierJournaux" -ForegroundColor Gray
Write-Host ''
Read-Host 'Appuyez sur Entrée pour fermer cette fenêtre'
