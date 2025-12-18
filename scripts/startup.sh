#!/bin/bash
# =============================================================================
# Oracle ADG Startup Script
# =============================================================================
# This script handles database creation and ADG configuration at runtime.
# Oracle software is already installed in the image during build.
# =============================================================================

# 如果以 root 用户运行，先设置权限，然后切换到 oracle 用户
if [ "$(id -u)" = "0" ]; then
    echo "以 root 用户启动，设置目录权限..."
    chown -R oracle:oinstall /u01 /u02
    chmod -R 775 /u02
    chmod -R g+s /u02
    chmod 777 /u01/password_share 2>/dev/null || mkdir -p /u01/password_share && chmod 777 /u01/password_share
    chown oracle:oinstall /etc/oratab 2>/dev/null || true
    echo "切换到 oracle 用户执行..."
    exec gosu oracle /bin/bash -c "export ROLE=$ROLE; $0"
fi

# 设置基本环境变量
export ORACLE_BASE=/u01/app/oracle
export ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH
export LD_LIBRARY_PATH=$ORACLE_HOME/lib:$LD_LIBRARY_PATH
export ORACLE_SID=ORCL
export TNS_ADMIN=$ORACLE_HOME/network/admin
export CV_ASSUME_DISTID=OL8

# 验证 Oracle 软件已安装
if [ ! -d "$ORACLE_HOME/bin" ] || [ ! -f "$ORACLE_HOME/bin/sqlplus" ]; then
  echo "错误：Oracle软件未安装！"
  echo "请确保使用正确的镜像（oracle-adg:latest）"
  echo "运行 ./build.sh 构建镜像"
  exit 1
fi

echo "Oracle软件已安装，版本信息："
sqlplus -v

# 确保网络配置文件存在
if [ ! -d "$TNS_ADMIN" ]; then
  mkdir -p $TNS_ADMIN
fi

# 定义fixConfig函数，用于处理配置文件链接（参考demo版本）
function fixConfig {
  # 确保必要的目录存在
  mkdir -p /u02/config/${ORACLE_SID}
  
  # 复制oratab文件
  if [ -f "/u02/config/oratab" ]; then
    cp -f /u02/config/oratab /etc/oratab
  fi
  
  # 创建符号链接
  if [ ! -L ${ORACLE_HOME}/dbs/orapw${ORACLE_SID} ] && [ -f "/u02/config/${ORACLE_SID}/orapw${ORACLE_SID}" ]; then
    ln -s /u02/config/${ORACLE_SID}/orapw${ORACLE_SID} ${ORACLE_HOME}/dbs/orapw${ORACLE_SID}
  fi
  
  if [ ! -L ${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora ] && [ -f "/u02/config/${ORACLE_SID}/spfile${ORACLE_SID}.ora" ]; then
    ln -s /u02/config/${ORACLE_SID}/spfile${ORACLE_SID}.ora ${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora
  fi
  
  if [ ! -L ${ORACLE_BASE}/admin ] && [ -d "/u02/config/${ORACLE_SID}/admin" ]; then
    ln -s /u02/config/${ORACLE_SID}/admin ${ORACLE_BASE}/admin
  fi
  
  if [ ! -L ${ORACLE_BASE}/fast_recovery_area ] && [ -d "/u02/config/${ORACLE_SID}/fast_recovery_area" ]; then
    ln -s /u02/config/${ORACLE_SID}/fast_recovery_area ${ORACLE_BASE}/fast_recovery_area
  fi
  
  if [ ! -L ${ORACLE_BASE}/diag ] && [ -d "/u02/config/${ORACLE_SID}/diag" ]; then
    rm -Rf ${ORACLE_BASE}/diag 2>/dev/null || true
    ln -s /u02/config/${ORACLE_SID}/diag ${ORACLE_BASE}/diag
  fi
}

# 创建网络配置文件（根据角色配置不同的监听器）
function createNetworkFiles {
  echo "创建listener.ora文件..."
  mkdir -p ${ORACLE_HOME}/network/admin
  
  if [ "$ROLE" = "STANDBY" ]; then
    # 备库需要静态注册，因为实例在NOMOUNT状态无法自动注册
    cat > ${ORACLE_HOME}/network/admin/listener.ora <<EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1))
      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = ${ORACLE_SID}_STANDBY)
      (ORACLE_HOME = ${ORACLE_HOME})
      (SID_NAME = ${ORACLE_SID})
    )
  )

