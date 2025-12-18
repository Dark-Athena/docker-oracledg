#!/bin/bash

echo "=============================================="
echo "Oracle Data Guard 主备切换脚本"
echo "=============================================="

# 检测当前角色
echo "检测当前数据库角色..."
PRIMARY_ROLE=$(docker exec -u oracle oracle-primary bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set heading off feedback off pagesize 0
SELECT DATABASE_ROLE FROM V\$DATABASE;
EOF' 2>/dev/null | tr -d '[:space:]')

STANDBY_ROLE=$(docker exec -u oracle oracle-standby bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set heading off feedback off pagesize 0
SELECT DATABASE_ROLE FROM V\$DATABASE;
EOF' 2>/dev/null | tr -d '[:space:]')

echo "oracle-primary: $PRIMARY_ROLE"
echo "oracle-standby: $STANDBY_ROLE"
echo ""

# 确定切换方向
if [ "$PRIMARY_ROLE" = "PRIMARY" ] && [ "$STANDBY_ROLE" = "PHYSICALSTANDBY" ]; then
    CURRENT_PRIMARY="oracle-primary"
    CURRENT_STANDBY="oracle-standby"
    echo "切换方向: oracle-primary(主) → oracle-standby(主)"
elif [ "$PRIMARY_ROLE" = "PHYSICALSTANDBY" ] && [ "$STANDBY_ROLE" = "PRIMARY" ]; then
    CURRENT_PRIMARY="oracle-standby"
    CURRENT_STANDBY="oracle-primary"
    echo "切换方向: oracle-standby(主) → oracle-primary(主)"
else
    echo "错误：无法确定当前主备角色"
    echo "PRIMARY_ROLE=$PRIMARY_ROLE, STANDBY_ROLE=$STANDBY_ROLE"
    exit 1
fi

echo ""
read -p "确认执行主备切换？(yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "取消切换操作。"
    exit 1
fi

echo ""
echo "1. 在当前主库 [$CURRENT_PRIMARY] 执行切换到备库..."
echo "----------------------------------------"
docker exec -u oracle $CURRENT_PRIMARY bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
ALTER DATABASE COMMIT TO SWITCHOVER TO PHYSICAL STANDBY WITH SESSION SHUTDOWN;
exit;
EOF'

echo "重启到 MOUNT 状态..."
docker exec -u oracle $CURRENT_PRIMARY bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
exit;
EOF'

echo ""
echo "2. 在当前备库 [$CURRENT_STANDBY] 执行切换到主库..."
echo "----------------------------------------"
docker exec -u oracle $CURRENT_STANDBY bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE CANCEL;
ALTER DATABASE COMMIT TO SWITCHOVER TO PRIMARY WITH SESSION SHUTDOWN;
exit;
EOF'

echo "打开新主库..."
docker exec -u oracle $CURRENT_STANDBY bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
ALTER DATABASE OPEN;
exit;
EOF'

echo ""
echo "3. 在新备库 [$CURRENT_PRIMARY] 创建 Standby Redo Log 并启动恢复进程..."
echo "----------------------------------------"
docker exec -u oracle $CURRENT_PRIMARY bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
-- 检查并创建 Standby Redo Log
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM V\$LOGFILE WHERE TYPE = '"'"'STANDBY'"'"';
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE '"'"'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M'"'"';
    EXECUTE IMMEDIATE '"'"'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M'"'"';
    EXECUTE IMMEDIATE '"'"'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M'"'"';
    EXECUTE IMMEDIATE '"'"'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M'"'"';
    DBMS_OUTPUT.PUT_LINE('"'"'Standby Redo Log 已创建'"'"');
  ELSE
    DBMS_OUTPUT.PUT_LINE('"'"'Standby Redo Log 已存在'"'"');
  END IF;
END;
/
ALTER DATABASE OPEN READ ONLY;
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
exit;
EOF'

echo ""
echo "4. 验证切换结果..."
echo "----------------------------------------"
echo "oracle-primary:"
docker exec -u oracle oracle-primary bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200
SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;
EOF'

echo ""
echo "oracle-standby:"
docker exec -u oracle oracle-standby bash -c 'export ORACLE_SID=ORCL; export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1; $ORACLE_HOME/bin/sqlplus -s / as sysdba <<EOF
set linesize 200
SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;
EOF'

echo ""
echo "=============================================="
echo "主备切换完成！"
echo "$CURRENT_STANDBY 现在是主库"
echo "$CURRENT_PRIMARY 现在是备库"
echo "=============================================="
