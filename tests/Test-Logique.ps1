<#
.SYNOPSIS
    Tests de la logique RMN-Sync sans réseau ni dépendance (dossiers simulés).
    Compatible PS 5.1 et PS 7. Code de sortie 1 en cas d'échec.
#>
param([switch]$SansSurveillance)
$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $racine 'src\RMNSync.psm1') -Force

$script:echecs = 0
function Verifier([string]$Nom, [bool]$Condition) {
    if ($Condition) { Write-Host "OK     $Nom" }
    else { Write-Host "ÉCHEC  $Nom" -ForegroundColor Red; $script:echecs++ }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("rmn-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$src400 = Join-Path $tmp 'reseau/RMN400DATA/Voyer'
$src500 = Join-Path $tmp 'reseau/RMN500DATA/Voyer'
$dest = Join-Path $tmp 'local'
New-Item -ItemType Directory -Path $src400, $src500 -Force | Out-Null

$cfgFichier = Join-Path $tmp 'config.json'
@{
    PrefixeEchantillon  = 'EB1212'
    Groupe              = 'Voyer'
    RacineReseau        = (Join-Path $tmp 'reseau')
    Appareils           = @(@{ Dossier = 'RMN400DATA'; Frequence = '400MHz' }, @{ Dossier = 'RMN500DATA'; Frequence = '500MHz' })
    Destination         = $dest
    StabiliteSecondes   = 0
    DossierJournaux     = (Join-Path $tmp 'logs')
    IntervalleVerificationReseauSecondes = 1
    DelaiApresDetectionSecondes = 1
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgFichier -Encoding UTF8

try {
    Write-Host '== Configuration ==' -ForegroundColor Cyan
    $cfg = Read-RmnConfig -Chemin $cfgFichier
    Verifier 'deux sources construites' (@($cfg.Sources).Count -eq 2)
    Verifier 'chemin source = racine/dossier/groupe' ($cfg.Sources[0].Chemin -eq (Join-Path (Join-Path (Join-Path $tmp 'reseau') 'RMN400DATA') 'Voyer'))
    Verifier 'valeur par défaut appliquée' ($cfg.BalayagePeriodiqueMinutes -eq 10)
    $exemple = Read-RmnConfig -Chemin (Join-Path $racine 'config/rmn.config.example.json')
    Verifier 'exemple fourni valide' (@($exemple.Sources).Count -eq 3)
    $erreur = $false
    try { Read-RmnConfig -Chemin (Join-Path $tmp 'absent.json') | Out-Null } catch { $erreur = $true }
    Verifier 'erreur claire si config absente' $erreur

    Write-Host "`n== Analyse des noms ==" -ForegroundColor Cyan
    $e = Get-RmnExperience -Nom 'EB1212-071-36' -Config $cfg
    Verifier 'EB1212-071-36 reconnu' ($null -ne $e)
    Verifier 'parent EB1212-071' ($e.Parent -eq 'EB1212-071')
    Verifier 'expérience 36' ($e.Experience -eq '36')
    Verifier 'autre préfixe ignoré' ($null -eq (Get-RmnExperience -Nom 'AB9999-001-1' -Config $cfg))
    Verifier 'nom sans numéro ignoré' ($null -eq (Get-RmnExperience -Nom 'EB1212-071' -Config $cfg))
    Verifier 'préfixe dans le texte ignoré' ($null -eq (Get-RmnExperience -Nom 'xEB1212-071-36' -Config $cfg))

    $d = Get-RmnDestination -Experience $e -Frequence '400MHz' -Config $cfg
    Verifier 'destination EB1212-071/EB1212-071-36_400MHz' ($d -eq (Join-Path (Join-Path $dest 'EB1212-071') 'EB1212-071-36_400MHz'))

    Write-Host "`n== Balayage ==" -ForegroundColor Cyan
    $exp1 = Join-Path $src400 'EB1212-071-36'
    New-Item -ItemType Directory -Path (Join-Path $exp1 'pdata/1') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $exp1 'acqus') -Value 'acq'
    Set-Content -LiteralPath (Join-Path $exp1 'pdata/1/procs') -Value 'proc'
    New-Item -ItemType Directory -Path (Join-Path $src500 'Autre-dossier') -Force | Out-Null
    $b = Invoke-RmnBalayage -Config $cfg
    $copie = Join-Path (Join-Path $dest 'EB1212-071') 'EB1212-071-36_400MHz'
    Verifier 'une expérience copiée' ($b.Copie -eq 1)
    Verifier 'sous-dossiers copiés' (Test-Path -LiteralPath (Join-Path $copie 'pdata/1/procs'))
    Verifier 'aucun dossier .partiel restant' (-not (Test-Path -LiteralPath "$copie.partiel"))
    Verifier 'dossier non conforme ignoré' ($b.Ignore -eq 1)

    Set-Content -LiteralPath (Join-Path $copie 'acqus') -Value 'MODIFIÉ LOCALEMENT'
    $b2 = Invoke-RmnBalayage -Config $cfg
    Verifier 'deuxième balayage : rien recopié' ($b2.Copie -eq 0 -and $b2.Existe -eq 1)
    Verifier 'copie locale jamais écrasée' ((Get-Content -LiteralPath (Join-Path $copie 'acqus')) -eq 'MODIFIÉ LOCALEMENT')

    Write-Host "`n== Stabilité et fichiers requis ==" -ForegroundColor Cyan
    $cfg.StabiliteSecondes = 3600
    $exp2 = Join-Path $src400 'EB1212-072-1'
    New-Item -ItemType Directory -Path $exp2 -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $exp2 'acqus') -Value 'en cours'
    Verifier 'acquisition récente = en attente' ((Sync-RmnExperience -CheminSource $exp2 -Frequence '400MHz' -Config $cfg) -eq 'EnAttente')
    $cfg.StabiliteSecondes = 0
    $cfg.FichiersRequis = @('fid|ser')
    Verifier 'fichier requis absent = en attente' ((Sync-RmnExperience -CheminSource $exp2 -Frequence '400MHz' -Config $cfg) -eq 'EnAttente')
    Set-Content -LiteralPath (Join-Path $exp2 'ser') -Value 'x'
    Verifier 'alternative fid|ser acceptée' ((Sync-RmnExperience -CheminSource $exp2 -Frequence '400MHz' -Config $cfg) -eq 'Copie')
    $cfg.FichiersRequis = @()

    Write-Host "`n== Source inaccessible ==" -ForegroundColor Cyan
    $cfgPanne = Read-RmnConfig -Chemin $cfgFichier
    $cfgPanne.Sources = @([pscustomobject]@{ Chemin = (Join-Path $tmp 'nexiste/pas'); Frequence = '300MHz' })
    $b3 = Invoke-RmnBalayage -Config $cfgPanne
    Verifier 'pas de plantage si réseau absent' ($b3.Copie -eq 0)

    if (-not $SansSurveillance) {
        Write-Host "`n== Surveillance en temps réel ==" -ForegroundColor Cyan
        $exe = (Get-Process -Id $PID).Path
        $entree = Join-Path $racine 'src/RMN-Sync.ps1'
        $style = @{ NoNewWindow = $true }
        if ($env:OS -eq 'Windows_NT') { $style = @{ WindowStyle = 'Hidden' } }
        $p = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-File', "`"$entree`"", '-Config', "`"$cfgFichier`"") -PassThru @style
        Start-Sleep -Seconds 6
        $p2 = Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-File', "`"$entree`"", '-Config', "`"$cfgFichier`"") -PassThru @style
        $p2.WaitForExit(15000) | Out-Null
        Verifier 'deuxième instance refusée' ($p2.HasExited -and $p2.ExitCode -eq 0)

        $exp3 = Join-Path $src500 'EB1212-080-5'
        New-Item -ItemType Directory -Path $exp3 -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $exp3 'fid') -Value 'data'
        $attendu = Join-Path (Join-Path $dest 'EB1212-080') 'EB1212-080-5_500MHz'
        $ok = $false
        for ($t = 0; $t -lt 20 -and -not $ok; $t++) { Start-Sleep -Seconds 1; $ok = Test-Path -LiteralPath (Join-Path $attendu 'fid') }
        Verifier 'nouvelle expérience détectée et copiée' $ok

        # Coupure réseau simulée puis retour avec une nouvelle expérience
        $cache = "$src500-coupe"
        Move-Item -LiteralPath $src500 -Destination $cache
        Start-Sleep -Seconds 4
        New-Item -ItemType Directory -Path (Join-Path $cache 'EB1212-081-2') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $cache 'EB1212-081-2/fid') -Value 'data'
        Move-Item -LiteralPath $cache -Destination $src500
        $attendu2 = Join-Path (Join-Path $dest 'EB1212-081') 'EB1212-081-2_500MHz'
        $ok2 = $false
        for ($t = 0; $t -lt 20 -and -not $ok2; $t++) { Start-Sleep -Seconds 1; $ok2 = Test-Path -LiteralPath (Join-Path $attendu2 'fid') }
        Verifier 'reprise après coupure réseau' $ok2

        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
        $journal = Get-ChildItem -LiteralPath (Join-Path $tmp 'logs') -Filter 'RMN_*.log' | Select-Object -First 1
        Verifier 'journal écrit' ($null -ne $journal -and (Get-Content -LiteralPath $journal.FullName -Raw) -match 'Surveillance active')
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:echecs -gt 0) { Write-Host "$script:echecs test(s) en échec." -ForegroundColor Red; exit 1 }
Write-Host 'Tous les tests de logique passent.' -ForegroundColor Green
exit 0
