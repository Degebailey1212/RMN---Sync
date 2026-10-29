<#
.SYNOPSIS
    Point d'entrée de la synchronisation RMN.
.DESCRIPTION
    Charge la configuration, garantit une seule instance par utilisateur,
    effectue le balayage puis surveille les nouvelles expériences.
.PARAMETER Config
    Chemin du fichier JSON. Par défaut : config\rmn.config.json à côté du dépôt.
.PARAMETER UneFois
    Fait un seul balayage puis quitte (utile pour tester ou pour une tâche ponctuelle).
.EXAMPLE
    .\src\RMN-Sync.ps1
    .\src\RMN-Sync.ps1 -UneFois
    .\src\RMN-Sync.ps1 -Config 'D:\autre.json'
#>
[CmdletBinding()]
param(
    [string]$Config,
    [switch]$UneFois
)

$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'RMNSync.psm1') -Force

if (-not $Config) {
    $Config = Join-Path $racine 'config\rmn.config.json'
    if (-not (Test-Path -LiteralPath $Config)) {
        Write-Host "config\rmn.config.json absent : copiez config\rmn.config.example.json et adaptez-le." -ForegroundColor Yellow
        exit 2
    }
}

$cfg = Read-RmnConfig -Chemin $Config
Initialize-RmnJournal -Config $cfg

# Une seule instance par utilisateur, quel que soit le mode de lancement
# (tâche planifiée, double-clic, VS Code).
$nomVerrou = 'RMN-Sync-' + ($env:USERNAME -replace '[^\w-]', '_')
$verrou = New-Object System.Threading.Mutex($false, $nomVerrou)
$acquis = $false
try { $acquis = $verrou.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquis = $true }
if (-not $acquis) {
    Write-RmnJournal 'Une instance est déjà active : arrêt de ce lancement.'
    exit 0
}

try {
    Write-RmnJournal "Démarrage (PowerShell $($PSVersionTable.PSVersion), config : $Config)"
    Write-RmnJournal "Destination : $($cfg.Destination)"
    if ($UneFois) {
        Invoke-RmnBalayage -Config $cfg | Out-Null
    } else {
        Start-RmnSurveillance -Config $cfg
    }
} catch {
    Write-RmnJournal "Erreur fatale : $($_.Exception.Message)" 'ERREUR'
    exit 1
} finally {
    $verrou.ReleaseMutex()
    $verrou.Dispose()
}
