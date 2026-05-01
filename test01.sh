sql_exec(){
    local sid=$1
    local sql=$2
    local exec_res
    
    exec_res=$(su - oracle -c "
    export ORACLE_SID=$sid
    sqlplus -S / as sysdba <<EOF
    set heading off
    set pages 0
    set feedback off
    set linesize 1000
    prompt ###sql_result_start###
    $sql
    prompt ###sql_result_end###
    exit;
EOF
    " 2>/dev/null | sed -n '/###sql_result_start###/,/###sql_result_end###/p' | grep -v "###sql_")
    
    echo "$exec_res"
}

# 调用测试
sql_exec "ORCL" 'select name from v\$parameter where rownum <= 3;'