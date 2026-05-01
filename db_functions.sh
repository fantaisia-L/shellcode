#!/bin/bash

# 全局变量（统一管理，避免重复定义）
typeset -rx CODES_DIR="/opt/oracle19c/oradata/codes"
typeset -rx DEFAULT_CONTROL_PATH="/opt/oracle19c/oradata/data"
typeset -rx DEFAULT_LOG_PATH="/opt/oracle19c/oradata/log"

# ======================================================================
# 检查 Oracle 环境变量（ORACLE_HOME / ORACLE_BASE）
# ======================================================================
check_oracle_env() {
    local result
    result=$(su - oracle -c 'env | grep -E "ORACLE_HOME=|ORACLE_BASE=" 2>/dev/null')

    if [[ -z "$result" ]]; then
        echo "ERROR: 无法获取 oracle 用户环境变量"
        return 1
    fi

    if ! echo "$result" | grep -q "ORACLE_HOME="; then
        echo "ERROR: ORACLE_HOME 未设置"
        return 1
    fi

    if ! echo "$result" | grep -q "ORACLE_BASE="; then
        echo "ERROR: ORACLE_BASE 未设置"
        return 1
    fi

    # 赋值全局变量
    ORACLE_HOME=$(echo "$result" | awk -F= '/ORACLE_HOME=/ {print $2}')
    ORACLE_BASE=$(echo "$result" | awk -F= '/ORACLE_BASE=/ {print $2}')

    if [[ -z "$ORACLE_HOME" || -z "$ORACLE_BASE" ]]; then
        echo "ERROR: ORACLE_HOME 或 ORACLE_BASE 值为空"
        return 1
    fi

    echo "✅ 环境变量检查通过"
    return 0
}

# ======================================================================
# 检查实例是否存在（通过smon进程）
# ======================================================================
check_instance_exists() {
    local db_name="$1"
    if [[ -z "$db_name" ]]; then
        return 1
    fi
    ps -ef | grep -v grep | grep -q "ora_smon_${db_name}$"
    return $?
}

# ======================================================================
# 创建实例目录 & 生成 pfile
# ======================================================================
create_oracle_pfile_path() {
    # 创建 adump 目录
    local adump_dir="${ORACLE_HOME}/${db_name}/adump"
    mkdir -p "${adump_dir}"
    chown oracle:oinstall "${adump_dir}"
    chmod 750 "${adump_dir}"

    # pfile 输出目录
    pfile_dir="${ORACLE_HOME}/dbs1"
    mkdir -p "${pfile_dir}"
    chown oracle:oinstall "${pfile_dir}"
    chmod 750 "${pfile_dir}"
}

# ======================================================================
# 生成 pfile 文件（替换模板）
# ======================================================================
create_oracle_pfile() {
    local orginal_dir="$1"
    local input_file="${orginal_dir}/init.ora"
    output_file="init${db_name}.ora"

    if [[ ! -f "${input_file}" ]]; then
        echo "ERROR: 模板文件 ${input_file} 不存在"
        return 1
    fi

    read -p "请输入 control_files 路径 [默认: ${DEFAULT_CONTROL_PATH}]: " new_control_path
    new_control_path=${new_control_path:-${DEFAULT_CONTROL_PATH}}

    read -p "请输入 log_archive_dest_1 路径 [默认: ${DEFAULT_LOG_PATH}]: " new_log_path
    new_log_path=${new_log_path:-${DEFAULT_LOG_PATH}}

    # 生成 pfile
    {
        while IFS= read -r line
        do
            if [[ "$line" == *.control_files=* ]]; then
                echo "*.control_files='$new_control_path/$db_name/control.ctl'"
            elif [[ "$line" == *.log_archive_dest_1=* ]]; then
                echo "*.log_archive_dest_1='LOCATION=$new_log_path'"
            elif [[ "$line" == *.audit_file_dest=* ]]; then
                echo "*.audit_file_dest='$ORACLE_HOME/$db_name/adump'"
            elif [[ "$line" == *.diagnostic_dest=* ]]; then
                echo "*.diagnostic_dest='$ORACLE_HOME'"
            else
                echo "$line"
            fi
        done < "$input_file"
    } > "$pfile_dir/$output_file"
    chown oracle:oinstall "${pfile_dir}/${output_file}"
    echo "✅ pfile 已生成: ${pfile_dir}/${output_file}"
}

