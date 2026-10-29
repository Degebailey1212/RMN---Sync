#!/usr/bin/env bash
# Script de configuration pour l'environnement Claude Code sur le web.
# Installe PowerShell 7 et Pester pour pouvoir tester les scripts sous Linux.
set -euo pipefail

if ! command -v pwsh >/dev/null 2>&1; then
  VERSION="7.4.6"
  curl -fsSL -o /tmp/pwsh.tar.gz \
    "https://github.com/PowerShell/PowerShell/releases/download/v${VERSION}/powershell-${VERSION}-linux-x64.tar.gz"
  sudo mkdir -p /opt/microsoft/powershell/7
  sudo tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7
  sudo chmod +x /opt/microsoft/powershell/7/pwsh
  sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh
fi

pwsh -NoProfile -Command '
  if (-not (Get-Module -ListAvailable Pester | Where-Object Version -ge "5.0")) {
    Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
  }
  if (-not (Get-Module -ListAvailable PSScriptAnalyzer)) {
    Install-Module PSScriptAnalyzer -Scope CurrentUser -Force
  }
'
pwsh --version
