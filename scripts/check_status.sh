#!/bin/bash

echo "=============================================="
echo "Oracle Data Guard 状态检查"
echo "=============================================="

echo ""
echo "=== 主库状态 ==="
docker exec -u oracle oracle-primary bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200 pagesize 100
col DATABASE_ROLE for a20
col OPEN_MODE for a25
SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;
EOF'

echo ""
echo "=== 备库状态 ==="
docker exec -u oracle oracle-standby bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200 pagesize 100
col DATABASE_ROLE for a20
col OPEN_MODE for a25
SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;
EOF'

echo ""
echo "=== 同步延迟 ==="
docker exec -u oracle oracle-standby bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200 pagesize 100
col NAME for a20
col VALUE for a30
SELECT NAME, VALUE FROM V\$DATAGUARD_STATS WHERE NAME IN ('"'"'transport lag'"'"', '"'"'apply lag'"'"');
EOF'

echo ""
echo "=== 日志传输状态 ==="
docker exec -u oracle oracle-primary bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200 pagesize 100
col DEST_ID for 99
col STATUS for a10
col ERROR for a30
SELECT DEST_ID, STATUS, ERROR FROM V\$ARCHIVE_DEST WHERE DEST_ID IN (1,2);
EOF'

echo ""
echo "=== 备库恢复进程 ==="
docker exec -u oracle oracle-standby bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200 pagesize 100
col PROCESS for a10
col STATUS for a15
SELECT PROCESS, STATUS, THREAD#, SEQUENCE# FROM V\$MANAGED_STANDBY WHERE PROCESS IN ('"'"'MRP0'"'"', '"'"'RFS'"'"');
EOF'
