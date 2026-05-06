#!/bin/bash

# ==========================================================
# 变量配置 (请根据实际情况修改)
# ==========================================================
export ORACLE_SID=your_sid_here
export ORACLE_HOME=/u01/app/oracle/product/19c/dbhome_1
export PATH=$ORACLE_HOME/bin:$PATH

# 数据库名称
DB_NAME="YOUR_DB_NAME"
# 数据文件存放目录 (支持通配符或手动列出)
DATAFILES_PATH="/u01/app/oracle/oradata/${DB_NAME}/*.dbf"
# 新的 Redo Log 存放路径
REDO_PATH="/u01/app/oracle/oradata/${DB_NAME}"

# ==========================================================
# 脚本核心逻辑
# ==========================================================

# 1. 获取所有数据文件列表并格式化
FILES_LIST=$(ls $DATAFILES_PATH | sed "s/^/'/;s/$/'/" | paste -sd "," -)

# 2. 生成重建控制文件的 SQL 语句
RECREATE_SQL="
STARTUP NOMOUNT;
CREATE CONTROLFILE REUSE DATABASE \"$DB_NAME\" RESETLOGS  NOARCHIVELOG
    MAXLOGFILES 16
    MAXLOGMEMBERS 3
    MAXDATAFILES 100
    MAXINSTANCES 8
    MAXLOGHISTORY 292
LOGFILE
  GROUP 1 '$REDO_PATH/redo01.log'  SIZE 512M,
  GROUP 2 '$REDO_PATH/redo02.log'  SIZE 512M,
  GROUP 3 '$REDO_PATH/redo03.log'  SIZE 512M
DATAFILE
  $FILES_LIST
CHARACTER SET AL32UTF8; -- 请确保字符集与原库一致
"

# 3. 执行 SQL
sqlplus / as sysdba <<EOF
SHUTDOWN ABORT;
$RECREATE_SQL
-- 此时控制文件已重建，处于 MOUNT 状态
ALTER DATABASE OPEN RESETLOGS;
EOF