USE_SID_AS_SERVICE_listener=on
INBOUND_CONNECT_TIMEOUT_LISTENER=400
EOF
  else
    # 主库使用标准监听器配置
    cat > ${ORACLE_HOME}/network/admin/listener.ora <<EOF
LISTENER = 
(DESCRIPTION_LIST = 
  (DESCRIPTION = 
    (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1)) 
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521)) 
  ) 
) 
USE_SID_AS_SERVICE_listener=on
INBOUND_CONNECT_TIMEOUT_LISTENER=400
EOF
  fi

  # 总是重新创建tnsnames.ora以确保配置正确
  echo "创建tnsnames.ora文件..."
  
  cat > ${ORACLE_HOME}/network/admin/tnsnames.ora <<EOF
LISTENER = (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))

${ORACLE_SID} =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${ORACLE_SID})
    )
  )

${ORACLE_SID}_PRIMARY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = oracle-primary)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${ORACLE_SID}_PRIMARY)
    )
  )

${ORACLE_SID}_STANDBY =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = oracle-standby)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${ORACLE_SID}_STANDBY)
    )
  )
EOF

  if [ ! -f ${ORACLE_HOME}/network/admin/sqlnet.ora ]; then
    echo "创建sqlnet.ora文件..."
    
    cat > ${ORACLE_HOME}/network/admin/sqlnet.ora <<EOF
SQLNET.INBOUND_CONNECT_TIMEOUT=400
EOF
  fi
}

# 启动Oracle监听器
echo "启动Oracle监听器..."
createNetworkFiles
lsnrctl start

# 根据角色执行不同的初始化流程
if [ "$ROLE" = "PRIMARY" ]; then
  echo "初始化主库..."
  
  # 检查数据库是否已经存在（参考demo版本的方法）
  if [ ! -d "/u02/oradata/${ORACLE_SID}" ]; then
    echo "数据库不存在，开始创建数据库..."
    
    # 创建必要的目录
    mkdir -p /u02/oradata/${ORACLE_SID}
    mkdir -p /u02/fast_recovery_area/${ORACLE_SID}
    mkdir -p /u02/config/${ORACLE_SID}
    
    # 确保目录权限正确（在容器中可能无权修改，忽略错误）
    chown -R oracle:oinstall /u02 2>/dev/null || true
    chmod -R 775 /u02 2>/dev/null || true
    chmod -R g+s /u02 2>/dev/null || true
    
    # 确保密码共享目录存在且有正确权限
    mkdir -p /u01/password_share
    chmod 777 /u01/password_share 2>/dev/null || true
    
    # 使用dbca创建数据库
    echo "使用dbca创建数据库..."
    dbca -silent -createDatabase \
      -templateName General_Purpose.dbc \
      -gdbname ${ORACLE_SID} -sid ${ORACLE_SID} -responseFile NO_VALUE \
      -characterSet AL32UTF8 \
      -sysPassword Oradoc_db1 \
      -systemPassword Oradoc_db1 \
      -createAsContainerDatabase false \
      -databaseType MULTIPURPOSE \
      -memoryMgmtType auto_sga \
      -totalMemory 1024 \
      -storageType FS \
      -datafileDestination "/u02/oradata/" \
      -redoLogFileSize 50 \
      -emConfiguration NONE \
      -ignorePreReqs
    
    # 检查数据库创建是否成功
    if [ $? -ne 0 ]; then
      echo "错误：数据库创建失败"
      exit 1
    fi
    
    echo "数据库创建成功"
    
    # 关闭数据库以便保存配置
    sqlplus / as sysdba << EOF
