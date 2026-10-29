<#
.SYNOPSIS
    Vérifications rapides : syntaxe PowerShell, encodage UTF-8 BOM, JSON de configuration,
    absence d'identifiants personnels codés en dur. Compatible PS 5.1 et PS 7.
#>
$ErrorActionPreference = 'Stop'
$racine = Split-Path -Parent $PSScriptRoot
$echecs = 0
$avert  = 0

Write-Host '== Syntaxe PowerShell ==' -ForegroundColor Cyan
Get-ChildItem -Path $racine -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notmatch '[\\/]legacy[\\/]' } | ForEach-Object {
    $tokens = $null; $erreurs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$erreurs) | Out-Null
    if ($erreurs.Count -gt 0) {
        $echecs++
        Write-Host "ÉCHEC  $($_.Name)" -ForegroundColor Red
        $erreurs | ForEach-Object { Write-Host "   ligne $($_.Extent.StartLineNumber) : $($_.Message)" }
    } else {
        Write-Host "OK     $($_.Name)"
    }

    # Encodage : un script avec accents doit avoir un BOM pour PS 5.1
    $octets = [System.IO.File]::ReadAllBytes($_.FullName)
    $bom = ($octets.Length -ge 3 -and $octets[0] -eq 0xEF -and $octets[1] -eq 0xBB -and $octets[2] -eq 0xBF)
    $nonAscii = $false
    foreach ($o in $octets) { if ($o -gt 127) { $nonAscii = $true; break } }
    if ($nonAscii -and -not $bom) {
        $echecs++
        Write-Host "ÉCHEC  $($_.Name) contient des accents sans BOM UTF-8 (illisible par PS 5.1)" -ForegroundColor Red
    }

    # Opérateurs propres à PowerShell 7
    $texte = [System.IO.File]::ReadAllText($_.FullName)
    if ($texte -match '\?\?=?|\?\.|ForEach-Object\s+-Parallel') {
        $avert++
        Write-Host "AVERT  $($_.Name) semble utiliser une syntaxe PS 7 uniquement" -ForegroundColor Yellow
    }

    # Identifiants personnels codés en dur (sauf dans scripts/ et tests/)
    if ($_.FullName -notmatch '[\\/](tests|scripts)[\\/]' -and $texte -match 'EMBAI9') {
        $avert++
        Write-Host "AVERT  $($_.Name) contient un identifiant utilisateur codé en dur" -ForegroundColor Yellow
    }
}

Write-Host "`n== Configuration ==" -ForegroundColor Cyan
Get-ChildItem -Path (Join-Path $racine 'config') -Filter *.json | ForEach-Object {
    try {
        $cfg = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($cle in 'PrefixeEchantillon', 'RacineReseau', 'Appareils', 'Destination') {
            if (-not $cfg.$cle) { throw "clé manquante : $cle" }
        }
        Write-Host "OK     $($_.Name)"
    } catch {
        $echecs++
        Write-Host "ÉCHEC  $($_.Name) : $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n== Tests de logique ==" -ForegroundColor Cyan
$exe = (Get-Process -Id $PID).Path
& $exe -NoProfile -File (Join-Path $PSScriptRoot 'Test-Logique.ps1')
if ($LASTEXITCODE -ne 0) { $echecs++ }

Write-Host ""
if ($echecs -gt 0) {
    Write-Host "$echecs échec(s), $avert avertissement(s)." -ForegroundColor Red
    exit 1
}
Write-Host "Tout est correct ($avert avertissement(s))." -ForegroundColor Green
exit 0
