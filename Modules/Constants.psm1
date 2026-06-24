<# ============================================================================================
  Path:       D:\Git_Repositories\BackgroundModifier\Modules
  Module:     Constants.psm1
  Version:    8.0.0
  Author:     Rolf Bercht

  Purpose:
      Provides shared constants for scripts and modules.

  Caller Contract: Read-only module. No state implications.
============================================================================================ #>

# --- Deployment Topology (Architecture.md Section 4) ---

# Runtime State Plane (C: drive for multi-boot stability)
$Global:RuntimeRoot = "C:\BackgroundMotives"
$Global:AssetsRoot  = "C:\BackgroundMotives\assets"
$Global:LogRoot     = "C:\BackgroundMotives\logs"

# Deployment Plane (non-repository runtime content)
$Global:DeploymentRoot = "D:\OneDrive\BTools\BackgroundModifier"
$Global:DeploymentModules = Join-Path $Global:DeploymentRoot "Modules"

# Shared Modules (cross-repository)
$Global:SharedModulesRoot = "D:\OneDrive\BTools\SharedModules"

# User Exposure Plane (launchers and user-facing commands)
$Global:UserExposureRoot = "D:\OneDrive\cmd"

# Inventory
$Global:InventoryRoot = "D:\OneDrive\BTools\Inventory"

