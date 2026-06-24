<# ============================================================================================
    Path:       D:\Git_Repositories\BackgroundModifier\Modules
    Module:     FileTools.psm1
    Version:    8.0.1
    Author:     Rolf Bercht

    Purpose:
        Provides file system utility functions for hashing and content comparison.
        Atomic functions used for image state tracking and change detection.

  Caller Contract (Module-Caller State Update Responsibility):
    This module computes hashes but does NOT modify state.json. Caller is responsible for:
    - Get-FileHashOrNull: Safe to call; returns hash or null; read-only
    - If hash is used for state tracking: Caller must store hash in state.json with timestamp and source
    - Common use: Image state tracking; caller must update state with hash and appliedAtUtc
    - This module does NOT update state; caller owns artifact tracking
============================================================================================ #>

function Get-FileHashOrNull {
    <#
    .SYNOPSIS
        Computes SHA256 hash of a file, returning null on error.
    .DESCRIPTION
        Returns file hash or null if file missing or hash computation fails.
        Never throws exceptions; suitable for error-tolerant comparison workflows.
    .PARAMETER Path
        Path to file to hash.
    .OUTPUTS
        [string] SHA256 hash value or $null if unavailable.
    #>
    param(
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    try {
        return (Get-FileHash -Path $Path -Algorithm SHA256).Hash
    }
    catch {
        return $null
    }
}

function Test-FileContentEqual {
    <#
    .SYNOPSIS
        Compares file contents by SHA256 hash.
    .DESCRIPTION
        Compares two files by hash to detect content changes.
        Returns false if either file missing or hash unavailable.
    .PARAMETER PathA
        First file path to compare.
    .PARAMETER PathB
        Second file path to compare.
    .OUTPUTS
        [bool] True if both files exist and have identical content, false otherwise.
    #>
    param(
        [string]$PathA,
        [string]$PathB
    )

    $hashA = Get-FileHashOrNull -Path $PathA
    $hashB = Get-FileHashOrNull -Path $PathB

    if (-not $hashA -or -not $hashB) {
        return $false
    }

    return ($hashA -eq $hashB)
}

Export-ModuleMember -Function @(
    'Get-FileHashOrNull',
    'Test-FileContentEqual'
)