SHUTDOWN IMMEDIATE;
EXIT;
EOF
    
    # 存储配置文件到config目录（参考demo版本）
    echo "存储配置文件..."
    
    # 创建密码文件（如果不存在）
    if [ ! -f "${ORACLE_HOME}/dbs/orapw${ORACLE_SID}" ]; then
      orapwd file=${ORACLE_HOME}/dbs/orapw${ORACLE_SID} password=Oradoc_db1 entries=10
    fi
    
    # 复制配置文件到持久化存储
    cp ${ORACLE_HOME}/dbs/orapw${ORACLE_SID} /u02/config/${ORACLE_SID}/
    cp ${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora /u02/config/${ORACLE_SID}/ 2>/dev/null || true
    
    # 复制其他配置目录
    cp -r ${ORACLE_BASE}/admin /u02/config/${ORACLE_SID}/ 2>/dev/null || true
    cp -r ${ORACLE_BASE}/fast_recovery_area /u02/config/${ORACLE_SID}/ 2>/dev/null || true
    cp -r ${ORACLE_BASE}/diag /u02/config/${ORACLE_SID}/ 2>/dev/null || true
    
    # 更新oratab文件（使用临时文件避免权限问题）
    if [ -f /etc/oratab ]; then
      cp /etc/oratab /tmp/oratab.tmp
      sed -i -e "s|${ORACLE_SID}:${ORACLE_HOME}:N|${ORACLE_SID}:${ORACLE_HOME}:Y|g" /tmp/oratab.tmp
      cp /tmp/oratab.tmp /u02/config/oratab
      rm -f /tmp/oratab.tmp
    fi
    
    # 启动数据库
    sqlplus / as sysdba << EOF
STARTUP;
EXIT;
EOF
    
    # 配置归档日志模式和Data Guard相关参数
    sqlplus / as sysdba << EOF
-- 首先设置恢复区域大小（必须在设置DB_RECOVERY_FILE_DEST之前设置SIZE）
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST_SIZE=10G SCOPE=BOTH;
ALTER SYSTEM SET DB_RECOVERY_FILE_DEST='/u02/fast_recovery_area' SCOPE=BOTH;

-- 强制日志模式
ALTER DATABASE FORCE LOGGING;

-- 关闭数据库切换到归档模式
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;

-- 设置Data Guard相关参数
ALTER SYSTEM SET LOG_ARCHIVE_DEST_1='LOCATION=/u02/fast_recovery_area VALID_FOR=(ALL_LOGFILES,ALL_ROLES) DB_UNIQUE_NAME=${ORACLE_SID}_PRIMARY' SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_2='SERVICE=${ORACLE_SID}_STANDBY LGWR ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=${ORACLE_SID}_STANDBY' SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_1=ENABLE SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=ENABLE SCOPE=SPFILE;
ALTER SYSTEM SET FAL_SERVER='${ORACLE_SID}_STANDBY' SCOPE=SPFILE;
ALTER SYSTEM SET FAL_CLIENT='${ORACLE_SID}_PRIMARY' SCOPE=SPFILE;
ALTER SYSTEM SET STANDBY_FILE_MANAGEMENT=AUTO SCOPE=SPFILE;
ALTER SYSTEM SET LOG_ARCHIVE_CONFIG='DG_CONFIG=(${ORACLE_SID}_PRIMARY,${ORACLE_SID}_STANDBY)' SCOPE=SPFILE;
ALTER SYSTEM SET DB_UNIQUE_NAME='${ORACLE_SID}_PRIMARY' SCOPE=SPFILE;
-- 设置LOCAL_LISTENER确保服务注册到监听器
ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS=(PROTOCOL=TCP)(HOST=0.0.0.0)(PORT=1521))' SCOPE=SPFILE;

-- 创建 Standby Redo Log（为将来 switchover 做准备）
ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M;
ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M;
ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M;
ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M;

