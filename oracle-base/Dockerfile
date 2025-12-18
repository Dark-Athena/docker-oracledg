# ------------------------------------------------------------------------------
# Oracle ADG Base - 多阶段构建优化
# ------------------------------------------------------------------------------

FROM oraclelinux:8 AS builder

ENV ORACLE_BASE=/u01/app/oracle \
    ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
    ORA_INVENTORY=/u01/app/oraInventory \
    SOFTWARE_DIR=/u01/software \
    SCRIPTS_DIR=/u01/scripts

# 安装依赖（包含 gosu 用于容器内切换用户）
RUN dnf install -y --setopt=install_weak_deps=False --setopt=max_parallel_downloads=10 \
    oracle-database-preinstall-19c openssl curl unzip hostname procps-ng ksh \
    binutils gcc gcc-c++ glibc glibc-devel libaio libaio-devel libgcc \
    libstdc++ libstdc++-devel make sysstat unixODBC unixODBC-devel tar sudo shadow-utils && \
    curl -fsSL -o /usr/local/bin/gosu https://gh.llkk.cc/https://github.com/tianon/gosu/releases/download/1.17/gosu-amd64 && \
    chmod +x /usr/local/bin/gosu && \
    dnf clean all && rm -rf /var/cache/dnf /var/log/dnf* /var/log/hawkey*

# 创建用户和目录
RUN groupadd -g 500 dba 2>/dev/null || true && \
    groupadd -g 501 oinstall 2>/dev/null || true && \
    useradd -d /home/oracle -u 500 -g oinstall -G dba -m -s /bin/bash oracle 2>/dev/null || true && \
    mkdir -p ${ORACLE_HOME} ${ORA_INVENTORY} ${SOFTWARE_DIR} ${SCRIPTS_DIR} \
             /u02/oradata /u02/fast_recovery_area /u02/config /u01/password_share && \
    chown -R oracle:oinstall /u01 /u02 && \
    chmod -R 775 /u02 && chmod -R g+s /u02 && \
    chmod 777 /u01/password_share && \
    echo "oracle ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    touch /etc/oratab && chown oracle:oinstall /etc/oratab && chmod 664 /etc/oratab

# =============================================================================
# Stage 2: 最终镜像
# =============================================================================
FROM scratch

LABEL maintainer="oracle-adg"
LABEL description="Oracle ADG Base Image"

# 从 builder 复制
# COPY --from=builder /usr /usr
# COPY --from=builder /etc /etc
# COPY --from=builder /var/lib/rpm /var/lib/rpm
# COPY --from=builder /var/lib/dnf /var/lib/dnf
# COPY --from=builder /home /home
# COPY --from=builder /u01 /u01
# COPY --from=builder /u02 /u02
COPY --from=builder / /

# 重新设置权限（COPY 不保留所有权）
RUN chown -R 500:501 /u01 /u02 && \
    chmod -R 775 /u02 && chmod -R g+s /u02 && \
    chmod 777 /u01/password_share && \
    chown 500:501 /etc/oratab && chmod 664 /etc/oratab

ENV ORACLE_BASE=/u01/app/oracle \
    ORACLE_HOME=/u01/app/oracle/product/19.0.0/dbhome_1 \
    ORA_INVENTORY=/u01/app/oraInventory \
    SOFTWARE_DIR=/u01/software \
    SCRIPTS_DIR=/u01/scripts \
    ORAENV_ASK=NO \
    ORACLE_SID=ORCL \
    ORACLE_PDB=ORCLPDB1 \
    ORACLE_CHARACTERSET=AL32UTF8 \
    CV_ASSUME_DISTID=OL8

ENV PATH=${ORACLE_HOME}/bin:${PATH} \
    LD_LIBRARY_PATH=${ORACLE_HOME}/lib:${LD_LIBRARY_PATH}

CMD ["/bin/bash"]
