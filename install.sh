#!/usr/bin/env bash

# install.sh - 可在线通过 curl | bash 运行的安装脚本
# 支持本地 tool/ 目录或从 GitHub 仓库远程下载 tool/*.sh 并安装到 /usr/local/bin
# 兼容大多数 Linux 发行版，交互输入从 /dev/tty 读取（适用于管道执行时交互）

set -euo pipefail

# 配置仓库信息（如将来需要修改分支或仓库，可在这里改）
REPO_OWNER="Xiaoxinyun2008"
REPO_NAME="linux-tool"
BRANCH="main"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 脚本目录（当脚本以文件运行时有效）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null || pwd) || true"
TOOL_DIR="$SCRIPT_DIR/tool"
INSTALL_DIR="/usr/local/bin"

# 远程 urls
GITHUB_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents/tool?ref=${BRANCH}"
GITHUB_RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/tool"

USE_REMOTE=0

# 分页设置
PAGE_SIZE=10
CURRENT_PAGE=1
SELECTED_ITEMS=()

# 临时数组（远程模式时填充）
REMOTE_FILES=()
REMOTE_DOWNLOAD_URLS=()

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查是否有 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        echo "请使用: sudo bash -c 'curl -sSL <URL> | tr -d \"\\r\" | bash -s --'"
        exit 1
    fi
}

# 检查本地 tool 目录是否存在，不存在则启用远程模式
check_tool_dir_or_remote() {
    if [ -d "$TOOL_DIR" ]; then
        USE_REMOTE=0
        return 0
    fi

    # 如果当前目录下没有 tool，则使用远程模式
    print_info "未发现本地 tool/ 目录，尝试使用 GitHub 仓库的远程文件列表..."
    USE_REMOTE=1
    fetch_remote_file_list || {
        print_error "无法从 GitHub 获取 tool 列表，请检查网络或仓库设置。"
        exit 1
    }
}

# 从 GitHub API 获取 tool 目录下的 .sh 文件名与 download_url
fetch_remote_file_list() {
    local json
    json="$(curl -fsSL "$GITHUB_API")" || return 1

    # 解析 name 与 download_url（用 awk 分析 JSON 行，避免依赖 jq）
    # 每个条目会产生一对 "name" 行 与 "download_url" 行，使用 awk 关联输出
    # 格式： name download_url
    local list
    list="$(echo "$json" | awk -F'"' '/"name":/ {n=$4} /"download_url":/ {print n" "$4}')"

    REMOTE_FILES=()
    REMOTE_DOWNLOAD_URLS=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        name="${line%% *}"
        url="${line#* }"
        case "$name" in
            *.sh)
                REMOTE_FILES+=("$name")
                REMOTE_DOWNLOAD_URLS+=("$url")
                ;;
        esac
    done <<< "$list"

    if [ ${#REMOTE_FILES[@]} -eq 0 ]; then
        return 1
    fi
    return 0
}

# 获取所有 .sh 文件名（本地或远程）
get_sh_files() {
    if [ "$USE_REMOTE" -eq 0 ]; then
        local files=()
        while IFS= read -r -d '' file; do
            files+=("$(basename "$file")")
        done < <(find "$TOOL_DIR" -maxdepth 1 -type f -name "*.sh" -print0 | sort -z)
        echo "${files[@]}"
    else
        echo "${REMOTE_FILES[@]}"
    fi
}

# 获取脚本的描述（会读取文件头 20 行）
get_description() {
    local file_path="$1"
    local description=""
    local content

    if [ "$USE_REMOTE" -eq 0 ]; then
        if [ ! -f "$TOOL_DIR/$file_path" ]; then
            echo "暂无描述"
            return
        fi
        content="$(head -n 20 "$TOOL_DIR/$file_path")"
    else
        # 找到下载 url
        local idx
        for i in "${!REMOTE_FILES[@]}"; do
            if [ "${REMOTE_FILES[$i]}" = "$file_path" ]; then
                idx=$i
                break
            fi
        done
        if [ -z "${idx:-}" ]; then
            echo "暂无描述"
            return
        fi
        content="$(curl -fsSL "${REMOTE_DOWNLOAD_URLS[$idx]}" 2>/dev/null || true)"
        content="$(printf "%s\n" "$content" | head -n 20)"
    fi

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
    done <<< "$content"

    if [ -z "$description" ]; then
        description="暂无描述"
    fi
    echo "$description"
}

# 检查命令冲突（同原逻辑）
check_command_conflict() {
    local tool_name="$1"
    local conflicts=()

    if [ -f "$INSTALL_DIR/$tool_name" ]; then
        if [ "$USE_REMOTE" -eq 0 ]; then
            if ! cmp -s "$TOOL_DIR/${tool_name}.sh" "$INSTALL_DIR/$tool_name" 2>/dev/null; then
                conflicts+=("$INSTALL_DIR/$tool_name (已存在不同版本)")
            fi
        else
            conflicts+=("$INSTALL_DIR/$tool_name (已存在，不使用本仓库文件比较)")
        fi
    fi

    local cmd_path
    cmd_path="$(command -v "$tool_name" 2>/dev/null || true)"
    if [ -n "$cmd_path" ] && [ "$cmd_path" != "$INSTALL_DIR/$tool_name" ]; then
        conflicts+=("$cmd_path")
    fi

    echo "${conflicts[@]}"
}

# 处理冲突交互（从 /dev/tty 读取）
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
    read -r -p "请选择 [1-3]: " conflict_choice </dev/tty

    case $conflict_choice in
        1)
            return 0
            ;;
        2)
            read -r -p "请输入新的命令名称 (默认: ${tool_name}-custom): " new_name </dev/tty
            new_name=${new_name:-"${tool_name}-custom"}
            printf '%s' "$new_name"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# 显示 ASCII Logo
