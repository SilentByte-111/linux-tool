#!/usr/bin/env fish
# 功能：Clash 控制面板

function clashctl
    while true
        clear
        echo "=== Clash 控制面板 ==="
        if pgrep clash >/dev/null
            set clash_pid (pgrep clash)
            set proxy_ip (curl -x http://127.0.0.1:7890 -s https://ipinfo.io/ip 2>/dev/null)
            echo "📊 Clash 正在运行 (PID: $clash_pid)"
            echo "🌐 当前代理 IP: $proxy_ip"
        else
            echo "📊 Clash 未运行"
        end

        echo ""
        echo "1) 启动 Clash"
        echo "2) 停止 Clash"
        echo "3) 开启代理环境变量"
        echo "4) 关闭代理环境变量"
        echo "5) 退出"
        echo ""
        read choice

        switch $choice
            case 1
                nohup clash >/dev/null 2>&1 &
            case 2
                killall clash
            case 3
                set -x http_proxy http://127.0.0.1:7890
                set -x https_proxy http://127.0.0.1:7890
                set -x all_proxy socks5://127.0.0.1:7890
            case 4
                set -e http_proxy
                set -e https_proxy
                set -e all_proxy
            case 5
                break
        end
    end
end

clashctl