-- 重启数据库使参数生效
SHUTDOWN IMMEDIATE;
STARTUP;
ALTER SYSTEM SWITCH LOGFILE;
EXIT;
EOF
    
    # 创建备用数据库所需的密码文件
    # 先删除已存在的密码文件
    rm -f $ORACLE_HOME/dbs/orapw${ORACLE_SID}
    orapwd file=$ORACLE_HOME/dbs/orapw${ORACLE_SID} password=Oradoc_db1 entries=10
    
    # 将密码文件复制到共享卷，供备库使用
    mkdir -p /u01/password_share
    chmod 777 /u01/password_share
    # 删除已存在的文件（如果有的话）
    rm -f /u01/password_share/orapw${ORACLE_SID}
    # 确保源文件存在
    if [ -f "$ORACLE_HOME/dbs/orapw${ORACLE_SID}" ]; then
      cp $ORACLE_HOME/dbs/orapw${ORACLE_SID} /u01/password_share/
    else
      echo "警告：源密码文件不存在"
    fi
    
    # 确保主库处于强制日志记录模式并注册到监听器
    sqlplus / as sysdba << EOF
ALTER DATABASE FORCE LOGGING;
-- 设置LOCAL_LISTENER以确保服务正确注册到监听器
ALTER SYSTEM SET LOCAL_LISTENER='(ADDRESS=(PROTOCOL=TCP)(HOST=0.0.0.0)(PORT=1521))' SCOPE=BOTH;
-- 注册 ORCL 服务，支持 sqlplus user/pass@host:port/ORCL 连接
ALTER SYSTEM SET SERVICE_NAMES='${ORACLE_SID},${ORACLE_SID}_PRIMARY' SCOPE=BOTH;
ALTER SYSTEM REGISTER;
EXIT;
EOF
    
  else
    echo "数据库已存在，启动现有数据库..."
    # 使用fixConfig函数处理配置文件链接
    fixConfig
    
    # 启动数据库
    sqlplus / as sysdba << EOF
STARTUP;
EXIT;
EOF
  fi
  
  # 启动一个简单的健康检查服务
  cat > /tmp/health_check.sql << EOF
set heading off
set feedback off
set pagesize 0
select 'primary_ready' from dual where exists (select 1 from v\$instance where status = 'OPEN');
exit
EOF
  
  # 启动健康检查服务（在后台运行）
  nohup bash -c '
while true; do
  sqlplus -s / as sysdba @/tmp/health_check.sql > /tmp/health_status.txt 2>/dev/null
  if grep -q "primary_ready" /tmp/health_status.txt; then
    echo "HTTP/1.1 200 OK" > /tmp/health_response.txt
    echo "Content-Type: text/plain" >> /tmp/health_response.txt
    echo "" >> /tmp/health_response.txt
    echo "PRIMARY_READY" >> /tmp/health_response.txt
  else
    echo "HTTP/1.1 503 Service Unavailable" > /tmp/health_response.txt
    echo "Content-Type: text/plain" >> /tmp/health_response.txt
    echo "" >> /tmp/health_response.txt
    echo "PRIMARY_NOT_READY" >> /tmp/health_response.txt
  fi
  # 使用nc提供简单的HTTP服务（如果可用）
  if command -v nc >/dev/null 2>&1; then
    cat /tmp/health_response.txt | nc -l -p 8080 >/dev/null 2>&1 || true
  fi
  sleep 30
done
' &

  # 后台进程：等待备库就绪后启用DEST_2
  nohup bash -c '
    echo "等待备库就绪以启用日志传输..."
    retry=0
    max_retry=60
    while [ $retry -lt $max_retry ]; do
      # 检查备库是否可达
      if tnsping ORCL_STANDBY >/dev/null 2>&1; then
        # 尝试连接备库
        result=$(sqlplus -s sys/Oradoc_db1@ORCL_STANDBY as sysdba <<EOF
set heading off feedback off pagesize 0
select status from v\$instance;
exit;
EOF
)
        if echo "$result" | grep -qE "OPEN|MOUNTED"; then
          echo "备库已就绪，启用LOG_ARCHIVE_DEST_2..."
          sqlplus -s / as sysdba <<EOF
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=ENABLE;
ALTER SYSTEM SWITCH LOGFILE;
exit;
EOF
          echo "LOG_ARCHIVE_DEST_2 已启用"
          break
        fi
      fi
      sleep 10
      retry=$((retry+1))
    done
  ' > /tmp/enable_dest2.log 2>&1 &
  
