#!/bin/bash
source /home/oracle/.profile
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

# 检查实例是否存在