# ======================================================================
# 创建实例（主逻辑）
# ======================================================================
create_db_instance() {
    local orginal_dir
    orginal_dir=$(pwd)

    echo "================================================"
    echo "           开始创建 Oracle 实例"
    echo "================================================"

    # 检查环境
    if ! check_oracle_env; then
        echo "❌ 环境检查失败，返回菜单"
        return 1
    fi

    read -p "请输入数据库名: " db_name
    if [[ -z "$db_name" ]]; then
        echo "❌ 数据库名不能为空"
        return 1
    fi

    if check_instance_exists "${db_name}"; then
        echo "❌ 实例 ${db_name} 已存在，禁止重复创建"
        return 1
    fi

    # 创建目录 + 生成 pfile
    create_oracle_pfile_path
    create_oracle_pfile "${orginal_dir}"

    # 启动实例到 nomount
    mkdir -p "${CODES_DIR}"
    echo "select status from v\$instance;" > "${CODES_DIR}/checklogging.sql"

    su - oracle -c "
        export ORACLE_SID=${db_name}
        export ORACLE_HOME=${ORACLE_HOME}
        echo 'ORACLE_HOME: ' \$ORACLE_HOME
        echo 'ORACLE_SID: ' \$ORACLE_SID
        sqlplus / as sysdba <<EOF
        startup nomount pfile='${pfile_dir}/${output_file}'
        spool ${CODES_DIR}/checklogging.txt
        @${CODES_DIR}/checklogging.sql
        spool off
        exit
EOF
    "

    echo "================================================"
    echo "✅ 实例 ${db_name} 创建完成！"
    echo "================================================"
}

# ======================================================================
# 停止实例
# ======================================================================
stop_db_instance() {
    echo "================================================"
    echo "               停止 Oracle 实例"
    echo "================================================"

    read -p "请输入要停止的实例名: " instance_name

    if [[ -z "${instance_name}" ]]; then
        echo "❌ 实例名不能为空"
        return 1
    fi

    if ! check_instance_exists "${instance_name}"; then
        echo "❌ 实例 ${instance_name} 不存在，返回菜单"
        return 1
    fi

    echo "✅ 实例 ${instance_name} 存在，准备停止..."

    su - oracle -c "
        export ORACLE_SID=${instance_name}
        sqlplus / as sysdba <<EOF
        shutdown immediate;
        exit
EOF
    "

    echo "✅ 实例 ${instance_name} 已停止"
}

restore_db_file_system(){
    # 恢复控制文件
    source /home/oracle/.profile
    read -p "Please enter the database instance that needs to be restored:" instance_name
    instance_name=${instance_name:-ORCL}
    echo $instance_name
    if ! check_instance_exists "${instance_name}"; then
        echo "❌ 实例 ${instance_name} 不存在"
        return 1
    fi
    # 读取参数中控制文件位置
    local control_file=$(sql_exec "$instance_name" "select REGEXP_SUBSTR(value, '[^,]+', 1, 1) from v\\\$parameter where name='control_files';")
    local archive_path=$(sql_exec "$instance_name" "select substr(value, instr(value,'=')+1) from v\\\$parameter where name='log_archive_dest_1';")
    echo "$control_file"
    echo "$archive_path"
}

sql_exec(){
    local sid=$1
    local sql=$2
    local exec_res
    exec_res=$(su oracle -c "
    export ORACLE_SID=$sid
    sqlplus -S / as sysdba <<EOF
    set heading off
    select 1 from dual;
    prompt ###sql_result_start###
    $sql
    prompt ###sql_result_end###
    exit;
EOF
    " 2>/dev/null | sed -n '/###sql_result_start###/,/###sql_result_end###/p' | grep -v "###sql_result" | grep -v ^$)
    echo "$exec_res"
}


full_data_base_backup(){
  source /home/oracle/.profile
  read -p "Please enter the backup(default:/opt/oracle19c/oradata/backup):" backup_path
  backup_path=${backup_path:-/opt/oracle19c/oradata/backup}
  echo $backup_path
  echo "ORACLE_HOME: $ORACLE_HOME"
  echo "ORACLE_BASE: $ORACLE_BASE"
  echo "ORACLE_SID: $ORACLE_SID"
  LOGFILE="$backup_path/${ORACLE_SID}_$(date +"%Y%m%d_%H%M%S").log"
  echo $LOGFILE
  su - oracle -c "
	rman target / log=$LOGFILE <<EOF
        run {
            allocate channel t1 type disk;
            allocate channel t2 type disk;
            backup database format '$backup_path/%d_FULL_%T_%U_%p';
            backup current controlfile format '$backup_path/%d_CF_%T_%U';
            release channel t1;
            release channel t2;
        }
EOF
    "
}