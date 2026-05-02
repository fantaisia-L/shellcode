#!/bin/bash
modify_control_file(){
    local sid=$1
    local NEW_DATAFILE_PATH=$2
    local NEW_LOG_PATH=$3
    local SQL_OUTPUT="/tmp/modify_controlfile_$(date +%Y%m%d)_$$.sql"
    su - oracle -c "
    export ORACLE_SID=$sid
    sqlplus -S / as sysdba <<'EOF' >>$SQL_OUTPUT
    set pagesize 0 feedback off verify off heading off trimspool on
    select 'alter database rename file '||name|| ' to ''' || '$NEW_DATAFILE_PATH/' || substr(name, instr(name, '/', -1)+1) || ''';' from v\$datafile;
    select 'set newname for tempfile ' || file# || ' to ''' || '$NEW_DATAFILE_PATH/' || substr(name, instr(name, '/', -1)+1) || ''';' from v\$tempfile;
    exit;
EOF
    cat >> $RMAN_OUTPUT <<EOF
restore database;
SWITCH DATAFILE ALL;
SWITCH TEMPFILE ALL;
}
EOF
    rman target / cmdfile=$RMAN_OUTPUT log=$RMAN_LOG
    "
    echo "完成！日志：$RMAN_LOG"
}
sid="ORCL"
data_path="/opt/oracle19c/oradata/data/ORCL"
log_path="/opt/oracle19c/oradata/log/ORCL"
backup_path='/opt/oracle19c/oradata/backup'
modify_control_file "$sid" "$data_path" "$log_path"
