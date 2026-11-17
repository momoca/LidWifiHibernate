#Requires -RunAsAdministrator
param([switch]$Undo)
$ErrorActionPreference='Stop'
$name='MT7922-Lid-Auto'
$dir=Join-Path $env:ProgramFiles $name
$bin=Join-Path $dir 'LidWifiHibernate.exe'
function Set-LidAction([int]$value) {
    foreach($option in '/setacvalueindex','/setdcvalueindex'){
        & powercfg.exe $option SCHEME_CURRENT SUB_BUTTONS LIDACTION $value
        if($LASTEXITCODE){throw "powercfg $option failed."}
    }
    & powercfg.exe /setactive SCHEME_CURRENT
    if($LASTEXITCODE){throw 'Could not apply the power plan.'}
}
if($Undo){
    Set-LidAction 2
    if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){
        Stop-ScheduledTask -TaskName $name
        Unregister-ScheduledTask -TaskName $name -Confirm:$false
    }
    return
}
$user=[Security.Principal.WindowsIdentity]::GetCurrent().Name
New-Item -ItemType Directory -Path $dir -Force | Out-Null
if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){
    Stop-ScheduledTask -TaskName $name
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'LidWifiHibernate.exe') -Destination $bin -Force
$action=New-ScheduledTaskAction -Execute $bin
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $user
$principal=New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
try {
    Start-ScheduledTask -TaskName $name
    Start-Sleep -Seconds 2
    if((Get-ScheduledTask -TaskName $name).State -ne 'Running'){throw 'The lid listener did not start.'}
    Set-LidAction 0
} catch {
    Set-LidAction 2
    throw
}



