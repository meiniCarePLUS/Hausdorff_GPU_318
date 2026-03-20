#!/bin/bash

# ================= Thingi10 GPU 性能测试脚本 =================
# 仅运行 GPU 版本，不做 CPU 对比。
# 数据组织约定：
#   - smooth 模型: ./thingk10/<id>_sf.obj
#   - origin 模型: ./thingk10/<id>.obj

set -u

# ---------------- 配置区域 ----------------
GPU_BIN="./build_gpu/bin/hausdorff"
MODEL_DIR="./thingk10"
LOG_DIR="./logs_gpu_comparison_thingk10"

ERROR_BOUND="0.01"
STOP_CONDITION="rel"
TRAIT_TYPE="point"

MODELS=(
    "36088" "36092" "36372" "37011" "37227" "37402"
    "37416" "37772" "37864" "37962" "38035" "38095"
    "38111" "38290" "38635" "38644" "39012" "39025"
    "39157" "39246" "39353" "39461" "39635" "39677"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}错误: 未找到命令 '$cmd'${NC}"
        exit 1
    fi
}

trim() {
    local s="$1"
    echo "$(echo "$s" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
}

extract_field_value() {
    local logfile="$1"
    local key="$2"
    local escaped_key="${key//\[/\\[}"
    escaped_key="${escaped_key//\]/\\]}"
    grep -m1 "^${escaped_key}" "$logfile" 2>/dev/null | awk '{print $2}'
}

extract_distance_full() {
    local logfile="$1"
    grep -m1 "^\\[distance\\]" "$logfile" 2>/dev/null | awk '{print $2, $3, $4}'
}

extract_max_point() {
    local logfile="$1"
    grep -m1 "^\\[max_point\\]" "$logfile" 2>/dev/null | awk '{print $2, $3, $4}'
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Thingi10 GPU Hausdorff 批量测试${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "测试参数: -e ${ERROR_BOUND} -c ${STOP_CONDITION} -t ${TRAIT_TYPE}"
    echo "模型目录: ${MODEL_DIR}"
    echo "日志目录: ${LOG_DIR}"
    echo ""
}

require_command grep
require_command awk
require_command sed

if [ ! -f "$GPU_BIN" ]; then
    echo -e "${RED}错误: GPU版本可执行文件不存在: $GPU_BIN${NC}"
    echo -e "${YELLOW}提示: 请先编译 GPU 版本: cmake -S . -B build_gpu && cmake --build build_gpu${NC}"
    exit 1
fi

if [ ! -d "$MODEL_DIR" ]; then
    echo -e "${RED}错误: 模型目录不存在: $MODEL_DIR${NC}"
    exit 1
fi

mkdir -p "$LOG_DIR"

print_header

SUMMARY_FILE="${LOG_DIR}/summary.csv"
{
    echo "Model,GPU_Time_ms,Distance,Mean_Distance,Status"
} > "$SUMMARY_FILE"

run_gpu_only() {
    local name="$1"
    local smooth="${MODEL_DIR}/${name}_sf.obj"
    local origin="${MODEL_DIR}/${name}.obj"
    local gpu_log="${LOG_DIR}/${name}_gpu.log"

    if [[ ! -f "$smooth" || ! -f "$origin" ]]; then
        echo -e "${YELLOW}[跳过] 模型文件缺失: $name${NC}"
        echo "  smooth: $smooth"
        echo "  origin: $origin"
        echo "$name,,,,MISSING_MODEL" >> "$SUMMARY_FILE"
        echo ""
        return
    fi

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}测试模型: $name${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}[1/1] 运行 GPU 版本...${NC}"

    "$GPU_BIN" \
        -a "$smooth" \
        -b "$origin" \
        -e "$ERROR_BOUND" \
        -c "$STOP_CONDITION" \
        -t "$TRAIT_TYPE" \
        > "$gpu_log" 2>&1

    local gpu_exit_code=$?
    if [ $gpu_exit_code -ne 0 ]; then
        echo -e "${RED}错误: GPU 程序执行失败，退出码: $gpu_exit_code${NC}"
        echo -e "${YELLOW}请检查日志: $gpu_log${NC}"
        echo "$name,,,,GPU_RUN_FAIL" >> "$SUMMARY_FILE"
        echo ""
        return
    fi

    local gpu_time
    local gpu_distance
    local gpu_mean
    local gpu_max_point
    gpu_time="$(trim "$(extract_field_value "$gpu_log" "[total_cost]")")"
    gpu_distance="$(trim "$(extract_distance_full "$gpu_log")")"
    gpu_mean="$(trim "$(extract_field_value "$gpu_log" "[mean_distance]")")"
    gpu_max_point="$(trim "$(extract_max_point "$gpu_log")")"

    if [ -z "$gpu_time" ]; then
        echo -e "${RED}错误: 无法从 GPU 日志提取 [total_cost]${NC}"
        echo -e "${YELLOW}请检查日志: $gpu_log${NC}"
        echo "$name,,,,GPU_PARSE_FAIL" >> "$SUMMARY_FILE"
        echo ""
        return
    fi

    echo "  耗时:     ${gpu_time} ms"
    echo "  距离:     ${gpu_distance:-N/A}"
    echo "  最大点:   ${gpu_max_point:-N/A}"
    echo "  平均距离: ${gpu_mean:-N/A}"
    echo ""

    echo "$name,${gpu_time:-},\"${gpu_distance:-}\",${gpu_mean:-},OK" >> "$SUMMARY_FILE"
}

for model in "${MODELS[@]}"; do
    run_gpu_only "$model"
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  测试汇总${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

if command -v column >/dev/null 2>&1; then
    column -t -s',' "$SUMMARY_FILE"
else
    cat "$SUMMARY_FILE"
fi

echo ""
echo -e "${GREEN}详细日志保存在: $LOG_DIR${NC}"
echo -e "${GREEN}汇总文件: $SUMMARY_FILE${NC}"
