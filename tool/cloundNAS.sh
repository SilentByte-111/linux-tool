#!/bin/bash

# Description: 在线下载云盘os系统
# 用途：在线下载云盘os系统
# 使用方法：cloundNAS

if [ "$EUID" -ne 0 ]; then
    exec sudo bash "$0" "$@"
fi


# ---------------------------- 全局配置 ------------------------------------

# 默认仓库地址 (可通过环境变量 NAS_REPO_URL 覆盖)
# 在发布到GitHub前，请修改这个默认值为你的仓库地址
NAS_REPO_URL="${NAS_REPO_URL:-https://github.com/SilentByte-111/nas-system.git}"

# 安装目录
NAS_INSTALL_DIR="${NAS_INSTALL_DIR:-$HOME/nas-system}"

# ---------------------------- 颜色定义 ------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# ---------------------------- Banner ------------------------------------

show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
   ____ ____  _  __      __  __
  / ___|  _ \| |/ /     |  \/  |
 | |   | |_) | ' / _____| |\/| |
 | |___|  _ <| . \|_____| |  | |
  \____|_| \_\_|\_\     |_|  |_|

  Personal Cloud Storage System
  来自于 linux-tool 的子工具！
  linux仓库地址：github/SilentByte-111/linux-tool
EOF
    echo -e "${NC}"
}

# ---------------------------- 检查依赖 ------------------------------------

check_dependencies() {
    local missing=()

    echo -e "${YELLOW}检查系统依赖...${NC}"

    # 检查 curl
    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    # 检查 git
    if ! command -v git &> /dev/null; then
        missing+=("git")
    fi

    # 检查 node
    if ! command -v node &> /dev/null; then
        missing+=("node")
    fi

    # 检查 npm
    if ! command -v npm &> /dev/null; then
        missing+=("npm")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}缺少必要的系统依赖:${NC}"
        echo "  ${missing[@]}"
        echo ""
        echo -e "${YELLOW}请先安装依赖:${NC}"
        echo "  Ubuntu/Debian: sudo apt-get install -y ${missing[*]}"
        echo "  CentOS/RHEL:   sudo yum install -y ${missing[*]}"
        echo "  macOS:         brew install ${missing[*]}"
        return 1
    fi

    # 检查 Node.js 版本
    node_version=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$node_version" -lt 16 ]; then
        echo -e "${RED}Node.js 版本过低，需要 v16 或更高版本${NC}"
        echo -e "${YELLOW}当前版本: $(node -v)${NC}"
        echo -e "${YELLOW}请升级 Node.js: https://nodejs.org/${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ 所有依赖已满足${NC}"
    return 0
}

# ---------------------------- 克隆仓库 ------------------------------------

clone_or_update() {
    echo -e "${YELLOW}仓库地址: $NAS_REPO_URL${NC}"
    echo -e "${YELLOW}安装目录: $NAS_INSTALL_DIR${NC}"
    echo ""

    if [ -d "$NAS_INSTALL_DIR" ]; then
        echo -e "${YELLOW}检测到已安装的 CloudNAS${NC}"
        read -p "是否更新到最新版本? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "$NAS_INSTALL_DIR"
            echo -e "${YELLOW}正在更新代码...${NC}"
            git pull origin main 2>/dev/null || git pull origin master 2>/dev/null
            echo -e "${GREEN}✓ 代码已更新${NC}"
        fi
    else
        echo -e "${YELLOW}正在克隆仓库...${NC}"
        git clone "$NAS_REPO_URL" "$NAS_INSTALL_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}克隆仓库失败，请检查仓库地址是否正确${NC}"
            return 1
        fi
        echo -e "${GREEN}✓ 仓库克隆成功${NC}"
    fi

    cd "$NAS_INSTALL_DIR"
    return 0
}

# ---------------------------- 安装依赖 ------------------------------------

install_dependencies() {
    echo ""
    echo -e "${YELLOW}正在安装项目依赖...${NC}"

    # 安装前端依赖
    if [ -f "package.json" ]; then
        echo -e "${BLUE}→ 安装前端依赖...${NC}"
        npm install --prefix "$NAS_INSTALL_DIR" 2>&1 | tail -3
    fi

    # 安装后端依赖
    if [ -f "server/package.json" ]; then
        echo -e "${BLUE}→ 安装后端依赖...${NC}"
        npm install --prefix "$NAS_INSTALL_DIR/server" 2>&1 | tail -3
    fi

    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}

# ---------------------------- 启动服务 ------------------------------------

start_service() {
    echo ""
    echo -e "${YELLOW}正在启动 CloudNAS 服务...${NC}"

    cd "$NAS_INSTALL_DIR"

    if [ -f "./start.sh" ]; then
        chmod +x ./start.sh
        bash ./start.sh
    else
        echo -e "${RED}找不到 start.sh 脚本${NC}"
        return 1
    fi
}

# ---------------------------- 停止服务 ------------------------------------

stop_service() {
    echo ""
    echo -e "${YELLOW}正在停止 CloudNAS 服务...${NC}"

    cd "$NAS_INSTALL_DIR"

    if [ -f "./stop.sh" ]; then
        chmod +x ./stop.sh
        bash ./stop.sh
    else
        echo -e "${RED}找不到 stop.sh 脚本${NC}"
        return 1
    fi
}

