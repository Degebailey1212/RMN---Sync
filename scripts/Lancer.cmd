@echo off
rem Demande le demarrage de la tache planifiee (sans creer de doublon).
schtasks /run /tn "RMN-Sync"
