@echo off
set CATALINA_BASE=C:\Users\HP\eclipse-workspace\.metadata\.plugins\org.eclipse.wst.server.core\tmp0
set CATALINA_HOME=C:\Users\HP\Downloads\apache-tomcat-9.0.115-windows-x64 (1)\apache-tomcat-9.0.115
set JRE_HOME=C:\Program Files\Java\jdk1.8.0_202\jre
set JAVA_HOME=C:\Program Files\Java\jdk1.8.0_202
set "JAVA_OPTS=-Djava.library.path=C:\Users\HP\Downloads\sqljdbc_13.2.1.0_enu\sqljdbc_13.2\enu\auth\x64 -Dsqlserver.auth.dll.path=C:\Users\HP\Downloads\sqljdbc_13.2.1.0_enu\sqljdbc_13.2\enu\auth\x64\mssql-jdbc_auth-13.2.1.x64.dll"
set "CATALINA_OPTS=%JAVA_OPTS%"
call "C:\Users\HP\Downloads\apache-tomcat-9.0.115-windows-x64 (1)\apache-tomcat-9.0.115\bin\catalina.bat" run
