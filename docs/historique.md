# Historique

## 9 octobre 2026 — Automatisation par le Planificateur de tâches
- Tâche `Master_code_RMN_watcher+Sync` corrigée : lancement via `powershell.exe -File` au lieu du `.ps1` directement.
- Déclencheurs : ouverture et déverrouillage de session ; exécution seulement quand l'utilisateur est connecté, sans mot de passe enregistré.
- Autorisée sur batterie, sans durée maximale, 3 redémarrages espacés d'une minute, aucune nouvelle instance si déjà active.
- Ajout de `Demarrer_RMN.ps1` (journal dans `%LOCALAPPDATA%\RMN\Logs`) et `Lancer_RMN.cmd`.
- Script principal inchangé (empreinte SHA-256 vérifiée).
- Le déclencheur au déverrouillage n'a pas été testé par un verrouillage réel.

## 29 octobre 2026 — Version universelle
- Réécriture en module (`src/RMNSync.psm1`) + point d'entrée (`src/RMN-Sync.ps1`), configuration JSON par utilisateur.
- Copie via `.partiel` puis renommage ; attente de stabilité avant copie ; balayage périodique de rattrapage.
- Gestion du réseau source par source ; instance unique par mutex (aussi depuis VS Code).
- Installation de la tâche par script pour l'utilisateur courant ; journaux quotidiens avec rotation.
- Réécrit à partir de la description du comportement : à valider contre `legacy/` sur un poste Windows.
