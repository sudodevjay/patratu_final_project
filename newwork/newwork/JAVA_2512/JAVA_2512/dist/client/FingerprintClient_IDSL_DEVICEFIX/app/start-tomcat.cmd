@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "LOG_DIR=%APP_DIR%\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "START_LOG=%LOG_DIR%\start-tomcat.log"
set "ENV_FILE=%APP_DIR%\.env"
if exist "%ENV_FILE%" call :loadEnvFile "%ENV_FILE%"

call :log "========== START REQUEST =========="
set "CATALINA_HOME=%APP_DIR%\tomcat"
set "CATALINA_BASE=%CATALINA_HOME%"
set "JAVA_HOME=%APP_DIR%\jre"
set "JRE_HOME=%JAVA_HOME%"
set "HTTP_PORT=8080"
set "SHUTDOWN_PORT=18015"
set "SCHEDULER_CRON=0 30 18 * * *"
set "SCHEDULER_ZONE=Asia/Kolkata"
if defined FP_SCHEDULER_CRON set "SCHEDULER_CRON=%FP_SCHEDULER_CRON%"
if defined FP_SCHEDULER_ZONE set "SCHEDULER_ZONE=%FP_SCHEDULER_ZONE%"
set "PATH=%JAVA_HOME%\bin;%PATH%"

if not exist "%JAVA_HOME%\bin\java.exe" (
  call :log "ERROR: Missing java.exe at %JAVA_HOME%\bin\java.exe"
  exit /b 11
)

set "SQL_AUTH_DLL="
for %%F in ("%CATALINA_HOME%\bin\mssql-jdbc_auth-*.x64.dll") do (
  if exist "%%~fF" (
    set "SQL_AUTH_DLL=%%~fF"
    goto :dllFound
  )
)
:dllFound

if defined SQL_AUTH_DLL (
  set "JAVA_OPTS=-Djava.library.path=%CATALINA_HOME%\bin -Dsqlserver.auth.dll.path=%SQL_AUTH_DLL%"
) else (
  set "JAVA_OPTS=-Djava.library.path=%CATALINA_HOME%\bin"
  call :log "WARN: SQL auth DLL not found under %CATALINA_HOME%\bin"
)
set "CATALINA_OPTS=%JAVA_OPTS%"

call :log "JAVA_HOME=%JAVA_HOME%"
call :log "CATALINA_HOME=%CATALINA_HOME%"
call :log "JAVA_OPTS=%JAVA_OPTS%"
call :log "SCHEDULER_CRON=%SCHEDULER_CRON% SCHEDULER_ZONE=%SCHEDULER_ZONE%"
call :log "HTTP_PORT=%HTTP_PORT% SHUTDOWN_PORT=%SHUTDOWN_PORT%"

set "EXISTING_INSTANCE=0"
netstat -ano | findstr /R /C:":%HTTP_PORT% .*LISTENING" >nul 2>&1 && set "EXISTING_INSTANCE=1"
netstat -ano | findstr /R /C:":%SHUTDOWN_PORT% .*LISTENING" >nul 2>&1 && set "EXISTING_INSTANCE=1"
if "%EXISTING_INSTANCE%"=="1" (
  call :log "Existing Tomcat instance detected. Running stop-tomcat.cmd before startup."
  call "%APP_DIR%\stop-tomcat.cmd" >> "%START_LOG%" 2>&1
  for /l %%I in (1,1,12) do (
    call :portsClosed
    if "%PORTS_CLOSED%"=="1" goto :preStopDone
    >nul ping -n 2 127.0.0.1
  )
  call :log "WARN: Ports still busy after stop script. Forcing cleanup by PID."
  call :killListeningPids %HTTP_PORT%
  call :killListeningPids %SHUTDOWN_PORT%
)
:preStopDone

call "%CATALINA_HOME%\bin\catalina.bat" configtest >> "%START_LOG%" 2>&1
if errorlevel 1 (
  call :log "ERROR: catalina configtest failed."
  exit /b 21
)

call "%CATALINA_HOME%\bin\startup.bat" >> "%START_LOG%" 2>&1
if errorlevel 1 (
  set "START_EXIT=1"
) else (
  set "START_EXIT=0"
)
call :log "startup.bat exit=%START_EXIT%"

set "SHUTDOWN_OK="
for /l %%I in (1,1,12) do (
  netstat -ano | findstr /R /C:":%SHUTDOWN_PORT% .*LISTENING" >nul 2>&1
  if not errorlevel 1 (
    set "SHUTDOWN_OK=1"
    goto :portDone
  )
  >nul ping -n 2 127.0.0.1
)
:portDone

if defined SHUTDOWN_OK (
  call :log "Tomcat detected on shutdown port %SHUTDOWN_PORT%."
) else (
  call :log "WARN: Shutdown port %SHUTDOWN_PORT% not listening after startup. Check tomcat\\logs\\catalina*.log"
)

set "HTTP_OK="
for /l %%I in (1,1,10) do (
  netstat -ano | findstr /R /C:":%HTTP_PORT% .*LISTENING" >nul 2>&1
  if not errorlevel 1 (
    set "HTTP_OK=1"
    goto :httpDone
  )
  >nul ping -n 2 127.0.0.1
)
:httpDone
if defined HTTP_OK (
  call :log "HTTP port %HTTP_PORT% detected."
) else (
  call :log "WARN: HTTP port %HTTP_PORT% not listening yet."
)

exit /b %START_EXIT%

:portsClosed
set "PORTS_CLOSED=1"
netstat -ano | findstr /R /C:":%HTTP_PORT% .*LISTENING" >nul 2>&1 && set "PORTS_CLOSED=0"
netstat -ano | findstr /R /C:":%SHUTDOWN_PORT% .*LISTENING" >nul 2>&1 && set "PORTS_CLOSED=0"
exit /b 0

:killListeningPids
set "KILL_PORT=%~1"
for /f "tokens=5" %%P in ('netstat -ano ^| findstr /R /C:":%KILL_PORT% .*LISTENING"') do (
  if not "%%P"=="0" (
    taskkill /PID %%P /T /F >> "%START_LOG%" 2>&1
    call :log "Killed PID %%P on port %KILL_PORT%"
  )
)
exit /b 0

:log
echo [%date% %time%] %~1>> "%START_LOG%"
echo [%date% %time%] %~1
exit /b 0

:loadEnvFile
set "ENV_TARGET=%~1"
if not exist "%ENV_TARGET%" exit /b 0
for /f "usebackq tokens=1,* delims==" %%A in (`findstr /R "^[ ]*[A-Za-z_][A-Za-z0-9_]*=" "%ENV_TARGET%"`) do (
  set "ENV_KEY=%%A"
  set "ENV_VALUE=%%B"
  for /f "tokens=* delims= " %%K in ("!ENV_KEY!") do set "ENV_KEY=%%K"
  if /I not "!ENV_KEY!"=="REM" (
    set "!ENV_KEY!=!ENV_VALUE!"
  )
)
exit /b 0
