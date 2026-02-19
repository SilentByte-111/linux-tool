#!/usr/bin/env bash

# install.sh - 可在线通过 curl | bash 运行的安装脚本
# 支持本地 tool/ 目录或从 GitHub 仓库远程下载 tool/*.sh 并安装到 /usr/local/bin
# 兼容大多数 Linux 发行版，交互输入从 /dev/tty 读取（适用于管道执行时交互）

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi
set -euo pipefail

# 配置仓库信息（如将来需要修改分支或仓库，可在这里改）
REPO_OWNER="SilentByte-111"
REPO_NAME="linux-tool"
BRANCH="main"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color
BOLD='\033[1m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'

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

# 版本控制
version=v1.2 

# 打印带颜色的消息
print_info() {
    echo -e "  ${CYAN}ℹ️  [INFO]${NC} $1"
}
print_success() {
    echo -e "  ${GREEN}✅ [SUCCESS]${NC} $1"
}
print_error() {
    echo -e "  ${RED}❌ [ERROR]${NC} $1" >&2
}
print_warning() {
    echo -e "  ${YELLOW}⚠️  [WARNING]${NC} $1"
}

# 检查是否有 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "此脚本需要 root 权限运行"
        echo -e "  ${YELLOW}💡 提示:${NC} 请使用: ${BOLD}sudo bash -c 'curl -sSL <URL> | tr -d \"\\r\" | bash -s --'${NC}"
        exit 1
    fi
}

# 自动检测并启动远程模式（直接启用远程模式，不检测本地目录）
check_tool_dir_or_remote() {
    # 直接启用远程模式
    print_info "正在使用 GitHub 仓库的远程文件列表..."
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
    echo -e "  ${RED}⚠️  当前命令位置:${NC} $conflicts"
    echo ""
    echo -e "  ${CYAN}┌─ 选择处理方式 ─────────────────────────────────────┐${NC}"
    echo -e "  ${CYAN}│${NC} ${GREEN}1)${NC} 覆盖安装 (替换现有命令)                     ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC} ${GREEN}2)${NC} 使用别名安装 (例如: ${tool_name}-custom)      ${CYAN}│${NC}"
    echo -e "  ${CYAN}│${NC} ${GREEN}3)${NC} 跳过此工具                                   ${CYAN}│${NC}"
    echo -e "  ${CYAN}└──────────────────────────────────────────────────┘${NC}"
    echo ""
    read -r -p "  ${YELLOW}👉 请选择 [1-3]: ${NC}" conflict_choice </dev/tty

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
    echo -e "   ${BOLD}${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "   ${BOLD}${CYAN}║${NC}    ${BOLD}强大的 Linux 工具集合管理器${NC}       ${BOLD}${CYAN}║${NC}"
    echo -e "   ${BOLD}${CYAN}║${NC}         ${MAGENTA}/by Silent Byte${NC}                   ${BOLD}${CYAN}║${NC}"
    echo -e "                                             QQ:1950930166/2101497063"
    echo -e "   ${BOLD}${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""
}

