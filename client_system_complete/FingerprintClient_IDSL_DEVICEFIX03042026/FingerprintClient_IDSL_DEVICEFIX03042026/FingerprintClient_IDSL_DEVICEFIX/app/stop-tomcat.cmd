@echo off
setlocal EnableExtensions
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "LOG_DIR=%APP_DIR%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "STOP_LOG=%LOG_DIR%\stop-tomcat.log"

call :log "========== STOP REQUEST =========="
set "CATALINA_HOME=%APP_DIR%\tomcat"
set "CATALINA_BASE=%CATALINA_HOME%"
set "JAVA_HOME=%APP_DIR%\jre"
set "JRE_HOME=%JAVA_HOME%"
set "HTTP_PORT=8080"
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "JAVA_OPTS=-Djava.library.path=%CATALINA_HOME%\bin"
set "CATALINA_OPTS=%JAVA_OPTS%"

set "STOP_EXIT=1"
for /l %%I in (1,1,20) do (
  call :killListeningPids %HTTP_PORT%
  call :killTomcatJavaProcs
  call :isStopped
  if "%ALL_STOPPED%"=="1" goto :stopDone
  >nul ping -n 2 127.0.0.1
)
:stopDone

if "%ALL_STOPPED%"=="1" (
  call :log "Tomcat process stopped."
  set "STOP_EXIT=0"
) else (
  call :log "WARN: Tomcat process still detected after retries."
)

exit /b %STOP_EXIT%

:killListeningPids
set "KILL_PORT=%~1"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%KILL_PORT% .*LISTENING"') do (
  if not "%%P"=="0" (
    taskkill /PID %%P /T /F >> "%STOP_LOG%" 2>&1
    if not errorlevel 1 (
      call :log "Killed PID %%P on port %KILL_PORT%"
      set "STOP_EXIT=0"
    ) else (
      call :log "WARN: Failed to kill PID %%P on port %KILL_PORT%"
    )
  )
)
exit /b 0

:killTomcatJavaProcs
for /f %%P in ('powershell -NoProfile -Command "$needle='%CATALINA_BASE%'; Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'java.exe' -and $_.CommandLine -like \"*${needle}*\" } | ForEach-Object { $_.ProcessId }"') do (
  if not "%%P"=="" (
    taskkill /PID %%P /T /F >> "%STOP_LOG%" 2>&1
    if not errorlevel 1 (
      call :log "Killed Tomcat java PID %%P"
      set "STOP_EXIT=0"
    ) else (
      call :log "WARN: Failed to kill Tomcat java PID %%P"
    )
  )
)
exit /b 0

:isStopped
set "ALL_STOPPED=1"
netstat -ano | findstr /R /C:":%HTTP_PORT% .*LISTENING" >nul 2>&1 && set "ALL_STOPPED=0"
for /f %%C in ('powershell -NoProfile -Command "$needle='%CATALINA_BASE%'; (Get-CimInstance Win32_Process | Where-Object { $_.Name -ieq 'java.exe' -and $_.CommandLine -like \"*${needle}*\" } | Measure-Object).Count"') do (
  if not "%%C"=="0" set "ALL_STOPPED=0"
)
exit /b 0

:log
echo [%date% %time%] %~1>> "%STOP_LOG%"
echo [%date% %time%] %~1
exit /b 0
