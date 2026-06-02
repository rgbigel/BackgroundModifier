# =================================================================================================
#  Module:      SchedulerTools.psm1
#  Path:        .\Modules
#  Author:      Rolf Bercht
#  Version:     6.0.0
#  Changelog:
#      5.000  -  Header normalized for repository-wide uniformity.
# =================================================================================================

<# ============================================================================================
  Path:       D:\OneDrive\Git_Repositories\PS\BackgroundModifier\Source\Modules\SchedulerTools.psm1
  Module:     SchedulerTools.psm1
    Version:    6.0.0
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
        [string[]]$ScriptArguments = @(),
        [ValidateSet("Startup", "LogOn", "Daily")]
        [string]$TriggerType = "Startup",
        [string]$TriggerTime = "03:00",
        [ValidateSet("System", "Interactive")]
        [string]$RunAs = "System"
    )

    if (-not (Test-Path $ScriptPath)) {
        Write-Host "[ERROR] Cannot register task. Script not found: $ScriptPath"
        return $false
    }

    $actionArguments = @(
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ('`"{0}`"' -f $ScriptPath)
    )

    foreach ($scriptArgument in $ScriptArguments) {
        if ([string]::IsNullOrWhiteSpace($scriptArgument)) {
            continue
        }

        if ($scriptArgument.Contains(' ')) {
            $actionArguments += ('`"{0}`"' -f $scriptArgument)
        }
        else {
            $actionArguments += $scriptArgument
        }
    }

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ($actionArguments -join ' ')

    switch ($TriggerType) {
        "Startup" {
            $trigger = New-ScheduledTaskTrigger -AtStartup
        }
        "LogOn" {
            $trigger = New-ScheduledTaskTrigger -AtLogOn
        }
        default {
            $trigger = New-ScheduledTaskTrigger -Daily -At $TriggerTime
        }
    }

    try {
        $principal = switch ($RunAs) {
            "System" {
                New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
            }
            "Interactive" {
                New-ScheduledTaskPrincipal -GroupId "S-1-5-4" -RunLevel Limited
            }
        }

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force -ErrorAction Stop | Out-Null

        Write-Host "[OK] Scheduled task registered -> $TaskName ($TriggerType/$RunAs)"
        return $true
    }
    catch {
        Write-Host "[ERROR] Failed to register scheduled task: $($_.Exception.Message)"
        return $false
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

