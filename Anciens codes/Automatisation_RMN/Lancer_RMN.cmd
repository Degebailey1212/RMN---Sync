@echo off
"%SystemRoot%\System32\schtasks.exe" /Run /TN "\Master_code_RMN_watcher+Sync"
if errorlevel 1 (
    echo Le demarrage de la tache RMN a echoue. Consulter le Planificateur de taches.
    pause
)
