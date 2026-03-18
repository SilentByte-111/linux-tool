#!/usr/bin/env python3
"""Linux Tool GUI client with built-in update support."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

try:
    import tkinter as tk
    from tkinter import messagebox, scrolledtext, ttk
except ImportError as exc:  # pragma: no cover - runtime dependency check
    print("Tkinter 不可用，请先安装 python3-tk / tk。", file=sys.stderr)
    raise SystemExit(1) from exc

APP_VERSION = "v2.0"
REPO_OWNER = "Xynrin"
REPO_NAME = "linux-tool"
BRANCH = "main"
RAW_BASE = f"https://raw.githubusercontent.com/{REPO_OWNER}/{REPO_NAME}/{BRANCH}"
VERSION_URL = f"{RAW_BASE}/version/versio.md"
UPDATE_FILES = {
    "client/linux_tool_client.py": "linux_tool_client.py",
    "client/tools.json": "tools.json",
    "install.sh": "install.sh",
    "README.md": "README.md",
    "version/versio.md": "version/versio.md",
}
PACKAGE_HINTS = {
    "apt": "sudo apt install -y python3 python3-tk git curl",
    "dnf": "sudo dnf install -y python3 python3-tkinter git curl",
    "yum": "sudo yum install -y python3 tkinter git curl",
    "pacman": "sudo pacman -S --needed python tk git curl",
    "zypper": "sudo zypper install -y python3 python3-tk git curl",
    "apk": "sudo apk add python3 py3-tkinter git curl",
}


@dataclass
class ToolEntry:
    name: str
    description: str
    script: Path
    requires_root: bool
    category: str


class LinuxToolClient:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("Linux Tool Client")
        self.root.geometry("1040x720")
        self.root.minsize(920, 640)

        self.project_root = Path(__file__).resolve().parent.parent
        if not (self.project_root / "tool").exists():
            self.project_root = Path.home() / ".local/share/linux-tool-client"

        self.tools = self._load_tools()
        self.status_var = tk.StringVar(value="就绪")
        self.version_var = tk.StringVar(value=f"当前版本：{APP_VERSION}")
        self.latest_version_var = tk.StringVar(value="远程版本：检查中...")
        self.compat_var = tk.StringVar(value=self._build_compat_text())
        self.selected_tool: ToolEntry | None = None
        self.update_button: ttk.Button | None = None
        self.log_widget: scrolledtext.ScrolledText | None = None
        self.detail_widget: scrolledtext.ScrolledText | None = None

        self._build_layout()
        self._refresh_tool_details(self.tools[0] if self.tools else None)
        self._append_log("Linux Tool GUI 客户端已启动。")
        self._append_log(f"项目目录：{self.project_root}")
        self._check_update_async()

    def _load_tools(self) -> list[ToolEntry]:
        manifest_path = self.project_root / "client/tools.json"
        if not manifest_path.exists():
            manifest_path = self.project_root / "tools.json"
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        tools: list[ToolEntry] = []
        for item in data:
            tools.append(
                ToolEntry(
                    name=item["name"],
                    description=item["description"],
                    script=self.project_root / item["script"],
                    requires_root=item.get("requires_root", False),
                    category=item.get("category", "通用"),
                )
            )
        return tools

    def _build_layout(self) -> None:
        self.root.columnconfigure(0, weight=2)
        self.root.columnconfigure(1, weight=3)
        self.root.rowconfigure(1, weight=1)
        self.root.rowconfigure(2, weight=1)

        header = ttk.Frame(self.root, padding=16)
        header.grid(row=0, column=0, columnspan=2, sticky="nsew")
        header.columnconfigure(0, weight=1)

        ttk.Label(header, text="Linux Tool Client", font=("Arial", 20, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(
            header,
            text="GUI 客户端 + 更新模块 + 多发行版兼容提示",
            font=("Arial", 11),
        ).grid(row=1, column=0, sticky="w", pady=(4, 0))
        ttk.Label(header, textvariable=self.version_var).grid(row=0, column=1, sticky="e")
        ttk.Label(header, textvariable=self.latest_version_var).grid(row=1, column=1, sticky="e")

        left = ttk.LabelFrame(self.root, text="工具列表", padding=12)
        left.grid(row=1, column=0, rowspan=2, sticky="nsew", padx=(16, 8), pady=(0, 16))
        left.columnconfigure(0, weight=1)
        left.rowconfigure(1, weight=1)

        ttk.Label(left, text="双击即可运行所选工具脚本。", foreground="#555").grid(row=0, column=0, sticky="w", pady=(0, 8))

        columns = ("name", "category", "root")
        tree = ttk.Treeview(left, columns=columns, show="headings", height=10)
        tree.heading("name", text="工具")
        tree.heading("category", text="类别")
        tree.heading("root", text="权限")
        tree.column("name", width=220, anchor="w")
        tree.column("category", width=90, anchor="center")
        tree.column("root", width=80, anchor="center")
        tree.grid(row=1, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(left, orient="vertical", command=tree.yview)
        tree.configure(yscrollcommand=scrollbar.set)
        scrollbar.grid(row=1, column=1, sticky="ns")
        self.tree = tree

        for idx, tool in enumerate(self.tools):
            tree.insert("", "end", iid=str(idx), values=(tool.name, tool.category, "sudo" if tool.requires_root else "用户"))
        tree.bind("<<TreeviewSelect>>", self._on_select)
        tree.bind("<Double-1>", lambda _event: self.run_selected_tool())

        button_bar = ttk.Frame(left)
        button_bar.grid(row=2, column=0, columnspan=2, sticky="ew", pady=(12, 0))
        button_bar.columnconfigure((0, 1, 2), weight=1)
        ttk.Button(button_bar, text="运行工具", command=self.run_selected_tool).grid(row=0, column=0, sticky="ew", padx=(0, 8))
        ttk.Button(button_bar, text="打开终端安装器", command=self.run_installer).grid(row=0, column=1, sticky="ew", padx=8)
        self.update_button = ttk.Button(button_bar, text="检查更新", command=self._check_update_async)
        self.update_button.grid(row=0, column=2, sticky="ew", padx=(8, 0))

        top_right = ttk.LabelFrame(self.root, text="工具详情 / 兼容性", padding=12)
        top_right.grid(row=1, column=1, sticky="nsew", padx=(8, 16), pady=(0, 8))
        top_right.columnconfigure(0, weight=1)
        top_right.rowconfigure(1, weight=1)

        ttk.Label(top_right, textvariable=self.compat_var, justify="left", foreground="#1f3b4d").grid(row=0, column=0, sticky="ew", pady=(0, 10))
        detail = scrolledtext.ScrolledText(top_right, wrap="word", height=14)
        detail.grid(row=1, column=0, sticky="nsew")
        detail.configure(state="disabled")
        self.detail_widget = detail

        bottom_right = ttk.LabelFrame(self.root, text="运行日志", padding=12)
        bottom_right.grid(row=2, column=1, sticky="nsew", padx=(8, 16), pady=(8, 16))
        bottom_right.columnconfigure(0, weight=1)
        bottom_right.rowconfigure(0, weight=1)

        log_widget = scrolledtext.ScrolledText(bottom_right, wrap="word", height=14, bg="#101418", fg="#d9f2ff")
        log_widget.grid(row=0, column=0, sticky="nsew")
        log_widget.configure(state="disabled")
        self.log_widget = log_widget

        footer = ttk.Frame(self.root, padding=(16, 0, 16, 12))
        footer.grid(row=3, column=0, columnspan=2, sticky="ew")
        footer.columnconfigure(0, weight=1)
        ttk.Label(footer, textvariable=self.status_var).grid(row=0, column=0, sticky="w")
        ttk.Button(footer, text="退出", command=self.root.destroy).grid(row=0, column=1, sticky="e")

        if self.tools:
            self.tree.selection_set("0")

    def _build_compat_text(self) -> str:
        manager = self._detect_package_manager()
        hint = PACKAGE_HINTS.get(manager, "请安装 python3、Tk、git、curl 后再运行。")
        return (
            "兼容策略：使用 Python + Tkinter 实现 GUI，避免绑定特定桌面环境；\n"
            "支持方式：Debian/Ubuntu、Fedora/RHEL、Arch、openSUSE、Alpine 等常见发行版；\n"
            f"当前建议依赖安装命令：{hint}"
        )

    def _detect_package_manager(self) -> str | None:
        for manager in PACKAGE_HINTS:
            if shutil.which(manager):
                return manager
        return None

    def _append_log(self, message: str) -> None:
        if not self.log_widget:
            return
        self.log_widget.configure(state="normal")
        self.log_widget.insert("end", message + "\n")
        self.log_widget.see("end")
        self.log_widget.configure(state="disabled")

    def _set_detail_text(self, text: str) -> None:
        if not self.detail_widget:
            return
        self.detail_widget.configure(state="normal")
        self.detail_widget.delete("1.0", "end")
        self.detail_widget.insert("1.0", text)
        self.detail_widget.configure(state="disabled")

    def _refresh_tool_details(self, tool: ToolEntry | None) -> None:
        self.selected_tool = tool
        if tool is None:
            self._set_detail_text("当前没有可用工具。")
            return
        detail = [
            f"名称：{tool.name}",
            f"类别：{tool.category}",
            f"路径：{tool.script}",
            f"权限：{'需要 sudo / root' if tool.requires_root else '普通用户即可'}",
            "",
            "功能说明：",
            tool.description,
            "",
            "运行方式：",
            "- 点击“运行工具”后将在子进程中直接执行原始 shell 脚本。",
            "- 如脚本要求 root，GUI 会优先尝试 sudo。",
            "- 若没有图形环境，也可以继续使用 install.sh 终端交互版。",
        ]
        self._set_detail_text("\n".join(detail))

    def _on_select(self, _event: object) -> None:
        selected = self.tree.selection()
        if not selected:
            return
        self._refresh_tool_details(self.tools[int(selected[0])])

    def run_selected_tool(self) -> None:
        tool = self.selected_tool
        if tool is None:
            messagebox.showwarning("未选择工具", "请先从左侧列表选择一个工具。")
            return
        if not tool.script.exists():
            messagebox.showerror("脚本不存在", f"未找到脚本：{tool.script}")
            return

        def task() -> None:
            command = ["bash", str(tool.script)]
            if tool.requires_root and os.geteuid() != 0:
                sudo = shutil.which("sudo")
                if sudo:
                    command.insert(0, sudo)
            self._run_subprocess(command, f"运行工具：{tool.name}")

        threading.Thread(target=task, daemon=True).start()

    def run_installer(self) -> None:
        installer = self.project_root / "install.sh"
        if not installer.exists():
            messagebox.showerror("缺少安装器", f"未找到 {installer}")
            return
        threading.Thread(
            target=lambda: self._run_subprocess(["bash", str(installer)], "启动终端安装器"),
            daemon=True,
        ).start()

    def _run_subprocess(self, command: list[str], title: str) -> None:
        self.root.after(0, lambda: self.status_var.set(f"执行中：{title}"))
        self.root.after(0, lambda: self._append_log(f"$ {' '.join(command)}"))
        try:
            process = subprocess.Popen(
                command,
                cwd=self.project_root,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            assert process.stdout is not None
            for line in process.stdout:
                self.root.after(0, lambda line=line: self._append_log(line.rstrip()))
            code = process.wait()
            if code == 0:
                self.root.after(0, lambda: self.status_var.set(f"完成：{title}"))
            else:
                self.root.after(0, lambda: self.status_var.set(f"失败({code})：{title}"))
        except Exception as exc:  # pragma: no cover - UI side effect
            self.root.after(0, lambda: self._append_log(f"执行失败：{exc}"))
            self.root.after(0, lambda: self.status_var.set(f"异常：{title}"))

    def _check_update_async(self) -> None:
        if self.update_button:
            self.update_button.configure(state="disabled")
        self.status_var.set("正在检查更新...")
        threading.Thread(target=self._check_update, daemon=True).start()

    def _check_update(self) -> None:
        try:
            with urllib.request.urlopen(VERSION_URL, timeout=10) as response:
                content = response.read().decode("utf-8", errors="ignore")
            match = re.search(r"##\s+(v\d+(?:\.\d+)*)", content)
            latest = match.group(1) if match else "未知"
            self.root.after(0, lambda: self.latest_version_var.set(f"远程版本：{latest}"))
            self.root.after(0, lambda: self._append_log(f"远程版本检查完成：{latest}"))
            if latest != "未知" and self._is_newer(latest, APP_VERSION):
                self.root.after(0, lambda: self.status_var.set(f"发现新版本：{latest}"))
                self.root.after(0, lambda: self._prompt_update(latest))
            else:
                self.root.after(0, lambda: self.status_var.set("已是最新版本"))
        except urllib.error.URLError as exc:
            self.root.after(0, lambda: self._append_log(f"检查更新失败：{exc}"))
            self.root.after(0, lambda: self.status_var.set("检查更新失败"))
        finally:
            self.root.after(0, self._enable_update_button)

    def _enable_update_button(self) -> None:
        if self.update_button:
            self.update_button.configure(state="normal")

    def _prompt_update(self, latest: str) -> None:
        if messagebox.askyesno("发现更新", f"检测到 {latest}，是否立即更新 GUI 客户端文件？"):
            self.status_var.set("正在更新客户端...")
            threading.Thread(target=lambda: self._apply_update(latest), daemon=True).start()

    def _apply_update(self, latest: str) -> None:
        temp_dir = Path(tempfile.mkdtemp(prefix="linux-tool-update-"))
        try:
            for remote_path, local_name in UPDATE_FILES.items():
                target_path = temp_dir / local_name
                target_path.parent.mkdir(parents=True, exist_ok=True)
                url = f"{RAW_BASE}/{remote_path}"
                with urllib.request.urlopen(url, timeout=15) as response:
                    target_path.write_bytes(response.read())
                self.root.after(0, lambda p=remote_path: self._append_log(f"已下载更新文件：{p}"))

            destinations = {
                temp_dir / "linux_tool_client.py": self.project_root / "client/linux_tool_client.py",
                temp_dir / "tools.json": self.project_root / "client/tools.json",
                temp_dir / "install.sh": self.project_root / "install.sh",
                temp_dir / "README.md": self.project_root / "README.md",
                temp_dir / "version": self.project_root / "version",
            }

            (self.project_root / "version").mkdir(exist_ok=True)
            shutil.copy2(temp_dir / "linux_tool_client.py", destinations[temp_dir / "linux_tool_client.py"])
            shutil.copy2(temp_dir / "tools.json", destinations[temp_dir / "tools.json"])
            shutil.copy2(temp_dir / "install.sh", destinations[temp_dir / "install.sh"])
            shutil.copy2(temp_dir / "README.md", destinations[temp_dir / "README.md"])
            shutil.copy2(temp_dir / "version/versio.md", self.project_root / "version/versio.md")
            self.root.after(0, lambda: self._append_log(f"客户端已更新到 {latest}。"))
            self.root.after(0, lambda: self.status_var.set(f"更新完成：{latest}，重启后生效"))
        except Exception as exc:
            self.root.after(0, lambda: self._append_log(f"更新失败：{exc}"))
            self.root.after(0, lambda: self.status_var.set("更新失败"))
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    @staticmethod
    def _is_newer(candidate: str, current: str) -> bool:
        def normalize(value: str) -> tuple[int, ...]:
            return tuple(int(part) for part in value.lstrip("vV").split("."))

        return normalize(candidate) > normalize(current)

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    LinuxToolClient().run()
