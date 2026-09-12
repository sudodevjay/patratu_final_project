param(
  [string]$ServiceName = "FingerprintService",
  [string]$NssmPath,
  [string]$SqlDependencyService = "",
  [string]$Url = "http://localhost:8080/demo/"
)

$ErrorActionPreference = "Stop"

function Resolve-NssmPath {
  param([string]$ExplicitPath, [string]$AppDir)

  if ($ExplicitPath) {
    return $ExplicitPath
  }

  $candidates = @(
    (Join-Path $AppDir "nssm.exe"),
    (Join-Path $AppDir "tools\nssm\win64\nssm.exe"),
    (Join-Path $AppDir "tools\nssm\nssm.exe")
  )

  return $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$appDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runner = Join-Path $appDir "run-tomcat-service.cmd"
$stdoutLog = Join-Path $appDir "logs\service-stdout.log"
$stderrLog = Join-Path $appDir "logs\service-stderr.log"
$nssm = Resolve-NssmPath -ExplicitPath $NssmPath -AppDir $appDir

if (-not (Test-Path $runner)) {
  throw "Runner script not found at: $runner"
}
if (-not $nssm) {
  throw "NSSM not found. Pass -NssmPath <full path> or place nssm.exe under app\\nssm.exe or app\\tools\\nssm\\win64\\nssm.exe"
}

Write-Host "Using app directory: $appDir"
Write-Host "Using NSSM path: $nssm"
Write-Host "Stopping service if running..."
& $nssm stop $ServiceName | Out-Null
Start-Sleep -Seconds 2

Write-Host "Configuring NSSM application settings..."
& $nssm set $ServiceName Application "C:\Windows\System32\cmd.exe" | Out-Null
& $nssm set $ServiceName AppDirectory $appDir | Out-Null
& $nssm set $ServiceName AppParameters "/c `"$runner`"" | Out-Null

Write-Host "Configuring logs + restart behavior..."
& $nssm set $ServiceName AppStdout $stdoutLog | Out-Null
& $nssm set $ServiceName AppStderr $stderrLog | Out-Null
& $nssm set $ServiceName AppRotateFiles 1 | Out-Null
& $nssm set $ServiceName AppRotateOnline 1 | Out-Null
& $nssm set $ServiceName AppRotateBytes 10485760 | Out-Null
& $nssm set $ServiceName AppExit Default Restart | Out-Null
& $nssm set $ServiceName AppThrottle 1500 | Out-Null
& $nssm set $ServiceName AppRestartDelay 2000 | Out-Null
& $nssm set $ServiceName AppStopMethodConsole 15000 | Out-Null
& $nssm set $ServiceName AppStopMethodWindow 15000 | Out-Null
& $nssm set $ServiceName AppStopMethodThreads 15000 | Out-Null

Write-Host "Setting service startup options..."
if ($SqlDependencyService) {
  sc.exe config $ServiceName type= own start= delayed-auto depend= "Tcpip/$SqlDependencyService" | Out-Null
} else {
  sc.exe config $ServiceName type= own start= delayed-auto | Out-Null
}

Write-Host "Starting service..."
Start-Service -Name $ServiceName
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "Final state:"
Get-Service -Name $ServiceName | Select-Object Name,Status,StartType | Format-Table -AutoSize
Write-Host ""
Write-Host "Port check:"
cmd /c "netstat -ano | findstr /R /C:"":8080 .*LISTENING"""
Write-Host ""
Write-Host "URL check:"
$status = $null
for ($i = 1; $i -le 24; $i++) {
  try {
    $status = (Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 5).StatusCode
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
