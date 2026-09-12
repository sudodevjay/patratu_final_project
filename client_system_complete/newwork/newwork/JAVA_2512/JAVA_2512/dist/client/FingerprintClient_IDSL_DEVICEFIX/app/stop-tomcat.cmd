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
set "PATH=%JAVA_HOME%\bin;%PATH%"
set "JAVA_OPTS=-Djava.library.path=%CATALINA_HOME%\bin"
set "CATALINA_OPTS=%JAVA_OPTS%"

set "STOP_EXIT=1"
set "SHUTDOWN_PORT_OPEN=1"
for /l %%I in (1,1,20) do (
  call "%CATALINA_HOME%\bin\shutdown.bat" >> "%STOP_LOG%" 2>&1
  if errorlevel 1 (
    call :log "shutdown attempt %%I exit=1"
  ) else (
    set "STOP_EXIT=0"
    call :log "shutdown attempt %%I exit=0"
  )
  netstat -ano | findstr /R /C:":18005 .*LISTENING" >nul 2>&1
  if errorlevel 1 (
    set "SHUTDOWN_PORT_OPEN=0"
    goto :stopDone
  )
  >nul ping -n 2 127.0.0.1
)
:stopDone

if "%SHUTDOWN_PORT_OPEN%"=="0" (
  call :log "Tomcat shutdown port closed."
  set "STOP_EXIT=0"
) else (
  call :log "WARN: Shutdown port still open. Verify tomcat status."
)

exit /b %STOP_EXIT%

:log
echo [%date% %time%] %~1>> "%STOP_LOG%"
echo [%date% %time%] %~1
exit /b 0
