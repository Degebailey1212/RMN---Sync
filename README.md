# RMN Sync — version OneDrive (fonctionnelle)

Cette branche contient **le code qui fonctionne**, copié tel quel depuis
`OneDrive\RMN\RMN code` le 29 octobre 2026. Aucune ligne n'a été modifiée.

| Fichier | Rôle |
|---|---|
| `Master_code_RMN_watcher+Sync.ps1` | Script principal : balayage complet au démarrage et au retour du réseau, puis surveillance en temps réel (FileSystemWatcher) des dossiers RMN 300, 400 et 500 MHz. |
| `Sync_RMN.ps1` | Ancien script de synchronisation **ponctuelle** (un seul balayage, puis s'arrête). ⚠️ Son chemin de destination pointe encore vers `C:\Users\emili\OneDrive\RMN` et il recopie toutes les expériences à chaque passage. |
| `Automatisation_RMN/Demarrer_RMN.ps1` | Lanceur utilisé par la tâche planifiée ; journal dans `%LOCALAPPDATA%\RMN\Logs`. |
| `Automatisation_RMN/Lancer_RMN.cmd` | Démarre la tâche planifiée par double-clic. |
| `Automatisation_RMN/Tache_RMN_corrigee.xml` | Définition de la tâche planifiée (à importer dans le Planificateur). |
| `Automatisation_RMN/Mode_emploi.md` | Mode d'emploi. |

## Règle de nommage (à conserver)

Les dossiers sont reconnus par leur **début** de nom : `^EB1212-\d{2,3}-\d{2}`.
Tout ce qui suit est ignoré pour le nom local. Exemple :
`EB1212-071-36…` sur le 400 MHz → `RMN\EB1212-071\EB1212-071-36_400MHz`.

La version de la branche `main` exigeait que le nom s'arrête exactement après le numéro,
ce qui excluait les dossiers avec un suffixe : c'est la cause probable de son échec.
