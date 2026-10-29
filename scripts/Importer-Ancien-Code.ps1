<#
.SYNOPSIS
    Copie les anciens scripts RMN depuis OneDrive dans legacy\ pour comparaison.
.EXAMPLE
    .\scripts\Importer-Ancien-Code.ps1
#>
param(
    [string]$Source = (Join-Path $env:USERPROFILE 'OneDrive\RMN\RMN code')
)
$ErrorActionPreference = 'Stop'
$cible = Join-Path (Split-Path -Parent $PSScriptRoot) 'legacy'
if (-not (Test-Path -LiteralPath $Source)) { throw "Dossier source introuvable : $Source" }

$fichiers = 'Master_code_RMN_watcher+Sync.ps1',
            'Automatisation_RMN\Demarrer_RMN.ps1',
            'Automatisation_RMN\Lancer_RMN.cmd',
            'Automatisation_RMN\Mode_emploi.md',
            'Automatisation_RMN\Tache_RMN_corrigee.xml'
foreach ($f in $fichiers) {
    $chemin = Join-Path $Source $f
    if (Test-Path -LiteralPath $chemin) {
        Copy-Item -LiteralPath $chemin -Destination $cible -Force
        Write-Host "Copié : $f" -ForegroundColor Green
    } else { Write-Warning "Absent : $f" }
}
