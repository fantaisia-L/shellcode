#!/bin/bash
# =================================================================
# 脚本名称: universal_controlfile_editor.sh
# 功能描述: 通用的控制文件脚本编辑器 - 自动识别并修改 redo 和数据文件路径
# 使用方法: ./universal_controlfile_editor.sh <输入SQL文件> [输出SQL文件]
# =================================================================

# 默认参数
INPUT_FILE="${1:-/home/oracle/ctl_scripta.sql}"
OUTPUT_FILE="${2:-/home/oracle/ctl_modified_$(date +%Y%m%d_%H%M%S).sql}"
MODE="${3:-RESETLOGS}"  # RESETLOGS 或 NORESETLOGS

# 新的配置参数（可根据需要修改）
NEW_REDO_PATH="${NEW_REDO_PATH:-/opt/oracle19c/oradata/log/ORCL}"
NEW_REDO_SIZE="${NEW_REDO_SIZE:-200M}"
NEW_REDO_GROUP_COUNT="${NEW_REDO_GROUP_COUNT:-5}"
NEW_DATA_PATH_PREFIX="${NEW_DATA_PATH_PREFIX:-}"  # 可选：替换数据文件路径前缀

# 日志文件
LOG_FILE="/home/oracle/ctl_editor_$(date +%Y%m%d_%H%M%S).log"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE"
    exit 1
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" | tee -a "$LOG_FILE"
}

# 检查输入文件
check_input_file() {
    if [ ! -f "$INPUT_FILE" ]; then
        log_error "输入文件 $INPUT_FILE 不存在"
    fi
    log_info "输入文件: $INPUT_FILE"
    log_info "输出文件: $OUTPUT_FILE"
}

