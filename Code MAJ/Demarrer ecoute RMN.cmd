@echo off
title Demarrer l'ecoute RMN
rem Double-cliquez pour verifier le reseau, installer le demarrage automatique et lancer l'ecoute.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0moteur\Demarrer_ecoute_RMN.ps1"
if errorlevel 1 (
  echo.
  echo Une erreur s'est produite. Faites une capture d'ecran de cette fenetre.
  pause
)
