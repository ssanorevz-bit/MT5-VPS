$t="MT5Collector"
Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue
$a=New-ScheduledTaskAction -Execute "python" -Argument "C:\quant\collect_mt5_tick_dom.py" -WorkingDirectory "C:\quant"
$r=New-ScheduledTaskTrigger -AtStartup
$s=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartOnFailure -RestartInterval (New-TimeSpan -Minutes 1) -RestartCount 999
$p=New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
Register-ScheduledTask -TaskName $t -Action $a -Trigger $r -Settings $s -Principal $p -Force|Out-Null
Start-ScheduledTask -TaskName $t
Write-Host "MT5Collector running in background!" -ForegroundColor Green