# 自动检测数据库名称
detect_dbname() {
    DBNAME=$(grep -i "DATABASE.*\"[^\"]*\"" "$INPUT_FILE" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    if [ -z "$DBNAME" ]; then
        DBNAME="UNKNOWN"
        log_warn "无法检测数据库名称，使用默认值: $DBNAME"
    else
        log_info "检测到数据库名称: $DBNAME"
    fi
}

# 自动检测字符集
detect_charset() {
    CHARSET=$(grep -i "CHARACTER SET" "$INPUT_FILE" | head -1 | awk '{print $NF}' | sed 's/;//')
    if [ -z "$CHARSET" ]; then
        CHARSET="AL32UTF8"
        log_warn "无法检测字符集，使用默认值: $CHARSET"
    else
        log_info "检测到字符集: $CHARSET"
    fi
}

# 自动检测原始 redo 路径和大小
detect_original_redo() {
    ORIGINAL_REDO_PATH=$(grep -E "^[[:space:]]+GROUP.*\.log'" "$INPUT_FILE" | head -1 | sed "s/.*'\([^']*\)'.*/\1/" | xargs dirname)
    ORIGINAL_REDO_SIZE=$(grep -E "^[[:space:]]+GROUP.*SIZE" "$INPUT_FILE" | head -1 | sed 's/.*SIZE \([^ ]*\).*/\1/')
    
    if [ -n "$ORIGINAL_REDO_PATH" ]; then
        log_info "检测到原始 redo 路径: $ORIGINAL_REDO_PATH"
    fi
    if [ -n "$ORIGINAL_REDO_SIZE" ]; then
        log_info "检测到原始 redo 大小: $ORIGINAL_REDO_SIZE"
    fi
}

# 自动检测数据文件路径模式（改进版 - 基于上下文）
detect_datafile_pattern() {
    # 从提取的控制文件部分中查找数据文件路径模式
    local control_section="/tmp/control_section.tmp"
    
    if [ ! -f "$control_section" ]; then
        log_warn "控制文件部分不存在，跳过路径模式检测"
        return
    fi
    
    # 方法1：从 DATAFILE 行后查找第一个数据文件路径
    local first_datafile=$(sed -n '/^DATAFILE/,/^[^[:space:]]/p' "$control_section" | \
                           grep -E "^[[:space:]]+'/" | head -1 | \
                           sed "s/^[[:space:]]+'\(.*\)\/[^/]*[',].*/\1/")
    
    # 方法2：如果方法1失败，尝试更宽松的匹配
    if [ -z "$first_datafile" ]; then
        first_datafile=$(grep -E "^[[:space:]]+'/[^']+" "$control_section" | head -1 | \
                         sed "s/^[[:space:]]+'\(.*\)\/[^/]*[',].*/\1/")
    fi
    
    if [ -n "$first_datafile" ]; then
        DATAFILE_PATTERN="$first_datafile"
        log_info "检测到数据文件路径模式: $DATAFILE_PATTERN"
    else
        DATAFILE_PATTERN=""
        log_warn "无法检测数据文件路径模式"
    fi
}

# 提取指定模式的控制文件部分（改进版 - 更精确的上下文提取）
extract_controlfile_section() {
    local mode=$1
    local section_start=""
    
    if [ "$mode" = "RESETLOGS" ]; then
        section_start="--     Set #2. RESETLOGS case"
    else
        section_start="--     Set #1. NORESETLOGS case"
    fi
    
    log_info "提取 $mode 模式的控制文件部分..."
    
    # 改进的提取方法：基于上下文，从 STARTUP NOMOUNT 到第一个空行或分号
    sed -n "/$section_start/,/--     Set #[12]\./p" "$INPUT_FILE" | \
        sed -n "/STARTUP NOMOUNT/,/^[[:space:]]*$/p" > /tmp/control_section_raw.tmp
    
    # 提取完整的 CREATE CONTROLFILE 命令（从 CREATE 到分号）
    sed -n "/CREATE CONTROLFILE/,/^[[:space:]]*;/p" /tmp/control_section_raw.tmp > /tmp/control_section.tmp
    
    if [ ! -s /tmp/control_section.tmp ]; then
        # 备选方法：直接提取 CREATE 到 CHARACTER SET
        sed -n "/$section_start/,/--     Set #[12]\./p" "$INPUT_FILE" | \
            sed -n "/CREATE CONTROLFILE/,/CHARACTER SET/p" > /tmp/control_section.tmp
    fi
    
    if [ ! -s /tmp/control_section.tmp ]; then
        log_error "无法提取 $mode 模式的控制文件部分"
    fi
    
    log_info "提取完成，文件大小: $(wc -l < /tmp/control_section.tmp) 行"
}

# 智能提取数据文件（基于上下文，支持无后缀文件）
extract_datafiles_context() {
    local input_section=$1
    local output_file=$2
    
    log_info "使用上下文智能匹配提取数据文件..."
    
    # 策略1：基于 DATAFILE 关键字的上下文提取
    sed -n '/^DATAFILE/,/^[^[:space:]]/p' "$input_section" | \
        grep -v "^DATAFILE" | \
        grep -v "^--" | \
        grep -E "^[[:space:]]+'/[^']+" > "$output_file"
    
    # 策略2：如果策略1失败，提取所有符合路径格式的行（排除 LOGFILE）
    if [ ! -s "$output_file" ]; then
        log_info "策略1未找到数据文件，尝试策略2..."
        grep -E "^[[:space:]]+'/[^']+" "$input_section" | \
            grep -v "LOGFILE" | \
            grep -v "GROUP" | \
            grep -v "STANDBY" > "$output_file"
    fi
    
    # 策略3：如果还失败，尝试更宽松的匹配（允许任意空白）
    if [ ! -s "$output_file" ]; then
        log_info "策略2未找到数据文件，尝试策略3（宽松匹配）..."
        grep -E "'/[^']+'" "$input_section" | \
            grep -v "LOGFILE" | \
            grep -v "GROUP" | \
            grep -v "STANDBY" | \
            grep -v "CHARACTER" > "$output_file"
    fi
    
    # 清理格式：去除行尾逗号和空格，去除首尾单引号
    if [ -s "$output_file" ]; then
        sed -i "s/,[[:space:]]*$//" "$output_file"
        sed -i "s/^[[:space:]]*'//" "$output_file"
        sed -i "s/'[[:space:]]*$//" "$output_file"
        sed -i '/^$/d' "$output_file"
        
        local count=$(wc -l < "$output_file")
        log_info "成功提取 $count 个数据文件"
        
        # 显示前3个示例
        if [ $count -gt 0 ]; then
            log_info "数据文件示例:"
            head -3 "$output_file" | while read line; do
                echo "  - $line" | tee -a "$LOG_FILE"
            done
        fi
    else
        log_warn "未找到任何数据文件，请检查输入文件格式"
        # 创建空文件避免后续错误
        touch "$output_file"
    fi
}

# 智能修改数据文件路径（支持多种路径格式）
modify_datafile_paths_advanced() {
    local input_file=$1
    local output_file=$2
    local old_prefix=$3
    local new_prefix=$4
    
    if [ ! -s "$input_file" ]; then
        log_warn "数据文件列表为空"
        return
    fi
    
    if [ -n "$new_prefix" ] && [ -n "$old_prefix" ]; then
        log_info "替换数据文件路径: $old_prefix -> $new_prefix"
        
        # 方法1：标准替换
        sed "s|^$old_prefix|$new_prefix|" "$input_file" >> "$output_file"
        
        # 验证替换结果
        local changed=$(grep -c "^$new_prefix" "$output_file" 2>/dev/null || echo "0")
        local total=$(wc -l < "$input_file")
        
        if [ "$changed" -eq "$total" ]; then
            log_info "成功替换所有 $total 个数据文件路径"
        else
            log_warn "仅替换了 $changed/$total 个数据文件路径"
        fi
    else
        log_info "保持原始数据文件路径"
        # 重新添加单引号和格式
        sed "s/^/  '/" "$input_file" | sed "s/$/',/" >> "$output_file"
        # 处理最后一行没有逗号的情况（会在后续处理）
        return
    fi
}

# 生成新的 redo 日志配置
generate_redo_logs() {
    local output_file=$1
    local group_count=$2
    local redo_path=$3
    local redo_size=$4
    
    log_info "生成 $group_count 个 redo 日志组..."
    
    for i in $(seq 1 $group_count); do
        if [ $i -eq 1 ]; then
            echo "  GROUP $i '$redo_path/redo$(printf "%02d" $i).log'  SIZE $redo_size BLOCKSIZE 512" >> "$output_file"
        else
            echo "  GROUP $i '$redo_path/redo$(printf "%02d" $i).log'  SIZE $redo_size BLOCKSIZE 512," >> "$output_file"
        fi
    done
    
    # 最后一个需要处理逗号
    if [ $group_count -gt 0 ]; then
        # 获取最后一行行号
        local last_line=$(wc -l < "$output_file")
        # 移除最后一行的逗号（GNU sed 和 BSD sed 兼容）
        sed -i ''$last_line' s/,$//' "$output_file" 2>/dev/null || \
        sed -i "${last_line}s/,$//" "$output_file"
    fi
}

# 提取临时文件命令（改进版）
extract_tempfile_commands() {
    local output_file=$1
    
    log_info "提取临时文件添加命令..."
    
    echo "" >> "$output_file"
    echo "-- 添加临时文件" >> "$output_file"
    
    # 尝试多种模式提取临时文件
    local tempfile_found=false
    
    # 模式1：标准格式
    if sed -n '/-- Commands to add tempfiles/,/-- End of tempfile additions./p' "$INPUT_FILE" | \
       grep -E "^ALTER TABLESPACE.*ADD TEMPFILE" >> "$output_file"; then
        tempfile_found=true
    fi
    
    # 模式2：RESETLOGS 部分的临时文件
    if [ "$tempfile_found" = false ]; then
        sed -n "/--     Set #2. RESETLOGS case/,/-- End of tempfile additions./p" "$INPUT_FILE" | \
            grep -E "^ALTER TABLESPACE.*ADD TEMPFILE" >> "$output_file"
        [ -s "$output_file.tmp" ] && tempfile_found=true
    fi
    
    if [ "$tempfile_found" = true ]; then
        log_info "成功提取临时文件命令"
    else
        log_warn "未找到临时文件命令"
        echo "-- 未找到临时文件命令，请手动添加" >> "$output_file"
    fi
}

# 构建最终的 SQL 脚本（改进版）
build_final_script() {
    local output_file=$1
    local mode=$2
    
    log_info "构建最终的 SQL 脚本..."
    
    # 先提取数据文件
    local datafile_list="/tmp/datafile_list.tmp"
    extract_datafiles_context "/tmp/control_section.tmp" "$datafile_list"
    
    # 写入文件头
    cat > "$output_file" << EOF
-- =================================================================
-- 控制文件重建脚本 ($mode 模式)
-- 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
-- 源文件: $INPUT_FILE
-- 修改内容:
--   - Redo 日志组数量: $NEW_REDO_GROUP_COUNT
--   - Redo 日志路径: $NEW_REDO_PATH
--   - Redo 日志大小: $NEW_REDO_SIZE
EOF

    if [ -n "$NEW_DATA_PATH_PREFIX" ]; then
        echo "--   - 数据文件路径: $DATAFILE_PATTERN -> $NEW_DATA_PATH_PREFIX" >> "$output_file"
    fi
    
    local datafile_count=$(wc -l < "$datafile_list" 2>/dev/null || echo "0")
    echo "--   - 数据文件数量: $datafile_count" >> "$output_file"
    
    cat >> "$output_file" << EOF
-- =================================================================

-- 1. 启动实例到 NOMOUNT 状态
STARTUP NOMOUNT;

-- 2. 创建控制文件
CREATE CONTROLFILE REUSE DATABASE "$DBNAME" $mode ARCHIVELOG
    MAXLOGFILES 16
    MAXLOGMEMBERS 3
    MAXDATAFILES 100
    MAXINSTANCES 8
    MAXLOGHISTORY 292
LOGFILE
EOF

    # 生成 redo 日志
    generate_redo_logs "$output_file" "$NEW_REDO_GROUP_COUNT" "$NEW_REDO_PATH" "$NEW_REDO_SIZE"
    
    # 添加 STANDBY LOGFILE 注释和数据文件头
    echo "-- STANDBY LOGFILE" >> "$output_file"
    echo "DATAFILE" >> "$output_file"
    
    # 处理数据文件部分（改进版）
    if [ -s "$datafile_list" ]; then
        local datafile_formatted="/tmp/datafile_formatted.tmp"
        
        # 判断是否需要替换路径
        if [ -n "$NEW_DATA_PATH_PREFIX" ] && [ -n "$DATAFILE_PATTERN" ]; then
            log_info "应用数据文件路径替换"
            sed "s|^$DATAFILE_PATTERN|$NEW_DATA_PATH_PREFIX|" "$datafile_list" > "$datafile_formatted"
        else
            cp "$datafile_list" "$datafile_formatted"
        fi
        
        # 添加格式：单引号和逗号
        local line_count=0
        local total_lines=$(wc -l < "$datafile_formatted")
        
        while IFS= read -r line; do
            line_count=$((line_count + 1))
            if [ $line_count -eq $total_lines ]; then
                # 最后一行不加逗号
                echo "  '$line'" >> "$output_file"
            else
                echo "  '$line'," >> "$output_file"
            fi
        done < "$datafile_formatted"
        
        log_info "已添加 $total_lines 个数据文件"
        rm -f "$datafile_formatted"
    else
        log_warn "未找到数据文件，请手动添加"
        echo "  -- 未找到数据文件，请手动添加" >> "$output_file"
    fi
    
    # 添加字符集
    echo "CHARACTER SET $CHARSET;" >> "$output_file"
    
    # 添加临时文件
    extract_tempfile_commands "$output_file"
    
    # 写入完成提示
    cat >> "$output_file" << EOF

-- =================================================================
-- 脚本生成完成
-- =================================================================
-- 后续步骤:
-- 1. 确保 redo 日志路径存在: mkdir -p $NEW_REDO_PATH
-- 2. 关闭数据库: SHUTDOWN IMMEDIATE;
-- 3. 执行本脚本: @$output_file
-- 4. 根据需要执行恢复: RECOVER DATABASE USING BACKUP CONTROLFILE;
-- 5. 打开数据库: ALTER DATABASE OPEN RESETLOGS;
-- 6. 验证数据库: SELECT name, open_mode FROM v\$database;
-- =================================================================

PROMPT 控制文件创建完成！
PROMPT 请根据实际情况执行恢复和打开操作
EOF

    log_info "SQL 脚本已生成: $output_file"
}

# 生成验证脚本
generate_validation_script() {
    local validate_script="/home/oracle/validate_paths_$(date +%Y%m%d).sh"
    
    cat > "$validate_script" << EOF
#!/bin/bash
# 路径验证脚本 - 自动生成

echo "========================================="
echo "验证控制文件所需的路径"
echo "========================================="

# 验证 redo 日志路径
REDO_PATH="$NEW_REDO_PATH"
if [ -d "\$REDO_PATH" ]; then
    echo "✓ Redo 路径存在: \$REDO_PATH"
    echo "  权限: \$(ls -ld \$REDO_PATH)"
else
    echo "✗ Redo 路径不存在: \$REDO_PATH"
    echo "  请执行: mkdir -p \$REDO_PATH"
    echo "  请执行: chown oracle:oinstall \$REDO_PATH"
fi

# 验证数据文件路径（如果已修改）
if [ -n "$NEW_DATA_PATH_PREFIX" ]; then
    DATA_PATH="$NEW_DATA_PATH_PREFIX"
    if [ -d "\$DATA_PATH" ]; then
        echo "✓ 数据文件路径存在: \$DATA_PATH"
    else
        echo "✗ 数据文件路径不存在: \$DATA_PATH"
    fi
fi

echo ""
echo "========================================="
echo "当前控制文件配置"
echo "========================================="
echo "Redo 日志组数量: $NEW_REDO_GROUP_COUNT"
echo "Redo 日志大小: $NEW_REDO_SIZE"
echo "Redo 日志文件列表:"
for i in \$(seq 1 $NEW_REDO_GROUP_COUNT); do
    echo "  - $NEW_REDO_PATH/redo\$(printf "%02d" \$i).log"
done
EOF

    chmod +x "$validate_script"
    log_info "验证脚本已生成: $validate_script"
}

# 显示统计信息（改进版）
show_statistics() {
    local datafile_list="/tmp/datafile_list.tmp"
    local datafile_count=$(wc -l < "$datafile_list" 2>/dev/null || echo "0")
    
    echo ""
    echo "========================================="
    echo "处理完成 - 统计信息"
    echo "========================================="
    echo "输入文件: $INPUT_FILE"
    echo "输出文件: $OUTPUT_FILE"
    echo "日志文件: $LOG_FILE"
    echo ""
    echo "数据库配置:"
    echo "  - 数据库名称: $DBNAME"
    echo "  - 字符集: $CHARSET"
    echo "  - 模式: $MODE"
    echo ""
    echo "Redo 配置:"
    echo "  - 日志组数量: $NEW_REDO_GROUP_COUNT"
    echo "  - 日志大小: $NEW_REDO_SIZE"
    echo "  - 日志路径: $NEW_REDO_PATH"
    echo ""
    echo "数据文件:"
    echo "  - 文件数量: $datafile_count"
    if [ -n "$NEW_DATA_PATH_PREFIX" ]; then
        echo "  - 原路径模式: $DATAFILE_PATTERN"
        echo "  - 新路径前缀: $NEW_DATA_PATH_PREFIX"
    else
        echo "  - 保持原始路径"
    fi
    echo ""
    echo "========================================="
    echo "文件列表:"
    echo "  - SQL 脚本: $OUTPUT_FILE"
    echo "  - 验证脚本: /home/oracle/validate_paths_$(date +%Y%m%d).sh"
    echo "  - 日志文件: $LOG_FILE"
    echo "========================================="
}

# 清理临时文件
cleanup_temp_files() {
    rm -f /tmp/control_section.tmp
    rm -f /tmp/control_section_raw.tmp
    rm -f /tmp/datafile_list.tmp
    rm -f /tmp/datafile_section.tmp
    log_info "临时文件已清理"
}

# 主函数
main() {
    echo "开始处理控制文件脚本..."
    echo "========================================="
    
    check_input_file
    detect_dbname
    detect_charset
    detect_original_redo
    extract_controlfile_section "$MODE"
    detect_datafile_pattern
    build_final_script "$OUTPUT_FILE" "$MODE"
    generate_validation_script
    show_statistics
    
    cleanup_temp_files
    
    echo ""
    echo "处理成功完成！"
    echo "请查看输出文件: $OUTPUT_FILE"
}

# 执行主函数
main