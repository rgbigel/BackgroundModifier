<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     Logging.psm1
    Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides simple, reusable logging utilities for scripts and modules.
============================================================================================ #>

function Write-Log {
    param(
        [string]$Message,
        [string]$LogFile
    )

    if (-not $LogFile) {
        return
    }

    $Message | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Write-ContentMutationLog {
    param(
        [string]$Operation,
        [string]$Path,
        [string]$Target,
        [string]$ScriptName,
        [string]$Outcome = "OK"
    )

    $root = "C:\BackgroundMotives"
    $logRoot = "C:\BackgroundMotives\logs"
    $auditLog = Join-Path $logRoot "ContentMutation.log"

    function Resolve-FullPathOrEmpty {
        param([string]$InputPath)
        if ([string]::IsNullOrWhiteSpace($InputPath)) { return "" }
        try {
            return [System.IO.Path]::GetFullPath($InputPath)
        }
        catch {
            return $InputPath
        }
    }

    $resolvedPath = Resolve-FullPathOrEmpty -InputPath $Path
    $resolvedTarget = Resolve-FullPathOrEmpty -InputPath $Target

    $inScope = $false
    foreach ($candidate in @($resolvedPath, $resolvedTarget)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
        if ($candidate.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase) -and
            -not $candidate.StartsWith($logRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $inScope = $true
            break
        }
    }

    if (-not $inScope) {
        return
    }

    try {
        if (-not (Test-Path $logRoot)) {
            New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        }

        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        $origin = if ($ScriptName) { $ScriptName } else { "unknown" }
        $line = "[{0}] [{1}] [{2}] Op={3}; Path={4}; Target={5}" -f $timestamp, $origin, $Outcome, $Operation, $resolvedPath, $resolvedTarget
        Add-Content -Path $auditLog -Value $line -Encoding UTF8
    }
    catch {
        # Never fail main flow because of audit logging.
    }
}

Export-ModuleMember -Function Write-Log, Write-ContentMutationLog

