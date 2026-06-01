# =================================================================================================
#  Module:      SchedulerTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     5.000
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\SchedulerTools.psm1
  Module:     SchedulerTools.psm1
  Version:    5.000
  Author:     Rolf Bercht

  Purpose:
      Helper functions for creating, updating, and removing scheduled tasks
      used by the BackgroundModifier automation workflow.

   Change Log:
       5.000  -  Initial module creation for Consolidated Architecture (scheduled tasks)
============================================================================================ #>

function Register-BackgroundTask {
    param(
        [string]$TaskName,
        [string]$ScriptPath,
        [string]$TriggerTime = "03:00"
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[ERROR] Cannot register task. Script not found: $ScriptPath"
        return
    }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
    $trigger = New-ScheduledTaskTrigger -Daily -At $TriggerTime

    try {
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Force | Out-Null
        Write-Host "[OK] Scheduled task registered -> $TaskName at $TriggerTime"
    }
    catch {
        Write-Host "[ERROR] Failed to register scheduled task: $($_.Exception.Message)"
    }
}

function Unregister-BackgroundTask {
    param([string]$TaskName)

    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "[OK] Scheduled task removed -> $TaskName"
    }
    catch {
        Write-Host "[WARN] Could not remove task or task not found: $TaskName"
    }
}

function Test-BackgroundTask {
    param([string]$TaskName)

    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    return ($task -ne $null)
}
Export-ModuleMember -Function *
