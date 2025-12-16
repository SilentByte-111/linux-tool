#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$SCRIPT_DIR/tool"
INSTALL_DIR="/usr/local/bin"

# 分页设置
PAGE_SIZE=10
CURRENT_PAGE=1
SELECTED_ITEMS=()

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否有root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 检查tool目录是否存在
check_tool_dir() {
    if [ ! -d "$TOOL_DIR" ]; then
        print_error "找不到 tool 目录: $TOOL_DIR"
        exit 1
    fi
}

# 获取所有.sh文件
get_sh_files() {
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$(basename "$file")")
    done < <(find "$TOOL_DIR" -maxdepth 1 -type f -name "*.sh" -print0 | sort -z)
    echo "${files[@]}"
}

# 获取脚本描述信息
get_description() {
    local file_path="$1"
    local description=""
    
    while IFS= read -r line; do
        if [[ $line =~ ^#[[:space:]]*[Dd]escription:[[:space:]]*(.+)$ ]]; then
            description="${BASH_REMATCH[1]}"
            break
        fi
        if [[ $line =~ ^#[[:space:]]*DESC:[[:space:]]*(.+)$ ]]; then
            description="${BASH_REMATCH[1]}"
            break
        fi
        if [[ $line =~ ^#[[:space:]]*功能:[[:space:]]*(.+)$ ]]; then
            description="${BASH_REMATCH[1]}"
            break
        fi
        if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# && ! "$line" =~ ^[[:space:]]*$ ]]; then
            break
        fi
    done < <(head -n 20 "$file_path")
    
    if [ -z "$description" ]; then
        description="暂无描述"
    fi
    
    echo "$description"
}

# 检查命令冲突
check_command_conflict() {
    local tool_name="$1"
    local conflicts=()
    
    # 检查是否已在 /usr/local/bin 中存在
    if [ -f "$INSTALL_DIR/$tool_name" ]; then
        # 检查是否是我们安装的（通过比较文件内容）
        if ! cmp -s "$TOOL_DIR/${tool_name}.sh" "$INSTALL_DIR/$tool_name" 2>/dev/null; then
            conflicts+=("$INSTALL_DIR/$tool_name (已存在不同版本)")
        fi
    fi
    
    # 检查系统其他路径
    local cmd_path=$(command -v "$tool_name" 2>/dev/null)
    if [ -n "$cmd_path" ] && [ "$cmd_path" != "$INSTALL_DIR/$tool_name" ]; then
        conflicts+=("$cmd_path")
    fi
    
    echo "${conflicts[@]}"
}

# 显示冲突警告并询问
handle_conflict() {
    local tool_name="$1"
    local conflicts="$2"
    
    print_warning "检测到命令冲突: $tool_name"
    echo "现有命令位置: $conflicts"
    echo ""
    echo "  1) 覆盖安装 (替换现有命令)"
    echo "  2) 使用别名安装 (例如: ${tool_name}-custom)"
    echo "  3) 跳过此工具"
    echo ""
    read -p "请选择 [1-3]: " conflict_choice
    
    case $conflict_choice in
        1)
            return 0  # 继续安装
            ;;
        2)
            read -p "请输入新的命令名称 (默认: ${tool_name}-custom): " new_name
            new_name=${new_name:-"${tool_name}-custom"}
            echo "$new_name"
            return 0
            ;;
        *)
            return 1  # 跳过
            ;;
    esac
}

# 显示ASCII Logo
show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
    ╦  ┬┌┐┌┬ ┬─┐ ┬  ╔╦╗┌─┐┌─┐┬  
    ║  │││││ │┌┴┬┘   ║ │ ││ ││  
    ╩═╝┴┘└┘└─┘┴ └─   ╩ └─┘└─┘┴─┘
EOF
    echo -e "${NC}"
    echo -e "${BOLD}    强大的 Linux 工具集合管理器${NC}"
    echo -e "    作者: ${MAGENTA}零意${NC}"
    echo ""
}

# 显示欢迎信息
show_welcome() {
    clear
    show_logo
}

# 计算总页数
get_total_pages() {
    local total_items=$1
    echo $(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
}

# 获取当前页的项目
get_page_items() {
    local files=("$@")
    local start=$(( (CURRENT_PAGE - 1) * PAGE_SIZE ))
    local end=$(( start + PAGE_SIZE ))
    
    echo "${files[@]:$start:$PAGE_SIZE}"
}

# 显示分页菜单
show_paged_menu() {
    local files=("$@")
    local total=${#files[@]}
    local total_pages=$(get_total_pages $total)
    
    if [ $total -eq 0 ]; then
        print_warning "tool 目录中没有找到 .sh 文件"
        exit 0
    fi
    
    # 显示页面信息
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}可用工具列表${NC} (第 ${CURRENT_PAGE}/${total_pages} 页, 共 ${total} 个工具)"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 计算最长的工具名长度
    local max_name_len=0
    for file in "${files[@]}"; do
        local name="${file%.sh}"
        local name_len=${#name}
        if [ $name_len -gt $max_name_len ]; then
            max_name_len=$name_len
        fi
    done
    
    # 显示当前页的项目
    local page_items=($(get_page_items "${files[@]}"))
    local start_num=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))
    
    for i in "${!page_items[@]}"; do
        local num=$((start_num + i))
        local filename="${page_items[$i]}"
        local name="${filename%.sh}"
        local desc=$(get_description "$TOOL_DIR/$filename")
        
        local padding=$((max_name_len - ${#name} + 2))
        local spaces=$(printf '%*s' "$padding" '')
        
        # 检查是否已选中
        local is_selected=false
        for selected in "${SELECTED_ITEMS[@]}"; do
            if [ "$selected" = "$filename" ]; then
                is_selected=true
                break
            fi
        done
        
        # 检查是否已安装
        local status=""
        if [ -f "$INSTALL_DIR/$name" ]; then
            status="${GREEN}[已安装]${NC}"
        fi
        
        # 显示选中标记
        if $is_selected; then
            echo -e "  ${MAGENTA}[✓]${NC} $num) $name$spaces$status - $desc"
        else
            echo -e "  [ ] $num) $name$spaces$status - $desc"
        fi
    done
    
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 显示已选中的工具数量
    if [ ${#SELECTED_ITEMS[@]} -gt 0 ]; then
        echo -e "${MAGENTA}已选中: ${#SELECTED_ITEMS[@]} 个工具${NC}"
        echo ""
    fi
    
    # 显示操作提示
    echo "操作指令:"
    echo "  [数字]     选择/取消选择工具    [Enter]    安装已选中的工具"
    echo "  [n/→]      下一页              [p/←]      上一页"
    echo "  [a]        全选当前页          [A]        全选所有"
    echo "  [c]        清空选择            [u]        卸载工具"
    echo "  [i]        联系作者            [q]        退出"
    echo ""
}

# 切换选择状态
toggle_selection() {
    local item="$1"
    local found=false
    local new_selected=()
    
    for selected in "${SELECTED_ITEMS[@]}"; do
        if [ "$selected" = "$item" ]; then
            found=true
        else
            new_selected+=("$selected")
        fi
    done
    
    if ! $found; then
        new_selected+=("$item")
    fi
    
    SELECTED_ITEMS=("${new_selected[@]}")
}

# 安装单个工具
install_tool() {
    local sh_file="$1"
    local custom_name="$2"
    local tool_name="${custom_name:-${sh_file%.sh}}"
    local source_path="$TOOL_DIR/$sh_file"
    local dest_path="$INSTALL_DIR/$tool_name"
    
    if [ ! -f "$source_path" ]; then
        print_error "文件不存在: $source_path"
        return 1
    fi
    
    # 复制文件
    cp "$source_path" "$dest_path"
    chmod +x "$dest_path"
    
    print_success "已安装: $tool_name -> $dest_path"
    return 0
}

# 安装选中的工具
install_selected() {
    if [ ${#SELECTED_ITEMS[@]} -eq 0 ]; then
        print_warning "没有选中任何工具"
        return
    fi
    
    echo ""
    print_info "准备安装 ${#SELECTED_ITEMS[@]} 个工具..."
    echo ""
    
    local success_count=0
    local skip_count=0
    local fail_count=0
    
    for file in "${SELECTED_ITEMS[@]}"; do
        local name="${file%.sh}"
        
        # 检查命令冲突
        local conflicts=$(check_command_conflict "$name")
        local install_name="$name"
        
        if [ -n "$conflicts" ]; then
            result=$(handle_conflict "$name" "$conflicts")
            if [ $? -eq 0 ]; then
                if [ "$result" != "0" ]; then
                    install_name="$result"
                fi
            else
                print_warning "跳过: $name"
                ((skip_count++))
                continue
            fi
        fi
        
        if install_tool "$file" "$install_name"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
    done
    
    echo ""
    echo -e "${BOLD}安装完成!${NC}"
    echo "  成功: ${GREEN}$success_count${NC}"
    echo "  跳过: ${YELLOW}$skip_count${NC}"
    echo "  失败: ${RED}$fail_count${NC}"
    
    # 清空选择
    SELECTED_ITEMS=()
}

# 显示联系信息
show_contact() {
    clear
    show_logo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}联系作者${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}👤 作者:${NC} ${MAGENTA}零意${NC}"
    echo ""
    echo -e "  ${BOLD}💬 联系方式:${NC}"
    echo -e "     QQ: ${BLUE}https://qm.qq.com/q/LgAL9PiIY8${NC}"
    echo ""
    echo -e "  ${BOLD}👥 加入群聊:${NC}"
    echo -e "     群: ${BLUE}https://qm.qq.com/q/25rfBURNe8${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  ${YELLOW}提示: 你可以复制上面的链接在浏览器中打开${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    read -p "按 Enter 返回主菜单..."
}
    local files=("$@")
    local installed=()
    
    for file in "${files[@]}"; do
        local name="${file%.sh}"
        if [ -f "$INSTALL_DIR/$name" ]; then
            installed+=("$name")
        fi
    done
    
    if [ ${#installed[@]} -eq 0 ]; then
        print_warning "没有已安装的工具"
        read -p "按 Enter 继续..."
        return
    fi
    
    clear
    echo -e "${BOLD}======================================"
    echo "   卸载工具"
    echo -e "======================================${NC}"
    echo ""
    echo "已安装的工具:"
    echo ""
    
    for i in "${!installed[@]}"; do
        echo "  $((i + 1))) ${installed[$i]}"
    done
    
    echo ""
    echo "  [a] 卸载全部    [b] 返回"
    echo ""
    read -p "请输入编号或选项: " uninstall_choice
    
    case $uninstall_choice in
        [aA])
            for name in "${installed[@]}"; do
                rm -f "$INSTALL_DIR/$name"
                print_success "已卸载: $name"
            done
            ;;
        [bB])
            return
            ;;
        *)
            if [[ "$uninstall_choice" =~ ^[0-9]+$ ]] && [ "$uninstall_choice" -ge 1 ] && [ "$uninstall_choice" -le ${#installed[@]} ]; then
                local name="${installed[$((uninstall_choice - 1))]}"
                rm -f "$INSTALL_DIR/$name"
                print_success "已卸载: $name"
            else
                print_error "无效的选择"
            fi
            ;;
    esac
    
    echo ""
    read -p "按 Enter 继续..."
}

# 主函数
main() {
    check_root
    check_tool_dir
    
    local sh_files=($(get_sh_files))
    local total=${#sh_files[@]}
    
    while true; do
        show_welcome
        show_paged_menu "${sh_files[@]}"
        
        read -n 1 -s key
        echo ""
        
        case $key in
            q|Q)
                print_info "退出安装程序"
                exit 0
                ;;
            n|N|$'\e')
                # 检查是否是方向键
                read -n 2 -s -t 0.1 arrow
                if [ "$arrow" = "[C" ] || [ "$key" = "n" ] || [ "$key" = "N" ]; then
                    local total_pages=$(get_total_pages $total)
                    if [ $CURRENT_PAGE -lt $total_pages ]; then
                        ((CURRENT_PAGE++))
                    fi
                elif [ "$arrow" = "[D" ]; then
                    if [ $CURRENT_PAGE -gt 1 ]; then
                        ((CURRENT_PAGE--))
                    fi
                fi
                ;;
            p|P)
                if [ $CURRENT_PAGE -gt 1 ]; then
                    ((CURRENT_PAGE--))
                fi
                ;;
            a)
                # 全选当前页
                local page_items=($(get_page_items "${sh_files[@]}"))
                for item in "${page_items[@]}"; do
                    local found=false
                    for selected in "${SELECTED_ITEMS[@]}"; do
                        if [ "$selected" = "$item" ]; then
                            found=true
                            break
                        fi
                    done
                    if ! $found; then
                        SELECTED_ITEMS+=("$item")
                    fi
                done
                ;;
            A)
                # 全选所有
                SELECTED_ITEMS=("${sh_files[@]}")
                ;;
            c|C)
                # 清空选择
                SELECTED_ITEMS=()
                ;;
            u|U)
                uninstall_menu "${sh_files[@]}"
                ;;
            i|I)
                show_contact
                ;;
            "")
                # Enter 键 - 安装选中的工具
                if [ ${#SELECTED_ITEMS[@]} -gt 0 ]; then
                    install_selected
                    read -p "按 Enter 继续..."
                fi
                ;;
            [0-9])
                # 数字选择
                read -t 0.5 rest
                local num="${key}${rest}"
                local start_num=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))
                local end_num=$(( start_num + PAGE_SIZE - 1 ))
                
                if [ "$num" -ge "$start_num" ] && [ "$num" -le "$end_num" ] && [ "$num" -le "$total" ]; then
                    local idx=$((num - 1))
                    toggle_selection "${sh_files[$idx]}"
                else
                    print_error "无效的编号"
                    sleep 1
                fi
                ;;
        esac
    done
}

# 运行主函数
main
