# Lance le script RMN existant et conserve un journal local.
$ErrorActionPreference = 'Continue'
$mainScript = Join-Path (Split-Path -Parent $PSScriptRoot) 'Master_code_RMN_watcher+Sync.ps1'
$logDirectory = Join-Path $env:LOCALAPPDATA 'RMN\Logs'
$transcriptStarted = $false
$exitCode = 0

try {
    if (-not (Test-Path -LiteralPath $mainScript -PathType Leaf)) {
        throw "Script RMN introuvable : $mainScript"
    }
    New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop | Out-Null
    $logPath = Join-Path $logDirectory ('RMN_{0}_{1}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss'), $PID)
    Start-Transcript -LiteralPath $logPath -ErrorAction Stop | Out-Null
    $transcriptStarted = $true
    Write-Host ('[LANCEMENT] {0} | {1} | PowerShell {2} | PID {3}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), [Security.Principal.WindowsIdentity]::GetCurrent().Name, $PSVersionTable.PSVersion, $PID)
    Set-Location -LiteralPath (Split-Path -Parent $mainScript)
    # Le point execute le script dans la session courante, comme dans l'editeur.
    . $mainScript
}
catch {
    Write-Error -ErrorRecord $_ -ErrorAction Continue
    $exitCode = 1
}
finally {
    if ($transcriptStarted) { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
}
exit $exitCode
