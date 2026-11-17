#Requires -RunAsAdministrator
param([ValidateSet('Hibernate','Shutdown','Restore')][string]$Mode='Hibernate')
$ErrorActionPreference='Stop'
$adapters = @(Get-PnpDevice -PresentOnly -Class Net | Where-Object InstanceId -like 'PCI\VEN_14C3&DEV_0616&*')
if ($adapters.Count -ne 1) { throw 'Expected exactly one MediaTek MT7922 PCI adapter.' }
$id = $adapters[0].InstanceId
$task='MT7922-RestoreAfterPowerOff'
$logFolder=if($env:MT7922_LOG_DIR){$env:MT7922_LOG_DIR}else{$PSScriptRoot}
function Write-PowerLog([string]$message) {
    try {
        $folder=$logFolder
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $folder 'power.log') -Value ("{0:o} {1}" -f (Get-Date),$message) -Encoding UTF8
    } catch { Write-Warning "Could not write diagnostic log: $_" }
}
Write-PowerLog "Started mode=$Mode"
function Restore-Wifi {
    Write-PowerLog "Enabling MT7922"
    Enable-PnpDevice -InstanceId $id -Confirm:$false
    Write-PowerLog "Enable command succeeded"
    Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue
}
if($Mode -eq 'Restore'){ Restore-Wifi; return }
$device=Get-PnpDevice -InstanceId $id
if($device.Status -ne 'OK'){ throw 'MT7922 is not currently enabled and healthy.' }
$exe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$bootBase = @'
function Write-PowerLog([string]$message) {
    try {
        $folder=$logFolder
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $folder 'power.log') -Value ("{0:o} {1}" -f (Get-Date),$message) -Encoding UTF8
    } catch { Write-Warning "Could not write diagnostic log: $_" }
}

'@
$quotedLogFolder=$logFolder.Replace("'","''")
$bootCode = @"
`$logFolder = '$quotedLogFolder'
$bootBase
Write-PowerLog "Startup recovery started"
Enable-PnpDevice -InstanceId '$id' -Confirm:`$false -ErrorAction Stop
Write-PowerLog "Startup recovery enabled MT7922"
Unregister-ScheduledTask -TaskName '$task' -Confirm:`$false
"@
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootCode))
$action=New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -EncodedCommand $encoded"
$trigger=New-ScheduledTaskTrigger -AtStartup
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $task -Action $action -Trigger $trigger -Settings $settings -User SYSTEM -RunLevel Highest -ErrorAction Stop | Out-Null
$shutdownAccepted=$false
try {
    Write-PowerLog "Disabling MT7922"
    Disable-PnpDevice -InstanceId $id -Confirm:$false
    $problem=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_ProblemCode).Data
    Write-PowerLog "MT7922 problem code after disable: $problem"
    if($problem -ne 22){ throw 'Windows did not confirm that MT7922 was disabled.' }
    if($Mode -eq 'Shutdown'){
        & shutdown.exe /s /t 0
        if($LASTEXITCODE -ne 0){ throw 'Shutdown request failed.' }
        $shutdownAccepted=$true
    } else {
        Add-Type -Namespace PowerTool -Name Native -MemberDefinition '[System.Runtime.InteropServices.DllImport("powrprof.dll", SetLastError=true)] public static extern byte SetSuspendState(byte hibernate, byte force, byte disableWakeEvent);'
        Write-PowerLog "Requesting hibernation"
        if([PowerTool.Native]::SetSuspendState(1,0,0) -eq 0){ throw 'Hibernate request failed.' }
        Write-PowerLog "Hibernate call returned"
    }
} catch { Write-PowerLog "Power operation failed: $_"; throw } finally {
    if(-not $shutdownAccepted){ Restore-Wifi }
}





