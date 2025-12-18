@echo off
setlocal enabledelayedexpansion

echo ==============================================
echo Oracle Data Guard 主备切换脚本 (Windows)
echo ==============================================

echo 检测当前数据库角色...

for /f "tokens=*" %%i in ('docker exec -u oracle oracle-primary bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< \"set heading off feedback off pagesize 0; SELECT DATABASE_ROLE FROM V\$DATABASE; exit;\"" 2^>nul') do set PRIMARY_ROLE=%%i

for /f "tokens=*" %%i in ('docker exec -u oracle oracle-standby bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< \"set heading off feedback off pagesize 0; SELECT DATABASE_ROLE FROM V\$DATABASE; exit;\"" 2^>nul') do set STANDBY_ROLE=%%i

echo oracle-primary: %PRIMARY_ROLE%
echo oracle-standby: %STANDBY_ROLE%
echo.

if "%PRIMARY_ROLE%"=="PRIMARY" if "%STANDBY_ROLE%"=="PHYSICAL STANDBY" (
    set CURRENT_PRIMARY=oracle-primary
    set CURRENT_STANDBY=oracle-standby
    echo 切换方向: oracle-primary(主) -^> oracle-standby(主)
    goto :confirm
)

if "%PRIMARY_ROLE%"=="PHYSICAL STANDBY" if "%STANDBY_ROLE%"=="PRIMARY" (
    set CURRENT_PRIMARY=oracle-standby
    set CURRENT_STANDBY=oracle-primary
    echo 切换方向: oracle-standby(主) -^> oracle-primary(主)
    goto :confirm
)

echo 错误：无法确定当前主备角色
pause
exit /b 1

:confirm
echo.
set /p confirm=确认执行主备切换？(yes/no): 

if not "%confirm%"=="yes" (
    echo 取消切换操作。
    pause
    exit /b 1
)

echo.
echo 1. 在当前主库 [%CURRENT_PRIMARY%] 执行切换到备库...
echo ----------------------------------------
docker exec -u oracle %CURRENT_PRIMARY% bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN; exit;'"

echo 重启到 MOUNT 状态...
docker exec -u oracle %CURRENT_PRIMARY% bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'SHUTDOWN IMMEDIATE; STARTUP MOUNT; exit;'"

echo.
echo 2. 在当前备库 [%CURRENT_STANDBY%] 执行切换到主库...
echo ----------------------------------------
docker exec -u oracle %CURRENT_STANDBY% bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL; ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN; exit;'"

echo 打开新主库...
docker exec -u oracle %CURRENT_STANDBY% bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'ALTER DATABASE OPEN; exit;'"

echo.
echo 3. 在新备库 [%CURRENT_PRIMARY%] 创建 Standby Redo Log 并启动恢复进程...
echo ----------------------------------------
docker exec -u oracle %CURRENT_PRIMARY% bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'DECLARE v_count NUMBER; BEGIN SELECT COUNT(*) INTO v_count FROM V\$LOGFILE WHERE TYPE = ''STANDBY''; IF v_count = 0 THEN EXECUTE IMMEDIATE ''ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M''; EXECUTE IMMEDIATE ''ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M''; EXECUTE IMMEDIATE ''ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M''; EXECUTE IMMEDIATE ''ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M''; END IF; END; / ALTER DATABASE OPEN READ ONLY; ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION; exit;'"

echo.
echo 4. 验证切换结果...
echo ----------------------------------------
echo oracle-primary:
docker exec -u oracle oracle-primary bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'set linesize 200; SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE; exit;'"

echo.
echo oracle-standby:
docker exec -u oracle oracle-standby bash -c "export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<< 'set linesize 200; SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE; exit;'"

echo.
echo ==============================================
echo 主备切换完成！
echo %CURRENT_STANDBY% 现在是主库
echo %CURRENT_PRIMARY% 现在是备库
echo ==============================================

pause
