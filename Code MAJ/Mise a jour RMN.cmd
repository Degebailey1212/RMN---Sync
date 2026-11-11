@echo off
title Mise a jour RMN
rem Double-cliquez pour copier tout de suite les nouvelles experiences, puis s'arreter.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0moteur\Demarrer_ecoute_RMN.ps1" -UneFois
echo.
pause
