# Oracle Active Data Guard Docker 环境

基于 Docker Compose 的 Oracle 19c 一主一备 ADG（Active Data Guard）环境，支持**近实时同步**。

## 特性

- **分层镜像构建**：oracle-base（系统依赖） → oracle-installed（Oracle软件）
- **LGWR ASYNC 实时传输**：主库变更秒级同步到备库
- **Active Data Guard**：备库 READ ONLY WITH APPLY 模式，可同时查询和应用日志
- **自动化部署**：一键启动，自动完成主库创建、备库克隆、DG配置

## 系统要求

- Docker 18.06+, Docker Compose 1.22+
- 内存 ≥ 16GB（推荐 48GB+）
- 磁盘 ≥ 100GB
- Oracle 安装包：`LINUX.X64_193000_db_home.zip`

## 快速开始

### 1. 准备安装包

将 Oracle 19c 安装包放入 `oracle-install/` 目录：

```bash
ls oracle-install/
# LINUX.X64_193000_db_home.zip
```

### 2. 构建镜像

```bash
chmod +x scripts/*.sh build.sh
docker-compose build
```

### 3. 启动环境

```bash
docker-compose up -d oracle-primary oracle-standby
```

首次启动需要约 15-20 分钟完成数据库创建和备库克隆。

### 4. 查看日志

```bash
docker logs -f oracle-primary   # 主库日志
docker logs -f oracle-standby   # 备库日志
```

## 连接信息

| 角色 | 主机 | 端口 | SID | 密码 |
|------|------|------|-----|------|
| 主库 | localhost | 1521 | ORCL | Oradoc_db1 |
| 备库 | localhost | 1522 | ORCL | Oradoc_db1 |

### sqlplus 连接示例

```bash
# 本机连接主库
sqlplus sys/Oradoc_db1@localhost:1521/ORCL as sysdba

# 本机连接备库（只读）
sqlplus sys/Oradoc_db1@localhost:1522/ORCL as sysdba

# 远程连接（将 <HOST_IP> 替换为实际 IP 地址）
sqlplus sys/Oradoc_db1@<HOST_IP>:1521/ORCL as sysdba
sqlplus sys/Oradoc_db1@<HOST_IP>:1522/ORCL as sysdba

# 使用普通用户连接（需先创建用户）
sqlplus username/password@<HOST_IP>:1521/ORCL
```

### Easy Connect 格式

```
sqlplus user/password@host:port/service_name
```

示例：
```bash
# 完整格式
sqlplus sys/Oradoc_db1@//192.168.1.100:1521/ORCL as sysdba

# 简化格式
sqlplus sys/Oradoc_db1@192.168.1.100:1521/ORCL as sysdba
```

## 状态检查

```bash
# 使用脚本
./scripts/check_status.sh

# 或手动检查主库状态
docker exec -u oracle oracle-primary bash -c 'sqlplus -s / as sysdba <<EOF
SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;
EOF'

# 检查备库状态
docker exec -u oracle oracle-standby bash -c 'sqlplus -s / as sysdba <<EOF
SELECT DATABASE_ROLE, OPEN_MODE FROM V\$DATABASE;
EOF'

# 检查同步延迟
docker exec -u oracle oracle-standby bash -c 'sqlplus -s / as sysdba <<EOF
SELECT NAME, VALUE FROM V\$DATAGUARD_STATS WHERE NAME IN ('"'"'transport lag'"'"', '"'"'apply lag'"'"');
EOF'
```

正常状态：
- 主库：`PRIMARY` / `READ WRITE`
- 备库：`PHYSICAL STANDBY` / `READ ONLY WITH APPLY`
- 同步延迟：`+00 00:00:00`（秒级）

## 常用命令

```bash
# 停止
docker-compose stop

# 启动
docker-compose start

# 重启
docker-compose restart

# 删除（包括数据）
docker-compose down -v

# 查看容器状态
docker-compose ps
```

## 目录结构

```
docker-oracledg/
├── docker-compose.yml      # 服务编排
├── build.sh                # 构建脚本
├── oracle-base/            # 基础镜像（系统依赖）
│   └── Dockerfile
├── oracle-installed/       # 应用镜像（Oracle软件）
│   └── Dockerfile
├── oracle-install/         # 安装包目录
│   └── LINUX.X64_193000_db_home.zip
└── scripts/
    ├── startup.sh          # 容器启动脚本
    ├── check_*.sh/sql      # 状态检查脚本
    └── switchover_*.sh/sql # 主备切换脚本
```

## 主备切换

```bash
./scripts/switchover_test.sh
```

> 注意：主备切换是高风险操作，请先确认同步正常。

## 故障排除

### 备库同步延迟

```bash
# 检查 DEST_2 状态
docker exec -u oracle oracle-primary bash -c 'sqlplus -s / as sysdba <<EOF
SELECT DEST_ID, STATUS, ERROR FROM V\$ARCHIVE_DEST WHERE DEST_ID=2;
EOF'

# 如果 ERROR，重新启用
docker exec -u oracle oracle-primary bash -c 'sqlplus -s / as sysdba <<EOF
ALTER SYSTEM SET LOG_ARCHIVE_DEST_STATE_2=ENABLE;
ALTER SYSTEM SWITCH LOGFILE;
EOF'
```

### 容器启动失败

```bash
# 查看详细日志
docker logs oracle-primary 2>&1 | tail -100
docker logs oracle-standby 2>&1 | tail -100
```

### 重新部署

```bash
docker-compose down -v
docker-compose up -d oracle-primary oracle-standby
```

### 内网构建
需要先在外网构建构建 oracle-adg-base ，然后导出，再放到内网继续构建
1. 外网
```bash
docker-compose build oracle-base
docker save oracle-adg-base | bzip2 > oracle-adg-base.tar.bz2
```

2. 内网
```bash
docker load -i oracle-adg-base.tar.bz2
docker-compose build oracle-installed
docker-compose up -d oracle-primary oracle-standby

# 监控日志
docker logs -f oracle-primary   # 主库日志
docker logs -f oracle-standby   # 备库日志
```


