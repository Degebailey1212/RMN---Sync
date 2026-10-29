<#
.SYNOPSIS
    Crée (ou met à jour) la tâche planifiée RMN pour l'utilisateur courant.
.DESCRIPTION
    Déclencheurs : ouverture de session et déverrouillage.
    S'exécute seulement quand l'utilisateur est connecté, sans mot de passe enregistré,
    autorisée sur batterie, sans limite de durée, 3 redémarrages espacés d'une minute,
    aucune seconde instance.
.PARAMETER DesactiverAncienneTache
    Désactive (sans la supprimer) l'ancienne tâche « Master_code_RMN_watcher+Sync »
    pour éviter deux synchronisations en parallèle.
.EXAMPLE
    .\scripts\Installer-Tache.ps1 -DesactiverAncienneTache
#>
[CmdletBinding()]
param(
    [string]$NomTache = 'RMN-Sync',
    [string]$Config,
    [switch]$DesactiverAncienneTache
)
$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
$script = Join-Path $racine 'src\RMN-Sync.ps1'
if (-not $Config) { $Config = Join-Path $racine 'config\rmn.config.json' }
if (-not (Test-Path -LiteralPath $Config)) {
    throw "Configuration absente : $Config. Copiez d'abord config\rmn.config.example.json."
}

# Valide la configuration avant d'installer quoi que ce soit
Import-Module (Join-Path $racine 'src\RMNSync.psm1') -Force
$cfg = Read-RmnConfig -Chemin $Config
Write-Host "Configuration valide : préfixe $($cfg.PrefixeEchantillon), $(@($cfg.Sources).Count) source(s)."

$utilisateur = "$env:USERDOMAIN\$env:USERNAME"
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Config `"$Config`""

$action = New-ScheduledTaskAction -Execute $powershell -Argument $arguments -WorkingDirectory $racine

$ouverture = New-ScheduledTaskTrigger -AtLogOn -User $utilisateur
$classe = Get-CimClass -Namespace 'Root/Microsoft/Windows/TaskScheduler' -ClassName 'MSFT_TaskSessionStateChangeTrigger'
$deverrouillage = New-CimInstance -CimClass $classe -ClientOnly
$deverrouillage.StateChange = 8   # TASK_SESSION_UNLOCK
$deverrouillage.UserId = $utilisateur
$deverrouillage.Enabled = $true

$parametres = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew -StartWhenAvailable

$principal = New-ScheduledTaskPrincipal -UserId $utilisateur -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $NomTache -Action $action -Trigger @($ouverture, $deverrouillage) `
    -Settings $parametres -Principal $principal -Force `
    -Description 'Synchronisation automatique des données RMN (dépôt rmn-sync).' | Out-Null
Write-Host "Tâche « $NomTache » installée pour $utilisateur." -ForegroundColor Green

if ($DesactiverAncienneTache) {
    $ancienne = Get-ScheduledTask -TaskName 'Master_code_RMN_watcher+Sync' -ErrorAction SilentlyContinue
    if ($ancienne) {
        Stop-ScheduledTask -TaskName $ancienne.TaskName -ErrorAction SilentlyContinue
        Disable-ScheduledTask -TaskName $ancienne.TaskName | Out-Null
        Write-Host 'Ancienne tâche arrêtée et désactivée (non supprimée).' -ForegroundColor Yellow
    }
}

$demarrer = Read-Host 'Démarrer la tâche maintenant ? (o/n)'
if ($demarrer -match '^[oOyY]') { Start-ScheduledTask -TaskName $NomTache; Write-Host 'Démarrée.' }
