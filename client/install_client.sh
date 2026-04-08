#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/linux-tool-client"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
TARGET="$INSTALL_ROOT/linux_tool_client.py"
LAUNCHER="$BIN_DIR/linux-tool-client"
DESKTOP_FILE="$APP_DIR/linux-tool-client.desktop"

mkdir -p "$INSTALL_ROOT" "$BIN_DIR" "$APP_DIR"
cp "$PROJECT_ROOT/client/linux_tool_client.py" "$TARGET"
cp "$PROJECT_ROOT/client/tools.json" "$INSTALL_ROOT/tools.json"
chmod +x "$TARGET"

cat > "$LAUNCHER" <<LAUNCH
#!/usr/bin/env bash
exec python3 "$TARGET" "\$@"
LAUNCH
chmod +x "$LAUNCHER"

cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=Linux Tool Client
Comment=Linux Tool GUI Client
Exec=$LAUNCHER
Terminal=false
Categories=Utility;System;
StartupNotify=true
DESKTOP

cat <<MSG
Linux Tool GUI 客户端已安装：
- 启动命令: $LAUNCHER
- 桌面入口: $DESKTOP_FILE
- 数据目录: $INSTALL_ROOT

如果系统未安装 Tk，请先安装：
- Debian/Ubuntu: sudo apt install python3-tk
- Fedora: sudo dnf install python3-tkinter
- Arch: sudo pacman -S tk
MSG
