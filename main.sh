#!/bin/bash
source ./db_functions.sh

main() {
  while true; do
    clear
    echo "==================== 主菜单 ===================="
    echo "1. 新建数据库实例"
    echo "2. 停止数据库实例"
    echo "3. 退出"
    echo "================================================"
    read -p "请输入选项[1/2/3]：" choice

    case $choice in
      1)
        create_db_instance
        read -p "按回车继续..."
        ;;
      2)
        stop_db_instance
        read -p "按回车继续..."
        ;;
      3)
        echo "👋 退出脚本"
        exit 0
        ;;
      *)
        echo "输入错误，请重新选择"
        sleep 1
        ;;
    esac
  done
}
main