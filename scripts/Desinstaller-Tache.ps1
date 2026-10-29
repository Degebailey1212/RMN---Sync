<#
.SYNOPSIS
    Arrête et supprime la tâche planifiée RMN-Sync (les données ne sont pas touchées).
#>
param([string]$NomTache = 'RMN-Sync')
$tache = Get-ScheduledTask -TaskName $NomTache -ErrorAction SilentlyContinue
if (-not $tache) { Write-Host "Aucune tâche « $NomTache »."; return }
Stop-ScheduledTask -TaskName $NomTache -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $NomTache -Confirm:$false
Write-Host "Tâche « $NomTache » supprimée."
