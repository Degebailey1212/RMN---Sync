# Instructions pour Claude Code (branche version-onedrive)

Réponds et commente en français.

Cette branche est la **référence fonctionnelle** : `Master_code_RMN_watcher+Sync.ps1` est en
production sur le poste de l'utilisateur via la tâche planifiée « Master_code_RMN_watcher+Sync ».

Règles :
- Ne pas changer le comportement du script principal sans que l'utilisateur l'ait demandé.
- Conserver exactement la reconnaissance des noms : correspondance sur le **début** du nom
  (`^EB1212-\d{2,3}-\d{2}`, sans ancre de fin), nom local = `$matches[0]` + `_<freq>MHz`,
  dossier parent = nom jusqu'au dernier tiret.
- Compatibilité Windows PowerShell 5.1 obligatoire.
- Ne jamais écraser ni supprimer de données ; ne jamais écrire sur les partages réseau.
- Toute évolution (configuration par utilisateur, mise à jour ponctuelle…) se fait par petites
  étapes, chacune vérifiable par l'utilisateur sur son poste Windows.