show_welcome() {
    clear
    show_logo
    echo -e "  ${BOLD}${CYAN}┌─ 欢迎使用 Linux 工具集合管理器 ──────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}${CYAN}│${NC}     ${GREEN}✨ 一键管理您的 Linux 工具集 ✨${NC} |  $version                ${BOLD}${CYAN}│${NC}"
    echo -e "  ${BOLD}${CYAN}└─ 欢迎使用 Linux 工具集合管理器 ──────────────────────────────────────────┘${NC}"
    echo ""
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

    echo -e "${BOLD}${CYAN}┌─ 可用工具列表 ──────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}工具列表${NC} (第 ${CURRENT_PAGE}/${total_pages} 页, 共 ${total} 个工具)"
    echo -e "${BOLD}${CYAN}└─ 可用工具列表 ──────────────────────────────────────────────────────────┘${NC}"
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
            echo -e "  ${MAGENTA}●${NC} $num) ${BOLD}$name${NC}$spaces$status - $desc"
        else
            echo -e "  ○ $num) $name$spaces$status - $desc"
        fi
    done

    echo ""
    echo -e "${BOLD}${CYAN}┌─ 操作指令 ──────────────────────────────────────────────────────────────┐${NC}"
    if [ ${#SELECTED_ITEMS[@]} -gt 0 ]; then
        echo -e "  ${MAGENTA}已选中: ${BOLD}${#SELECTED_ITEMS[@]}${NC} 个工具${NC}"
        echo -e "${BOLD}${CYAN}├───────────────────────────────────────────────────────────────────────┤${NC}"
    fi

    echo -e "  ${GREEN}[数字]${NC}       选择/取消选择工具    ${GREEN}[Enter]${NC}    安装已选中的工具"
    echo -e "  ${GREEN}[n/→]${NC}        下一页              ${GREEN}[p/←]${NC}      上一页"
    echo -e "  ${GREEN}[a]${NC}          全选当前页          ${GREEN}[A]${NC}        全选所有"
    echo -e "  ${GREEN}[c]${NC}          清空选择            ${GREEN}[u]${NC}        卸载工具"
    echo -e "  ${GREEN}[i]${NC}          联系作者            ${GREEN}[q]${NC}        退出"
    echo -e "${BOLD}${CYAN}└─ 操作指令 ──────────────────────────────────────────────────────────────┘${NC}"
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

    echo -e "${BOLD}${CYAN}┌─ 开始安装 ──────────────────────────────────────────────────────────────┐${NC}"
    print_info "准备安装 ${#SELECTED_ITEMS[@]} 个工具..."
    echo -e "${BOLD}${CYAN}└─ 开始安装 ──────────────────────────────────────────────────────────────┘${NC}"
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
    echo -e "${BOLD}${GREEN}┌─ 安装完成 ──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}状态统计:${NC}"
    echo -e "    ${GREEN}✅ 成功: $success_count${NC}"
    echo -e "    ${YELLOW}⚠️  跳过: $skip_count${NC}"
    echo -e "    ${RED}❌ 失败: $fail_count${NC}"
    echo -e "${BOLD}${GREEN}└─ 安装完成 ──────────────────────────────────────────────────────────────┘${NC}"

    SELECTED_ITEMS=()
}

# 打开链接函数（尝试在终端或浏览器中打开链接）
open_link() {
    local url="$1"
    local name="$2"

    if command -v xdg-open >/dev/null 2>&1; then
        echo -e "  ${GREEN}正在尝试使用默认浏览器打开 $name...${NC}"
        xdg-open "$url" 2>/dev/null &
        sleep 1
    elif command -v open >/dev/null 2>&1; then
        echo -e "  ${GREEN}正在尝试使用默认浏览器打开 $name...${NC}"
        open "$url" 2>/dev/null &
        sleep 1
    elif command -v curl >/dev/null 2>&1; then
        echo -e "  ${YELLOW}请复制以下链接在浏览器中打开: ${NC}${BLUE}$url${NC}"
    else
        echo -e "  ${YELLOW}请复制以下链接在浏览器中打开: ${NC}${BLUE}$url${NC}"
    fi
}

show_contact() {
    clear
    show_logo
    while true; do
        echo -e "${BOLD}${CYAN}┌─ 联系作者 ──────────────────────────────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}联系方式${NC}"
        echo -e "${BOLD}${CYAN}└─ 联系作者 ──────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BOLD}${GREEN}┌─ 个人联系 ─────────────────────────────────────────┐${NC}"
        echo -e "  ${BOLD}👤 作者:${NC} ${MAGENTA}零意${NC}"
        echo -e "  ${GREEN}1)${NC} 💬 联系QQ: 2101497063"
        #echo -e "     🔗 https://qm.qq.com/q/LgAL9PiIY8"
        echo -e "  ${BOLD}${GREEN}└─────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BOLD}${PURPLE}┌─ 社区交流 ─────────────────────────────────────────┐${NC}"
        echo -e "  ${GREEN}2)${NC} 👥 加入Q群: 829665083"
        #echo -e "     🔗 https://qm.qq.com/q/25rfBURNe8"
        echo -e "  ${BOLD}${PURPLE}└─────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BOLD}${YELLOW}┌─ 更多链接 ─────────────────────────────────────────┐${NC}"
        echo -e "  ${GREEN}3)${NC} 🐙 GitHub: @Xiaoxinyun2008"
        #echo -e "     🔗 https://github.com/Xiaoxinyun2008"
        echo -e "  ${GREEN}4)${NC} 🔗 Gitee: 小韵"
        #echo -e "     🔗  https://gitee.com/xytool"
        echo -e "  ${GREEN}5)${NC} 🌐 网站: 小韵🧰"
        #echo -e "     🔗 https://xn--yetw70l.xyz"
        echo -e "  ${GREEN}6)${NC} 💻 CSDN: 小韵666"
        #echo -e "     🔗 https://blog.csdn.net/2401_82802633?spm=1000.2115.3001.5343"
        echo -e "  ${GREEN}7)${NC} 📖 知乎: 零意"
        #echo -e "     🔗 https://www.zhihu.com/people/xxy46548"
        echo -e "  ${GREEN}8)${NC} 📺 哔哩哔哩: 像深渊一样沉默"
        #echo -e "     🔗 https://space.bilibili.com/1198508132?spm_id_from=333.1007.0.0"
        echo -e "  ${BOLD}${YELLOW}└─────────────────────────────────────────────────────┘${NC}"
        echo ""
        echo -e "  ${BOLD}${CYAN}┌─ 操作选项 ─────────────────────────────────────────┐${NC}"
        echo -e "    ${GREEN}[数字]${NC}  打开对应链接    ${GREEN}[b]${NC} 返回主菜单"
        echo -e "  ${BOLD}${CYAN}└─────────────────────────────────────────────────────┘${NC}"
        echo ""
        read -r -p "  👉 请选择要打开的链接 [1-8] 或返回 [b]: " choice </dev/tty

        case $choice in
            1)
                echo ""  # 添加空行以分隔
                open_link "https://qm.qq.com/q/LgAL9PiIY8" "QQ"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            2)
                echo ""  # 添加空行以分隔
                open_link "https://qm.qq.com/q/25rfBURNe8" "Q群"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            3)
                echo ""  # 添加空行以分隔
                open_link "https://github.com/Xiaoxinyun2008" "GitHub"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            4)
                echo ""  # 添加空行以分隔
                open_link "https://gitee.com/xytool" "Gitee"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            5)
                echo ""  # 添加空行以分隔
                open_link "https://xn--yetw70l.xyz" "网站"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            6)
                echo ""  # 添加空行以分隔
                open_link "https://blog.csdn.net/2401_82802633?spm=1000.2115.3001.5343" "CSDN"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            7)
                echo ""  # 添加空行以分隔
                open_link "https://www.zhihu.com/people/xxy46548" "知乎"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            8)
                echo ""  # 添加空行以分隔
                open_link "https://space.bilibili.com/1198508132?spm_id_from=333.1007.0.0" "B站"
                read -r -p "  ${YELLOW}按 Enter 继续...${NC}" </dev/tty
                clear
                show_logo  # 重新显示logo和菜单
                ;;
            [bB])
                break
                ;;
            *)
                echo -e "  ${RED}❌ 无效选择，请输入 1-7 或 b${NC}"
                sleep 2
                clear
                show_logo  # 重新显示logo和菜单
                ;;
        esac
    done
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
    echo -e "${BOLD}${CYAN}┌─ 卸载工具 ──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}卸载管理${NC}"
    echo -e "${BOLD}${CYAN}└─ 卸载工具 ──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}${GREEN}┌─ 已安装工具 ───────────────────────────────────────┐${NC}"
    echo -e "  ${BOLD}已安装的工具:${NC}"
    echo ""

    for i in "${!installed[@]}"; do
        echo -e "    ${GREEN}$((i + 1)))${NC} ${BOLD}${installed[$i]}${NC}"
    done

    echo -e "  ${BOLD}${GREEN}└─ 已安装工具 ───────────────────────────────────────┘${NC}"
    echo ""
    echo -e "  ${BOLD}${YELLOW}┌─ 操作选项 ─────────────────────────────────────────┐${NC}"
    echo -e "    ${GREEN}[a]${NC} 卸载全部    ${GREEN}[b]${NC} 返回"
    echo -e "  ${BOLD}${YELLOW}└─ 操作选项 ─────────────────────────────────────────┘${NC}"
    echo ""
    read -r -p "  ${YELLOW}👉 请输入编号或选项: ${NC}" uninstall_choice </dev/tty

    case $uninstall_choice in
        [aA])
            echo -e "  ${RED}⚠️  正在卸载所有工具...${NC}"
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
    read -r -p "  ${YELLOW}按 Enter 继续... ${NC}" </dev/tty
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
