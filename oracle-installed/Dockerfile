# ------------------------------------------------------------------------------
# Oracle ADG - 多阶段构建
# ------------------------------------------------------------------------------

ARG BASE_IMAGE=oracle-adg-base:latest

# =============================================================================
# Stage 1: Builder - 安装并设置权限
# =============================================================================
FROM ${BASE_IMAGE} AS builder

ENV ORACLE_BASE=/u01/app/oracle \
    ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
    ORA_INVENTORY=/u01/app/oraInventory \
    SCRIPTS_DIR=/u01/scripts \
    CV_ASSUME_DISTID=OL8

COPY oracle-install/LINUX.X64_193000_db_home.zip /tmp/
COPY scripts/ ${SCRIPTS_DIR}/

# 设置权限
RUN chown -R oracle:oinstall /u01 /u02 /tmp/LINUX.X64_193000_db_home.zip && \
    chmod -R 775 /u02 && chmod -R g+s /u02 && \
    chmod u+x ${SCRIPTS_DIR}/*.sh

# 切换到 oracle 用户执行安装
USER oracle
WORKDIR ${ORACLE_HOME}

RUN unzip -oq /tmp/LINUX.X64_193000_db_home.zip && \
    ${ORACLE_HOME}/runInstaller -ignorePrereq -waitforcompletion -silent \
        oracle.install.option=INSTALL_DB_SWONLY \
        UNIX_GROUP_NAME=oinstall \
        INVENTORY_LOCATION=${ORA_INVENTORY} \
        SELECTED_LANGUAGES=en,en_US \
        ORACLE_HOME=${ORACLE_HOME} \
        ORACLE_BASE=${ORACLE_BASE} \
        oracle.install.db.InstallEdition=EE \
        oracle.install.db.OSDBA_GROUP=dba \
        oracle.install.db.OSBACKUPDBA_GROUP=dba \
        oracle.install.db.OSDGDBA_GROUP=dba \
        oracle.install.db.OSKMDBA_GROUP=dba \
        oracle.install.db.OSRACDBA_GROUP=dba \
        SECURITY_UPDATES_VIA_MYORACLESUPPORT=false \
        DECLINE_SECURITY_UPDATES=true; \
    exit_code=$?; \
    if [ $exit_code -ne 0 ] && [ $exit_code -ne 6 ]; then exit $exit_code; fi

# 切换回 root 执行后续脚本
USER root
RUN [ -f "${ORA_INVENTORY}/orainstRoot.sh" ] && ${ORA_INVENTORY}/orainstRoot.sh || true && \
    [ -f "${ORACLE_HOME}/root.sh" ] && ${ORACLE_HOME}/root.sh || true && \
    mkdir -p ${ORACLE_HOME}/network/admin && \
    echo -e "LISTENER =\n  (DESCRIPTION_LIST =\n    (DESCRIPTION =\n      (ADDRESS = (PROTOCOL = TCP)(HOST = 0.0.0.0)(PORT = 1521))\n      (ADDRESS = (PROTOCOL = IPC)(KEY = EXTPROC1521))\n    )\n  )\nDEFAULT_SERVICE_LISTENER = (SYSTEM)" > ${ORACLE_HOME}/network/admin/listener.ora && \
    echo -e "ORCL_PRIMARY =\n  (DESCRIPTION =\n    (ADDRESS = (PROTOCOL = TCP)(HOST = oracle-primary)(PORT = 1521))\n    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = ORCL)))\n\nORCL_STANDBY =\n  (DESCRIPTION =\n    (ADDRESS = (PROTOCOL = TCP)(HOST = oracle-standby)(PORT = 1521))\n    (CONNECT_DATA = (SERVER = DEDICATED)(SERVICE_NAME = ORCL)))" > ${ORACLE_HOME}/network/admin/tnsnames.ora && \
    chown -R oracle:oinstall ${ORACLE_HOME}/network /u01 /u02 && \
    chmod -R 775 /u02 && chmod -R g+s /u02 && \
    rm -rf ${ORACLE_HOME}/lib/*.zip ${ORACLE_HOME}/inventory/backup/* ${ORACLE_HOME}/*.zip /tmp/*.zip

# =============================================================================
# Stage 2: Runtime - 直接复制（保留权限）
# =============================================================================
FROM ${BASE_IMAGE}

LABEL maintainer="oracle-adg"
LABEL description="Oracle ADG"

ENV ORACLE_BASE=/u01/app/oracle \
    ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
    ORA_INVENTORY=/u01/app/oraInventory \
    SCRIPTS_DIR=/u01/scripts \
    ORAENV_ASK=NO \
    ORACLE_SID=ORCL \
    ORACLE_PDB=ORCLPDB1 \
    ORACLE_CHARACTERSET=AL32UTF8 \
    CV_ASSUME_DISTID=OL8

ENV PATH=${ORACLE_HOME}/bin:${PATH} \
    LD_LIBRARY_PATH=${ORACLE_HOME}/lib:${LD_LIBRARY_PATH}

# 直接复制（COPY 保留权限）
# 注意：不复制 /u02，因为它是数据目录，会被 Docker 卷挂载
COPY --from=builder /u01 /u01

# 以 root 启动，startup.sh 中设置权限后切换到 oracle
# USER oracle

EXPOSE 1521 5500

CMD exec ${SCRIPTS_DIR}/startup.sh
