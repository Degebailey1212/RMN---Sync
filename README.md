# RMN Sync

Copie automatiquement les données RMN (300, 400 et 500 MHz) du réseau de l'Université Laval
vers `OneDrive\RMN`, et garde la copie à jour pendant et après les acquisitions.

Cette branche reflète exactement le dossier `OneDrive\RMN\RMN code` (état du 11 novembre 2026).

## Code MAJ — la version à utiliser

| Fichier | Rôle |
|---|---|
| `Code MAJ/Demarrer ecoute RMN.cmd` | Double-clic : affiche l'état (écoute en marche ? démarrage automatique installé ?), propose d'installer le démarrage automatique et lance l'écoute en arrière-plan. |
| `Code MAJ/Mise a jour RMN.cmd` | Double-clic : mise à jour complète immédiate, puis s'arrête. Fonctionne même si l'écoute tourne. |
| `Code MAJ/moteur/Demarrer_ecoute_RMN.ps1` | Le code. Les réglages (préfixe, groupe, appareils, destination, délais) sont regroupés au début, dans `$Config`. |

Les `.cmd` lancent PowerShell avec `-ExecutionPolicy Bypass` : un double-clic sur un `.ps1`
est bloqué par Windows, et la fenêtre se fermait avant qu'on puisse lire l'erreur.

### Ce que fait l'écoute

- **Même classement que l'ancien script** : le nom est reconnu par son *début*
  (`^EB1212-\d{2,3}-\d{2}`) ; `EB1212-071-36_1H` sur le 400 MHz devient
  `RMN\EB1212-071\EB1212-071-36_400MHz`.
- **Copie incrémentale** (robocopy `/E /XO /XX`) : seuls les fichiers nouveaux ou plus récents
  sont copiés. Une expérience ajoutée 8 h plus tard dans un dossier déjà copié est récupérée.
- **Surveillance de l'intérieur des dossiers** (`IncludeSubdirectories`) : un dossier actif est
  recopié au moins toutes les 10 minutes, puis une dernière fois après 60 s de calme.
- **Rattrapage** toutes les 10 minutes des dossiers modifiés depuis moins de 48 h, et balayage
  à chaque retour du réseau (appareil par appareil).
- **Aucune suppression**, ni sur le réseau ni en local ; un fichier local plus récent
  (retraité dans TopSpin) n'est jamais écrasé.
- Une seule écoute à la fois (mutex). Journaux : `%LOCALAPPDATA%\RMN\Logs`.

### Démarrage automatique

`Demarrer ecoute RMN.cmd` crée la tâche planifiée **« RMN - Ecoute et mise a jour »**
(ouverture et déverrouillage de session) et désactive, sans la supprimer, l'ancienne tâche
`Master_code_RMN_watcher+Sync`.

Vérification :

```powershell
foreach ($n in 'RMN - Ecoute et mise a jour','Master_code_RMN_watcher+Sync') { $t = Get-ScheduledTask -TaskName $n -ErrorAction SilentlyContinue; if ($t) { "$n  ->  $($t.State)" } else { "$n  ->  n'existe pas" } }
```

Attendu : la nouvelle tâche en `Ready` ou `Running`, l'ancienne en `Disabled`.

## Anciens codes

`Anciens codes/` contient les scripts d'origine, inchangés, pour référence
(`Master_code_RMN_watcher+Sync.ps1`, `Sync_RMN.ps1`, `Automatisation_RMN/`).
Limite connue de l'ancien script : un dossier déjà copié était ignoré pour toujours, donc les
expériences ajoutées plus tard dans le même dossier n'étaient jamais récupérées.

## État des tests

Testé sur dossiers simulés sous PowerShell 7 (Linux, sans robocopy) : nom avec suffixe,
nouvelle expérience dans un dossier existant, fichier qui grossit, nouveau dossier, fichier
local plus récent conservé, deux lancements simultanés, mise à jour pendant l'écoute.
Sur le poste Windows : mise à jour ponctuelle et lancement de l'écoute confirmés par l'utilisateur.