elif [ "$ROLE" = "STANDBY" ]; then
  echo "初始化备库..."
  
  # 检查备库是否已经存在
  if [ ! -d "/u02/oradata/$ORACLE_SID" ] || [ ! -f "/u02/oradata/$ORACLE_SID/control01.ctl" ]; then
    # 创建备库所需目录
    mkdir -p /u02/oradata/$ORACLE_SID
    mkdir -p /u02/fast_recovery_area/$ORACLE_SID
    
    # 等待主库准备就绪（实现更可靠的检测机制）
    echo "等待主库准备就绪..."
    retry_count=0
    max_retries=120
    while [ $retry_count -lt $max_retries ]; do
      # 首先检查网络连通性
      if ping -c 1 oracle-primary >/dev/null 2>&1; then
        echo "主库网络可达"
        
        # 检查主库是否可连接
        if tnsping ${ORACLE_SID}_PRIMARY >/dev/null 2>&1; then
          echo "主库TNS连接正常"
          
          # 尝试连接主库检查状态
          sqlplus -s /nolog << EOF
connect sys/Oradoc_db1@${ORACLE_SID}_PRIMARY as sysdba
set heading off
set feedback off
set pagesize 0
spool /tmp/db_status.txt
select status from v\$instance;
spool off
exit
EOF
          if [ -f /tmp/db_status.txt ] && grep -q "OPEN" /tmp/db_status.txt; then
            echo "主库已启动并处于OPEN状态"
            rm -f /tmp/db_status.txt
            break
          fi
          rm -f /tmp/db_status.txt
        fi
      fi
      
      echo "等待主库启动... ($((retry_count+1))/$max_retries)"
      sleep 10
      retry_count=$((retry_count+1))
    done
    
    if [ $retry_count -eq $max_retries ]; then
      echo "错误：主库未能在规定时间内启动或无法连接"
      exit 1
    fi
    
    # 从主库真实复制密码文件
    echo "从主库复制密码文件..."
    # 修复权限问题，确保目录存在且有正确权限
    if [ ! -d "/u01/password_share" ]; then
      mkdir -p /u01/password_share
    fi
    chmod 777 /u01/password_share 2>/dev/null || true
    
    # 通过共享卷从主库获取密码文件
    # 删除已存在的密码文件
    rm -f $ORACLE_HOME/dbs/orapw${ORACLE_SID}
    if [ -f "/u01/password_share/orapw${ORACLE_SID}" ]; then
      cp /u01/password_share/orapw${ORACLE_SID} $ORACLE_HOME/dbs/
      echo "成功从共享卷复制密码文件"
    else
      # 如果无法从共享卷获取，则创建一个新的密码文件
      echo "警告：无法从主库获取密码文件，创建新的密码文件"
      orapwd file=$ORACLE_HOME/dbs/orapw${ORACLE_SID} password=Oradoc_db1 entries=10
    fi
    
    # 创建备库参数文件
    cat > $ORACLE_HOME/dbs/init${ORACLE_SID}.ora << EOF
