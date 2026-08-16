<#
Module: RepoQualityGates.psm1
Purpose: Local quality gate assertions for BackgroundModifier.
Path: tools/QualityGates/RepoQualityGates.psm1
Authors: Rolf
Version: 1.0.0
Changelog:
- 2026-08-16: Initial quality gate module instantiated.
#>

function Assert-RepoStructure {
  [CmdletBinding()]
  param([string]$RepoRoot)

  $requiredPaths = @(
    (Join-Path $RepoRoot 'docs\README.md'),
    (Join-Path $RepoRoot '.lcm\config.json'),
    (Join-Path $RepoRoot '.lcm\overrides.json'),
    (Join-Path $RepoRoot '.vscode\settings.json')
  )

  foreach ($req in $requiredPaths) {
    if (-not (Test-Path -LiteralPath $req)) {
      throw "Missing required repository structure file: $req"
    }
  }

  return [pscustomobject]@{
    Status = 'OK'
    Structure = 'Valid'
    CheckedFiles = $requiredPaths.Count
  }
}

function Assert-RepoFormatting {
  [CmdletBinding()]
  param([string]$RepoRoot)

  $files = Get-ChildItem -Path $RepoRoot -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and $_.FullName -notmatch '\\\.agents\\rules\\core\\'
  }

  $issues = @()
  foreach ($f in $files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
      $issues += "$($f.Name): Contains UTF-8 BOM"
    }
  }

  if ($issues.Count -gt 0) {
    throw ("Formatting violations detected: " + ($issues -join '; '))
  }

  return [pscustomobject]@{
    Status = 'OK'
    Formatting = 'Valid'
    ScannedFiles = $files.Count
  }
}

function Assert-RepoGovernanceLinks {
  [CmdletBinding()]
  param([string]$RepoRoot)

  $requiredLinks = @(
    (Join-Path $RepoRoot '.agents\rules\core'),
    (Join-Path $RepoRoot 'AGENTS.md')
  )

  foreach ($link in $requiredLinks) {
    if (-not (Test-Path -LiteralPath $link)) {
      throw "Missing governance link: $link"
    }
  }

  return [pscustomobject]@{
    Status = 'OK'
    GovernanceLinks = 'Valid'
  }
}

Export-ModuleMember -Function Assert-RepoStructure, Assert-RepoFormatting, Assert-RepoGovernanceLinks
