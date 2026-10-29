@echo off
rem Mise a jour ponctuelle : copie tout de suite les nouvelles experiences, puis s'arrete.
rem Fonctionne meme si la synchronisation automatique tourne deja.
cd /d "%~dp0.."
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\src\RMN-Sync.ps1" -UneFois
echo.
pause
