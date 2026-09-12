$ErrorActionPreference = "Stop"

$serviceName = "FingerprintService"
$nssm = "C:\Users\PVUNL\Downloads\nssm-2.24\nssm-2.24\win64\nssm.exe"
$appDir = "D:\housys\FingerprintClient_IDSL_DEVICEFIX03042026\FingerprintClient_IDSL_DEVICEFIX\app"
$runner = Join-Path $appDir "run-tomcat-service.cmd"
$stdoutLog = Join-Path $appDir "logs\service-stdout.log"
$stderrLog = Join-Path $appDir "logs\service-stderr.log"

if (-not (Test-Path $nssm)) {
  throw "NSSM not found at: $nssm"
}
if (-not (Test-Path $runner)) {
  throw "Runner script not found at: $runner"
}

Write-Host "Stopping service if running..."
& $nssm stop $serviceName | Out-Null
Start-Sleep -Seconds 2

Write-Host "Configuring NSSM application settings..."
& $nssm set $serviceName Application "C:\Windows\System32\cmd.exe" | Out-Null
& $nssm set $serviceName AppDirectory $appDir | Out-Null
& $nssm set $serviceName AppParameters "/c `"$runner`"" | Out-Null

Write-Host "Configuring logs + restart behavior..."
& $nssm set $serviceName AppStdout $stdoutLog | Out-Null
& $nssm set $serviceName AppStderr $stderrLog | Out-Null
& $nssm set $serviceName AppRotateFiles 1 | Out-Null
& $nssm set $serviceName AppRotateOnline 1 | Out-Null
& $nssm set $serviceName AppRotateBytes 10485760 | Out-Null
& $nssm set $serviceName AppExit Default Restart | Out-Null
& $nssm set $serviceName AppThrottle 1500 | Out-Null
& $nssm set $serviceName AppRestartDelay 2000 | Out-Null
& $nssm set $serviceName AppStopMethodConsole 15000 | Out-Null
& $nssm set $serviceName AppStopMethodWindow 15000 | Out-Null
& $nssm set $serviceName AppStopMethodThreads 15000 | Out-Null

Write-Host "Setting service startup/dependency..."
sc.exe config $serviceName type= own start= delayed-auto depend= "Tcpip/MSSQL`$DEVSQL" | Out-Null

Write-Host "Starting service..."
Start-Service -Name $serviceName
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "Final state:"
Get-Service -Name $serviceName | Select-Object Name,Status,StartType | Format-Table -AutoSize
Write-Host ""
Write-Host "Port check:"
cmd /c "netstat -ano | findstr /R /C:"":8080 .*LISTENING"""
Write-Host ""
Write-Host "URL check:"
$status = $null
for ($i = 1; $i -le 24; $i++) {
  try {
    $status = (Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:8080/demo/" -TimeoutSec 5).StatusCode
    break
  } catch {
    Start-Sleep -Seconds 3
  }
}
if ($status) {
  Write-Host "HTTP status: $status"
} else {
  Write-Host "HTTP check failed after retry window. Recent service log tail:"
  $serviceLog = Join-Path $appDir "logs\service-run.log"
  if (Test-Path $serviceLog) {
    Get-Content -Path $serviceLog -Tail 40
  } else {
    Write-Host "service-run.log not found."
  }
}

Write-Host ""
Write-Host "Done."
