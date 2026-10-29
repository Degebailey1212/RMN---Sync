# Mode d'emploi

**Démarrer manuellement :** double-cliquer sur `scripts\Lancer.cmd` (démarre la tâche planifiée ; aucun doublon possible).

**Mise à jour ponctuelle :** double-cliquer sur `scripts\Mise-a-jour.cmd`. Copie tout de suite les nouvelles expériences puis s'arrête ; fonctionne même si la synchronisation automatique tourne déjà.

**Journaux :** `%LOCALAPPDATA%\RMN\Logs`, un fichier `RMN_AAAA-MM-JJ.log` par jour, conservés 30 jours.

**Arrêter :** Planificateur de tâches → `RMN-Sync` → « Fin ».
**Ne plus démarrer automatiquement :** même tâche → « Désactiver ».
**Désinstaller :** `powershell -File .\scripts\Desinstaller-Tache.ps1` (aucune donnée n'est touchée).

**Changer un réglage :** modifier `config\rmn.config.json`, puis arrêter et relancer la tâche.

**Une expérience n'a pas été copiée ?**
- Le journal indique « en attente » : l'acquisition était récente ; elle sera copiée au prochain balayage (10 min par défaut).
- Le nom ne correspond pas au modèle : vérifier `PrefixeEchantillon` et `ModeleNomExperience`.
- Un dossier `…_400MHz.partiel` existe : une copie a été interrompue ; elle reprendra automatiquement.

**Remarques :**
- Une seule instance tourne par utilisateur, même lancée depuis VS Code.
- Une copie locale existante n'est jamais écrasée ni recopiée.