show_logo() {
    echo -e "${CYAN}"
    cat << "EOF"
 _     _                    _____           _ 
| |   (_)_ __  _   ___  __ |_   _|__   ___ | |
| |   | | '_ \| | | \ \/ /   | |/ _ \ / _ \| |
| |___| | | | | |_| |>  <    | | (_) | (_) | |
|_____|_|_| |_|\__,_/_/\_\   |_|\___/ \___/|_|
                                              

EOF
    echo -e "${NC}"
    echo -e "${BOLD}    强大的 Linux 工具集合管理器${NC}"
    echo -e "    作者: ${MAGENTA}零意${NC}"
    echo ""
}

show_welcome() {
    clear
    show_logo
}

get_total_pages() {
    local total_items=$1
    echo $(( (total_items + PAGE_SIZE - 1) / PAGE_SIZE ))
}

get_page_items() {
    local files=("$@")
    local start=$(( (CURRENT_PAGE - 1) * PAGE_SIZE ))
    echo "${files[@]:$start:$PAGE_SIZE}"
}

show_paged_menu() {
    local files=("$@")
    local total=${#files[@]}
    local total_pages
    total_pages=$(get_total_pages $total)

    if [ $total -eq 0 ]; then
        print_warning "tool 目录中没有找到 .sh 文件"
        exit 0
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}可用工具列表${NC} (第 ${CURRENT_PAGE}/${total_pages} 页, 共 ${total} 个工具)"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    local max_name_len=0
    for file in "${files[@]}"; do
        local name="${file%.sh}"
        local name_len=${#name}
        if [ $name_len -gt $max_name_len ]; then
            max_name_len=$name_len
        fi
    done

    local page_items=($(get_page_items "${files[@]}"))
    local start_num=$(( (CURRENT_PAGE - 1) * PAGE_SIZE + 1 ))

    for i in "${!page_items[@]}"; do
        local num=$((start_num + i))
        local filename="${page_items[$i]}"
        local name="${filename%.sh}"
        local desc
        desc=$(get_description "$filename")

        local padding=$((max_name_len - ${#name} + 2))
        local spaces
        spaces=$(printf '%*s' "$padding" '')

        local is_selected=false
        for selected in "${SELECTED_ITEMS[@]}"; do
            if [ "$selected" = "$filename" ]; then
                is_selected=true
                break
            fi
        done

        local status=""
        if [ -f "$INSTALL_DIR/$name" ]; then
            status="${GREEN}[已安装]${NC}"
        fi

        if $is_selected; then
            echo -e "  ${MAGENTA}[✓]${NC} $num) $name$spaces$status - $desc"
        else
            echo -e "  [ ] $num) $name$spaces$status - $desc"
        fi
    done

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    if [ ${#SELECTED_ITEMS[@]} -gt 0 ]; then
        echo -e "${MAGENTA}已选中: ${#SELECTED_ITEMS[@]} 个工具${NC}"
        echo ""
    fi

    echo "操作指令:"
    echo "  [数字]     选择/取消选择工具    [Enter]    安装已选中的工具"
    echo "  [n/→]      下一页              [p/←]      上一页"
    echo "  [a]        全选当前页          [A]        全选所有"
    echo "  [c]        清空选择            [u]        卸载工具"
    echo "  [i]        联系作者            [q]        退出"
    echo ""
}

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

# 安装单个工具 - 本地或远程都会处理
install_tool() {
    local sh_file="$1"
    local custom_name="$2"
    local tool_name="${custom_name:-${sh_file%.sh}}"
    local dest_path="$INSTALL_DIR/$tool_name"

    if [ "$USE_REMOTE" -eq 0 ]; then
        local source_path="$TOOL_DIR/$sh_file"
        if [ ! -f "$source_path" ]; then
            print_error "文件不存在: $source_path"
            return 1
        fi
        if [ ! -d "$INSTALL_DIR" ]; then
            mkdir -p "$INSTALL_DIR" || { print_error "无法创建安装目录: $INSTALL_DIR"; return 1; }
        fi
        cp "$source_path" "$dest_path" || { print_error "复制失败: $source_path -> $dest_path"; return 1; }
    else
        # 远程下载对应文件
        local idx=""
        for i in "${!REMOTE_FILES[@]}"; do
            if [ "${REMOTE_FILES[$i]}" = "$sh_file" ]; then
                idx=$i
                break
            fi
        done
        if [ -z "${idx}" ]; then
            print_error "未找到远程文件: $sh_file"
            return 1
        fi
        local url="${REMOTE_DOWNLOAD_URLS[$idx]}"
        if [ ! -d "$INSTALL_DIR" ]; then
            mkdir -p "$INSTALL_DIR" || { print_error "无法创建安装目录: $INSTALL_DIR"; return 1; }
        fi
        curl -fsSL "$url" -o "$dest_path" || { print_error "下载失败: $url"; return 1; }
    fi

    chmod +x "$dest_path" || { print_error "无法设置可执行权限: $dest_path"; return 1; }
    print_success "已安装: $tool_name -> $dest_path"
    return 0
}

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
        local conflicts
        conflicts="$(check_command_conflict "$name")"
        local install_name="$name"

        if [ -n "$conflicts" ]; then
            result="$(handle_conflict "$name" "$conflicts")" || {
                print_warning "跳过: $name"
                ((skip_count++))
                continue
            }
            # handle_conflict may have printed a new name
            if [ -n "$result" ]; then
                install_name="$result"
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

    SELECTED_ITEMS=()
}

show_contact() {
    clear
    show_logo
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}联系作者${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${BOLD}👤 作者:${NC} ${MAGENTA}零意${NC}"
    echo ""
    echo -e "  ${BOLD}💬 联系QQ:2101497063${NC}"
    echo -e "     QQ: ${BLUE}https://qm.qq.com/q/LgAL9PiIY8${NC}"
    echo ""
    echo -e "  ${BOLD}👥 加入Q群:829665083${NC}"
    echo -e "     群: ${BLUE}https://qm.qq.com/q/25rfBURNe8${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  ${YELLOW}提示: 你可以复制上面的链接在浏览器中打开${NC}"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    read -r -p "按 Enter 返回主菜单..." </dev/tty
}

uninstall_menu() {
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
        read -r -p "按 Enter 继续..." </dev/tty
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
    read -r -p "请输入编号或选项: " uninstall_choice </dev/tty

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
    read -r -p "按 Enter 继续..." </dev/tty
}

main() {
    # 等待用户（或非交互）时提示 root 权限
    check_root
    check_tool_dir_or_remote

    local sh_files=($(get_sh_files))
    local total=${#sh_files[@]}

    while true; do
        show_welcome
        show_paged_menu "${sh_files[@]}"

        # 从 /dev/tty 读取按键（支持管道执行时交互）
        read -n 1 -s key </dev/tty || key=""
        echo ""

        case $key in
            q|Q)
                print_info "退出安装程序"
                exit 0
                ;;
            n|N|$'\e')
                # 方向键或 n
                read -n 2 -s -t 0.1 arrow </dev/tty || arrow=""
                if [ "$arrow" = "[C" ] || [ "$key" = "n" ] || [ "$key" = "N" ]; then
                    local total_pages
                    total_pages=$(get_total_pages $total)
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
                SELECTED_ITEMS=("${sh_files[@]}")
                ;;
            c|C)
                SELECTED_ITEMS=()
                ;;
            u|U)
                uninstall_menu "${sh_files[@]}"
                ;;
            i|I)
                show_contact
                ;;
            "")
                if [ ${#SELECTED_ITEMS[@]} -gt 0 ]; then
                    install_selected
                    read -r -p "按 Enter 继续..." </dev/tty
                fi
                ;;
            [0-9])
                # 数字选择（允许多位）
                read -t 0.5 rest </dev/tty || rest=""
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

main

