# Instructions pour Claude Code

Réponds et commente en français.

## Projet

Synchronisation des données RMN de partages réseau vers un dossier local, pour n'importe quel membre d'un laboratoire. Tout réglage propre à un utilisateur vit dans `config/rmn.config.json` (modèle : `config/rmn.config.example.json`) ; aucune valeur personnelle dans le code.

- `src/RMNSync.psm1` : fonctions (`Read-RmnConfig`, `Get-RmnExperience`, `Get-RmnDestination`, `Test-RmnExperiencePrete`, `Copy-RmnExperience`, `Sync-RmnExperience`, `Invoke-RmnBalayage`, `Start-RmnSurveillance`).
- `src/RMN-Sync.ps1` : point d'entrée, verrou d'instance unique (mutex), journal.
- `scripts/Installer-Tache.ps1` : tâche planifiée (ouverture + déverrouillage de session) pour l'utilisateur courant.
- `legacy/` : ancien script, référence de comportement ; ne pas le modifier.

## Contraintes impératives

- **Windows PowerShell 5.1** obligatoire : pas de `??`, `?.`, `&&`, `||`, ternaire, `ForEach-Object -Parallel`, ni `Join-Path` à plus de deux arguments.
- `.ps1`/`.psm1` en **UTF-8 avec BOM**, fins de ligne CRLF.
- Ne jamais écraser, supprimer ni recopier une expérience locale existante ; ne jamais écrire sur les partages réseau.
- Copie via un dossier `.partiel` puis renommage (pas de dossier final incomplet).
- Toute nouvelle option : valeur par défaut dans `Read-RmnConfig`, entrée dans l'exemple JSON, ligne dans le tableau du README.

## Tests

`pwsh ./tests/Test-Depot.ps1` doit réussir avant toute fin de tâche. Ajouter un cas dans `tests/Test-Logique.ps1` pour chaque comportement modifié. La VM cloud n'a pas accès à `\\ul.ca`, au Planificateur ni à OneDrive : indiquer dans le PR ce qui doit être vérifié sur un poste Windows.
