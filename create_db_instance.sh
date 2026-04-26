#!/bin/bash
check_oracle_env(){
  result=$(su - oracle -c 'env | grep -E "ORACLE_HOME=|ORACLE_BASE=" 2>/dev/null')
  if [[ -z "$result" ]]; then
    echo "error:无法获取Oracle用户的环境变量"
    return 1
  fi
  if ! echo "$result" | grep -q "ORACLE_HOME="; then
    echo "error:ORACLE_HOME未设置"
    return 1
  fi
  if ! echo "$result" | grep -q "ORACLE_BASE="; then
    echo "error:ORACLE_BASE未设置"
    return 1
  fi
  # 获取具体值
  ORACLE_HOME=$(echo "$result" | grep "ORACLE_HOME=" | cut -d= -f2-)
  ORACLE_BASE=$(echo "$result" | grep "ORACLE_BASE=" | cut -d= -f2-)
  # 检查是否为空值
  if [[ -z "$ORACLE_HOME" ]]; then
    echo 
    return 1
  fi
    if [[ -z "$ORACLE_BASE" ]]; then
    echo "error:ORACLE_BASE值为空"
    return 1
  fi
  return 0
}
create_oracle_pfile_path(){
  if [ -d "$ORACLE_HOME" ] || [ -d "$ORACLE_BASE" ]; then
    read -p "Please input database name:" db_name
    if [ -z "$db_name" ]; then
      echo "error: database name cannot be empty"
      exit 1
    fi
    cd $ORACLE_HOME
    mkdir -p "./$db_name/adump"
    chown oracle:oinstall "./$db_name/adump"
    chmod 777 -R "./$db_name/adump"
  fi
  pfile_dir="$ORACLE_HOME/dbs1"
  if [ ! -d "$pfile_dir" ]; then
    cd $ORACLE_HOME
    mkdir -p "./dbs1"
    chown oracle:oinstall "./$dbs1"
    chmod 777 -R "./$dbs1"
  fi
  create_oracle_pfile
}
create_oracle_pfile(){
  cd $orginal_dir
  echo "current path: $orginal_dir"
  input_file="init.ora"
  output_file="init$db_name.ora"
  if [ ! -f "$input_file" ]; then
    echo "error:$input_file not exits!"
    exit 1
  fi
  read -p "Please input control_files Path(default:):" new_control_path
  new_control_path=${new_control_path:-/}
  read -p "Please input log_archive_dest_1 Path (default:):" new_log_path
  {
    while IFS= read -r line
    do
      if [[ "$line" == *.control_files=* ]]; then
        echo "*.control_files='$new_control_path'"
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
  echo "The pfile has been generated"
}
# 新建实例
create_db_instance(){
  echo "select status from v\$instance;" >/opt/oracle/oradata/workstation/codes/checklogging.sql
  {
    echo "echo 'current ORACLE_HOME: $ORACLE_HOME'"
    echo "echo 'current ORACLE_BASE: $ORACLE_BASE'"
    echo "echo 'current output_file: $output_file'"
    echo "export ORACLE_SID=$db_name"
    echo "sqlplus / as sysdba"
    echo "echo 'startup nomount pfile=\"$pfile_dir/$output_file\"'"
    echo "spool /opt/oracle/oradata/workstation/codes/checklogging.txt"
    echo "@/opt/oracle/oradata/workstation/codes/checklogging.sql"
    echo "spool off"
    echo "EOF"
  } | su - oracle
  echo "The instance $db_name has been created"
}

# 停止实例
stop_db_instance(){
  read -p "Please input instance_name which is needed to stop:" instance_name
  {
    echo "export ORACLE_SID=$instance_name"
    echo "sqlplus / as sysdba <<EOF"
    echo "shutdown immediate"
    echo "EOF"
  } | su - oracle
}
# 主程序
orginal_dir=$(pwd)
echo "正在检查Oracle用户的环境变量"
if check_oracle_env; then
  echo "环境变量检查成功"
  echo "ORACLE_HOME:$ORACLE_HOME"
  echo "ORACLE_BASE:$ORACLE_BASE"
  # 创建参数文件
  create_oracle_pfile_path
  # 创建数据库实例
  create_db_instance
  # 停止数据库实例
  # stop_db_instance
  exit 0
else
  echo "环境变量检查失败，请手工确认是否为Oracle数据库环境"
  exit 1
fi