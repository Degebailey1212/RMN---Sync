# Lancement automatique de RMN

La tache existante `Master_code_RMN_watcher+Sync`, dans la racine de la bibliotheque du Planificateur de taches, a ete corrigee.

Elle demarre a l'ouverture de session et au deverrouillage de la session ULAVAL\EMBAI9, en arriere-plan. Si elle fonctionne deja, le Planificateur conserve l'instance en cours. Le script attend lui-meme le retour du reseau universitaire ou du VPN.

Le script principal `Master_code_RMN_watcher+Sync.ps1` est conserve sans modification. `Demarrer_RMN.ps1` lance ce script et ajoute un journal de diagnostic.

## Utilisation

- Pour demarrer manuellement : double-cliquer sur `Lancer_RMN.cmd`.
- Pour consulter les journaux : ouvrir `%LOCALAPPDATA%\RMN\Logs` et lire le fichier RMN le plus recent.
- Pour arreter : ouvrir le Planificateur de taches, selectionner `Master_code_RMN_watcher+Sync`, puis cliquer sur **Fin**.
- Pour suspendre le lancement automatique : cliquer sur **Desactiver**. Pour arreter aussi l'instance en cours, utiliser **Fin**.

L'etat **En cours d'execution** et le code `0x41301` sont normaux : le script reste actif pour surveiller les nouveaux dossiers. Aucun editeur n'est necessaire. Eviter de lancer en parallele une autre copie du script principal dans Visual Studio Code.

## Configuration de l'action

Programme : `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`

Arguments :

```text
-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\EMBAI9\OneDrive\RMN\RMN code\Automatisation_RMN\Demarrer_RMN.ps1"
```

Demarrer dans : `C:\Users\EMBAI9\OneDrive\RMN\RMN code`

La tache s'execute uniquement lorsque cet utilisateur est connecte, avec ses droits habituels et sans mot de passe enregistre. Le parametre d'execution Bypass ne concerne que cette invocation PowerShell. Elle fonctionne sur batterie, n'a pas de duree maximale et tente jusqu'a trois redemarrages a une minute d'intervalle en cas d'erreur fatale.

## Fichiers de sauvegarde

- `Tache_RMN_avant_correction.xml` : configuration initiale.
- `Tache_RMN_corrigee.xml` : configuration corrigee, utilisable avec **Importer une tache**.

L'ancienne configuration utilisait le type de connexion Password : sa reimportation peut demander le mot de passe Windows. Le XML ne contient aucun mot de passe.

## Verification

Le lancement depuis le Planificateur a atteint le serveur reseau, effectue le balayage et demarre les watchers. Le declencheur au deverrouillage est configure ; aucun verrouillage force du poste n'a ete effectue pour le tester.

Documentation Microsoft :
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_powershell_exe?view=powershell-5.1
- https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-sessionstatechangetrigger-triggergroup-element
