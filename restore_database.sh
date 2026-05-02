#!/bin/bash
# 通过set newname的方式恢复数据库
restore_database(){
    local RMAN_OUTPUT="/tmp/rename_paths_$(date +%Y%m%d)_$$.rmn"
    local RMAN_LOG="/tmp/rman_rename_$(date +%Y%m%d)_$$.log"
    local sid=$1
    local NEW_DATAFILE_PATH=$2
    local RMAN_BACKUP_PATH=$3
    su - oracle -c "
    export ORACLE_SID=$sid
    cat >> $RMAN_OUTPUT <<EOF
catalog start with '$RMAN_BACKUP_PATH';
run {
EOF
    sqlplus -S / as sysdba <<'EOF' >>$RMAN_OUTPUT
    set pagesize 0 feedback off verify off heading off trimspool on
    select 'set newname for datafile ' || file# || ' to ''' || '$NEW_DATAFILE_PATH/' || substr(name, instr(name, '/', -1)+1) || ''';' from v\$datafile;
    select 'set newname for tempfile ' || file# || ' to ''' || '$NEW_DATAFILE_PATH/' || substr(name, instr(name, '/', -1)+1) || ''';' from v\$tempfile;
    exit;
EOF
    cat >> $RMAN_OUTPUT <<EOF
restore database;
SWITCH DATAFILE ALL;
SWITCH TEMPFILE ALL;
recover database;
}
EOF
    rman target / cmdfile=$RMAN_OUTPUT log=$RMAN_LOG
    "
    echo "完成！日志：$RMAN_LOG"
}
sid="ORCL"
path="/opt/oracle19c/oradata/data/ORCL"
backup_path='/opt/oracle19c/oradata/backup'
restore_database "$sid" "$path" "$backup_path"
