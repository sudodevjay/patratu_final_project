# Build Client EXE Package

Run from project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\packaging\build_client_exe.ps1
```

## Output structure

After build, only these two artifacts are expected in `dist\client`:

- `dist\client\FingerprintClient_IDSL_DEVICEFIX` (folder)
- `dist\client\FingerprintClient_IDSL_DEVICEFIX.zip` (zip)

`dist\client-build-FingerprintClient_IDSL_DEVICEFIX` is legacy intermediate output and is auto-cleaned by the new build script.

## Runtime

- Start: double click `FingerprintClient_IDSL_DEVICEFIX.exe`
- Stop:

```cmd
FingerprintClient_IDSL_DEVICEFIX.exe --stop
```

## Crash diagnostics logs

If Tomcat starts and closes, collect these logs from client machine:

- `app\logs\launcher.log`
- `app\logs\start-tomcat.log`
- `app\logs\stop-tomcat.log`
- `app\tomcat\logs\catalina*.log`

These logs now include startup script exit code, config test status, and port `8080` check.

## SQL auth DLL guarantee

Build now enforces presence of `mssql-jdbc_auth-*.x64.dll` inside `app\tomcat\bin`.
If DLL is missing, build fails instead of producing a broken client package.
