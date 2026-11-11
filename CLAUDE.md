# Instructions pour Claude Code (branche version-onedrive)

Réponds et commente en français.

## Où est le code

- `Code MAJ/moteur/Demarrer_ecoute_RMN.ps1` : **le code en production**. Trois modes :
  sans paramètre (assistant interactif), `-Ecoute` (boucle, lancée par la tâche planifiée),
  `-UneFois` (mise à jour complète puis arrêt).
- `Code MAJ/*.cmd` : lanceurs double-cliquables. Ils doivent rester en ASCII, fins de ligne CRLF.
- `Anciens codes/` : référence historique. Ne pas modifier.

Le dépôt est le miroir de `OneDrive\RMN\RMN code` sur le poste de l'utilisateur ; la tâche
planifiée pointe vers le fichier OneDrive, pas vers le dépôt. Toute modification ici doit être
recopiée dans OneDrive pour prendre effet.

## Règles à ne pas casser

- Reconnaissance des noms sur le **début** du nom (`^<Prefixe>-\d{2,3}-\d{2}`, sans ancre de fin) ;
  nom local = correspondance + `_<freq>MHz` ; dossier parent = nom jusqu'au dernier tiret.
- Copie incrémentale uniquement ; jamais de suppression ni de `/PURGE` ou `/MIR` ;
  ne jamais écraser un fichier local plus récent (`/XO`) ; ne jamais écrire sur le réseau.
- Compatibilité **Windows PowerShell 5.1** : pas de `??`, `?.`, `&&`, `||`, ternaire.
- `.ps1` en UTF-8 **avec BOM** (accents), fins de ligne CRLF.
- Toute valeur propre à un utilisateur reste dans `$Config`, au début du script.
- Le lancement manuel doit toujours afficher séparément « écoute en marche » et
  « démarrage automatique installé », et proposer l'installation si elle manque.

## Tests

La VM cloud n'a ni `\\ul.ca`, ni robocopy, ni Planificateur. Tester avec des dossiers simulés :
`pwsh -File "Code MAJ/moteur/Demarrer_ecoute_RMN.ps1" -UneFois -RacineReseau <dossier> -Destination <dossier>`
(les paramètres `-CalmeSecondes` et `-VerifReseauSecondes` raccourcissent les délais).
Indiquer dans chaque PR ce qui reste à vérifier sur le poste Windows.
