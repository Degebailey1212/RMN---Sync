# RMN Sync

Copie automatiquement les expériences RMN depuis les partages réseau des appareils vers un dossier local, puis surveille l'arrivée de nouvelles expériences. Tout ce qui est propre à un utilisateur (préfixe d'échantillon, groupe, appareils, destination) se règle dans un fichier de configuration, sans toucher au code.

## Installation pour un nouvel utilisateur (Windows)

1. Cloner ou télécharger le dépôt.
2. Copier `config\rmn.config.example.json` en `config\rmn.config.json` et l'adapter (au minimum `PrefixeEchantillon` et `Groupe`).
3. Tester un balayage unique :
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\src\RMN-Sync.ps1 -UneFois
   ```
4. Installer le démarrage automatique (ouverture et déverrouillage de session) :
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\Installer-Tache.ps1
   ```
   Ajouter `-DesactiverAncienneTache` si l'ancienne tâche `Master_code_RMN_watcher+Sync` existe.

Voir `docs/Mode_emploi.md` pour l'utilisation quotidienne.

## Configuration

| Clé | Rôle | Défaut |
|---|---|---|
| `PrefixeEchantillon` | Préfixe des dossiers à copier (ex. `EB1212`) | obligatoire |
| `Groupe` | Sous-dossier du groupe sur chaque appareil (ex. `Voyer`) | vide |
| `RacineReseau` | Racine commune des partages | — |
| `Appareils` | Liste `{ "Dossier", "Frequence" }`, ou `{ "Chemin", "Frequence" }` pour un chemin complet | obligatoire |
| `Destination` | Dossier local (variables `%USERPROFILE%` etc. acceptées) | obligatoire |
| `ModeleNomExperience` | Expression régulière ; `{Prefixe}` est remplacé, groupe `Parent` = dossier parent | `^(?<Parent>{Prefixe}-[^-]+)-(?<Experience>\d+)$` |
| `FormatDossierLocal` | Nom du dossier copié : `{Nom}`, `{Parent}`, `{Experience}`, `{Frequence}` | `{Nom}_{Frequence}` |
| `StabiliteSecondes` | Copie seulement quand aucun fichier n'a changé depuis ce délai (acquisition terminée) | 60 |
| `FichiersRequis` | Fichiers devant exister avant copie ; `"fid\|ser"` = l'un ou l'autre | aucun |
| `DelaiApresDetectionSecondes` | Attente après détection d'un nouveau dossier | 3 |
| `IntervalleVerificationReseauSecondes` | Fréquence de vérification du réseau | 30 |
| `BalayagePeriodiqueMinutes` | Balayage de rattrapage (événements manqués) | 10 |
| `DossierJournaux` / `JoursConservationJournaux` | Emplacement et durée de conservation des journaux | `%LOCALAPPDATA%\RMN\Logs` / 30 |

## Structure

```
src/RMN-Sync.ps1        point d'entrée (instance unique, journal, boucle)
src/RMNSync.psm1        fonctions (configuration, analyse des noms, copie, surveillance)
config/                 modèle de configuration
scripts/                installation / désinstallation de la tâche, import de l'ancien code
tests/                  Test-Depot.ps1 (tout), Test-Logique.ps1 (dossiers simulés)
legacy/                 ancien script, pour comparaison seulement
```

## Tests

```powershell
powershell -File .\tests\Test-Depot.ps1     # Windows PowerShell 5.1
pwsh ./tests/Test-Depot.ps1                 # PowerShell 7, y compris Linux
```
Les tests simulent les partages réseau avec des dossiers temporaires : détection, copie, non-écrasement, attente de stabilité, coupure et retour du réseau, instance unique.