# ---------------------------- 查看状态 ------------------------------------

show_status() {
    echo ""
    echo -e "${YELLOW}检查服务状态...${NC}"

    local backend_running=false
    local frontend_running=false

    # 检查后端
    if curl -s http://localhost:1111/health > /dev/null 2>&1; then
        backend_running=true
    fi

    # 检查前端
    if curl -s http://localhost:5173 > /dev/null 2>&1; then
        frontend_running=true
    fi

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│         CloudNAS 服务状态           │${NC}"
    echo -e "${CYAN}├─────────────────────────────────────┤${NC}"

    if [ "$backend_running" = true ]; then
        echo -e "${CYAN}│  ${GREEN}●${NC}  后端服务 (1111)    ${GREEN}运行中${NC}   │${NC}"
    else
        echo -e "${CYAN}│  ${RED}○${NC}  后端服务 (1111)    ${RED}未运行${NC}   │${NC}"
    fi                  

    if [ "$frontend_running" = true ]; then
        echo -e "${CYAN}│  ${GREEN}●${NC}  前端服务 (5173)    ${GREEN}运行中${NC}   │${NC}"
    else
        echo -e "${CYAN}│  ${RED}○${NC}  前端服务 (5173)    ${RED}未运行${NC}   │${NC}"
    fi

    echo -e "${CYAN}└─────────────────────────────────────┘${NC}"
    echo ""

    if [ "$frontend_running" = true ]; then
        local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo -e "${GREEN}访问地址: http://${local_ip}:5173${NC}"
    fi
}

# ---------------------------- 卸载服务 ------------------------------------

uninstall_service() {
    echo ""
    echo -e "${YELLOW}卸载 CloudNAS...${NC}"

    # 先停止服务
    cd "$NAS_INSTALL_DIR"
    if [ -f "./stop.sh" ]; then
        bash ./stop.sh
    fi

    read -p "确定要删除安装目录 ($NAS_INSTALL_DIR) 吗? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$NAS_INSTALL_DIR"
        echo -e "${GREEN}✓ CloudNAS 已卸载${NC}"
    else
        echo -e "${YELLOW}卸载已取消${NC}"
    fi
}

# ---------------------------- 交互菜单 ------------------------------------

show_menu() {
    clear
    show_banner
    echo ""
    echo -e "${PURPLE}请选择操作:${NC}"
    echo ""
    echo -e "${CYAN}  1)${NC} 安装/更新 CloudNAS"
    echo -e "${CYAN}  2)${NC} 启动服务"
    echo -e "${CYAN}  3)${NC} 停止服务"
    echo -e "${CYAN}  4)${NC} 查看服务状态"
    echo -e "${CYAN}  5)${NC} 卸载 CloudNAS"
    echo -e "${CYAN}  0)${NC} 退出"
    echo ""

    read -p "请输入选项 (0-5): " choice
    echo ""

    case $choice in
        1)
            if check_dependencies; then
                clone_or_update && install_dependencies
            fi
            ;;
        2)
            start_service
            ;;
        3)
            stop_service
            ;;
        4)
            show_status
            ;;
        5)
            uninstall_service
            ;;
        0)
            echo -e "${CYAN}再见!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选项，请重新选择${NC}"
            ;;
    esac

    echo ""
    read -p "按回车键继续..."
    show_menu
}

# ---------------------------- 主函数 ------------------------------------

main() {
    local mode="${1:-install}"

    show_banner

    case "$mode" in
        install)
            # 一键安装模式
            if check_dependencies; then
                clone_or_update
                if [ $? -eq 0 ]; then
                    install_dependencies
                    start_service
                fi
            fi
            ;;
        update)
            # 更新模式
            clone_or_update
            install_dependencies
            ;;
        start)
            # 仅启动
            start_service
            ;;
        stop)
            # 仅停止
            stop_service
            ;;
        status)
            # 查看状态
            show_status
            ;;
        uninstall)
            # 卸载
            uninstall_service
            ;;
        interactive)
            # 交互模式
            show_menu
            ;;
        help|--help|-h)
            echo "使用方法: $0 [模式]"
            echo ""
            echo "模式:"
            echo "  install      一键安装 (默认)"
            echo "  update       更新代码"
            echo "  start        启动服务"
            echo "  stop         停止服务"
            echo "  status       查看状态"
            echo "  uninstall    卸载"
            echo "  interactive  交互式菜单"
            echo ""
            echo "环境变量:"
            echo "  NAS_REPO_URL     Git仓库地址"
            echo "  NAS_INSTALL_DIR  安装目录"
            echo ""
            echo "示例:"
            echo "  $0 install"
            echo "  NAS_REPO_URL=https://github.com/SilentByte-111/nas-system.git $0 install"
            echo "  $0 interactive"
            ;;
        *)
            echo -e "${RED}未知模式: $mode${NC}"
            echo "使用 $0 help 查看帮助"
            exit 1
            ;;
    esac
}

# 执行主函数，传递所有参数
main "$@"
