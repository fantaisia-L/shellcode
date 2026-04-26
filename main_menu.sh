#!/bin/bash
source ./db_functions.sh

main_menu() {
    while true; do
        clear
        echo "================================================"
        echo "               Oracle 实例管理工具"
        echo "================================================"
        echo "1) 创建实例"
        echo "2) 停止实例"
        echo "3) 数据库备份（FULL）"
        echo "4) 基于单节点的全库恢复（filesystem）"
        echo "5) 退出"
        echo "================================================"
        read -p "请选择操作: " opt

        case $opt in
            1) create_db_instance ;;
            2) stop_db_instance ;;
            3) full_data_base_backup ;;
            4) restore_db_file_system ;;
            5) echo "👋 退出"; exit 0 ;;
            *) echo "❌ 输入错误" ;;
        esac

        echo -e "\n按回车返回菜单..."
        read
    done
}

main_menu