*.DB_NAME='${ORACLE_SID}'
*.DB_UNIQUE_NAME='${ORACLE_SID}_STANDBY'
*.DB_CREATE_FILE_DEST='/u02/oradata'
*.DB_CREATE_ONLINE_LOG_DEST_1='/u02/oradata'
*.DB_RECOVERY_FILE_DEST='/u02/fast_recovery_area'
*.DB_RECOVERY_FILE_DEST_SIZE=10G
*.CONTROL_FILES='/u02/oradata/${ORACLE_SID}/control01.ctl'
*.LOG_ARCHIVE_DEST_1='LOCATION=/u02/fast_recovery_area VALID_FOR=(ALL_LOGFILES,ALL_ROLES) DB_UNIQUE_NAME=${ORACLE_SID}_STANDBY'
*.LOG_ARCHIVE_DEST_2='SERVICE=${ORACLE_SID}_PRIMARY LGWR ASYNC VALID_FOR=(ONLINE_LOGFILES,PRIMARY_ROLE) DB_UNIQUE_NAME=${ORACLE_SID}_PRIMARY'
*.LOG_ARCHIVE_DEST_STATE_1=ENABLE
*.LOG_ARCHIVE_DEST_STATE_2=ENABLE
*.LOG_ARCHIVE_FORMAT='%t_%s_%r.dbf'
*.FAL_SERVER='${ORACLE_SID}_PRIMARY'
*.FAL_CLIENT='${ORACLE_SID}_STANDBY'
*.STANDBY_FILE_MANAGEMENT=AUTO
*.LOG_ARCHIVE_CONFIG='DG_CONFIG=(${ORACLE_SID}_PRIMARY,${ORACLE_SID}_STANDBY)'
*.SGA_TARGET=600M
*.PGA_AGGREGATE_TARGET=200M
*.PROCESSES=300
*.AUDIT_FILE_DEST='/u01/app/oracle/admin/${ORACLE_SID}/adump'
*.DIAGNOSTIC_DEST='/u01/app/oracle'
*.REMOTE_LOGIN_PASSWORDFILE=EXCLUSIVE
EOF

    # 创建必要的目录
    mkdir -p /u01/app/oracle/admin/${ORACLE_SID}/adump

    # 启动到nomount状态
    sqlplus / as sysdba << EOF
STARTUP NOMOUNT PFILE='$ORACLE_HOME/dbs/init${ORACLE_SID}.ora';
EXIT;
EOF

    # 使用RMAN从主库创建物理备库
    rman TARGET sys/Oradoc_db1@${ORACLE_SID}_PRIMARY AUXILIARY sys/Oradoc_db1@${ORACLE_SID}_STANDBY << EOF
DUPLICATE TARGET DATABASE FOR STANDBY FROM ACTIVE DATABASE DORECOVER
  NOFILENAMECHECK;
EXIT;
EOF
  else
    # 启动现有备库
    echo "备库数据库已存在，启动数据库..."
    sqlplus / as sysdba << EOF
STARTUP MOUNT;
EXIT;
EOF
  fi

  # 创建 Standby Redo Log（实时 redo 传输必需）
  echo "创建 Standby Redo Log..."
  sqlplus / as sysdba << EOF
-- 添加 4 组 Standby Redo Log（比 Online Redo Log 多一组）
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM V\$STANDBY_LOG;
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M';
    EXECUTE IMMEDIATE 'ALTER DATABASE ADD STANDBY LOGFILE SIZE 50M';
  END IF;
END;
/
EXIT;
EOF

  # 启动redo应用（Active Data Guard - READ ONLY WITH APPLY）
  sqlplus / as sysdba << EOF
-- 先打开数据库为只读模式
ALTER DATABASE OPEN READ ONLY;
-- 注册 ORCL 服务，支持 sqlplus user/pass@host:port/ORCL 连接
ALTER SYSTEM SET SERVICE_NAMES='${ORACLE_SID},${ORACLE_SID}_STANDBY';
ALTER SYSTEM REGISTER;
-- 然后启动实时应用
ALTER DATABASE RECOVER MANAGED STANDBY DATABASE DISCONNECT FROM SESSION;
EXIT;
EOF
  
else
  echo "错误：未知的角色 $ROLE"
  exit 1
fi

# 保持容器运行 - 等待日志文件创建后监控
echo "容器启动完成，等待日志文件..."
while true; do
  ALERT_LOG=$(find /u01/app/oracle/diag/rdbms -name "alert_${ORACLE_SID}.log" 2>/dev/null | head -1)
  if [ -n "$ALERT_LOG" ] && [ -f "$ALERT_LOG" ]; then
    echo "监控日志文件: $ALERT_LOG"
    tail -f "$ALERT_LOG"
  fi
  sleep 5
done