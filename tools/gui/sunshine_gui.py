#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sunshine 串流控制台（PySide6 图形外壳）。

边界：
  - 只负责界面、进程编排和日志展示；
  - 安装/卸载/恢复显示/面板逻辑全部复用部署包里的 .cmd / .ps1；
  - 所有外部进程都用 QProcess 异步执行，主线程不做阻塞等待。

凭据：
  - 一键部署.cmd 不接收参数，OneClick.ps1 用 Read-Host 依次读取用户名、密码；
  - 这里把两行凭据写进 QProcess 的 stdin（GBK，和无窗口控制台的默认输入编码一致）。

结果弹窗：
  - 启动子进程时注入 SUNSHINE_GUI=1，OneClick.ps1 / Uninstall.ps1 会把
    Show-Result.ps1 切到 -PrintOnly，只打印文本，不弹内部窗口；
  - 成功/失败提示统一由本程序负责。
"""

from __future__ import annotations

import codecs
import ctypes
import json
import os
import subprocess
import sys
import time
from pathlib import Path

from PySide6.QtCore import QProcess, QProcessEnvironment, Qt, QTimer
from PySide6.QtGui import QColor, QFont, QPalette, QTextCursor
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPlainTextEdit,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

APP_TITLE = "Sunshine 串流控制台"


# ---------------------------------------------------------------- 路径与权限

def application_base_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def find_package_root() -> Path | None:
    """找到含 一键部署.cmd 的目录。

    兼容三种放法：
      - exe 放在解压后的包根；
      - exe 放在包的子目录里；
      - 源码放在仓库 tools/gui 下（向上找到 repo/payload）。
    """
    start = application_base_dir()
    for parent in [start, *start.parents][:6]:
        for candidate in (parent, parent / "payload"):
            if (candidate / "一键部署.cmd").is_file():
                return candidate
    return None


def package_version(root: Path | None) -> str:
    if not root:
        return ""
    manifest = root / "manifest" / "components.json"
    try:
        data = json.loads(manifest.read_text(encoding="utf-8-sig"))
        return str(data.get("package", {}).get("version", ""))
    except Exception:
        return ""


def is_admin() -> bool:
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def _native_error(message: str) -> None:
    ctypes.windll.user32.MessageBoxW(None, message, APP_TITLE, 0x10)


def request_elevation() -> bool:
    """以管理员身份重启自己。成功发起 UAC 时返回 True。"""
    if getattr(sys, "frozen", False):
        executable = sys.executable
        arguments = sys.argv[1:]
    else:
        executable = sys.executable
        arguments = [str(Path(__file__).resolve()), *sys.argv[1:]]

    # 只用 list2cmdline 拼参数，不在这里执行任何子进程。
    params = subprocess.list2cmdline(arguments)
    shell32 = ctypes.windll.shell32
    shell32.ShellExecuteW.restype = ctypes.c_void_p
    result = shell32.ShellExecuteW(
        None, "runas", executable, params, str(application_base_dir()), 1
    )
    return int(result or 0) > 32


# ---------------------------------------------------------------- 日志解码

class ConsoleDecoder:
    """自适应 GBK / UTF-8 的增量解码器。

    GUI 进程没有控制台时，Windows 子进程通常按 OEM 代码页（中文为 GBK）输出；
    少数机器配置成 UTF-8。先按 GBK 严格试解，失败再试 UTF-8，锁定后增量解码，
    这样跨数据块的多字节字符不会变成乱码。
    """

    def __init__(self) -> None:
        self._encoding: str | None = None
        self._decoder = None
        self._buffer = bytearray()

    def feed(self, data: bytes, final: bool = False) -> str:
        if self._encoding:
            return self._decoder.decode(data, final)

        self._buffer.extend(data)
        if not self._buffer:
            return ""

        raw = bytes(self._buffer)
        if raw.isascii():
            self._buffer.clear()
            return raw.decode("ascii")

        for encoding in ("gbk", "utf-8"):
            try:
                text = raw.decode(encoding)
            except UnicodeDecodeError as exc:
                # 尾部被切断：等下一块数据再判断，不要急着锁定编码。
                if not final and exc.end == len(raw) and exc.reason in (
                    "incomplete multibyte sequence",
                    "unexpected end of data",
                ):
                    return ""
                continue
            self._encoding = encoding
            self._decoder = codecs.getincrementaldecoder(encoding)("replace")
            self._buffer.clear()
            return text

        if final or len(self._buffer) > 16384:
            text = raw.decode("gbk", errors="replace")
            self._buffer.clear()
            self._encoding = "gbk"
            self._decoder = codecs.getincrementaldecoder("gbk")("replace")
            return text
        return ""


# ---------------------------------------------------------------- 样式

STYLE = """
QMainWindow, QWidget {
    background-color: #0f1115;
    color: #e6e8eb;
    font-family: "Microsoft YaHei UI", "Segoe UI", sans-serif;
    font-size: 13px;
}
QLabel#title { font-size: 20px; font-weight: 600; color: #f4f6f8; }
QLabel#subtitle { color: #8b93a1; font-size: 12px; }
QLabel#section { color: #c9ced6; font-size: 13px; font-weight: 600; }
QLabel#fieldLabel { color: #9aa3b2; font-size: 12px; }
QLabel#hint { color: #7d8695; font-size: 11px; }
QLabel#status { color: #8b93a1; font-size: 12px; }
QLabel#rootError { color: #f87171; font-size: 12px; }
QFrame#card {
    background-color: #141820;
    border: 1px solid #232936;
    border-radius: 8px;
}
QLineEdit {
    background-color: #0f131a;
    border: 1px solid #2a3140;
    border-radius: 6px;
    padding: 8px 10px;
    color: #e6e8eb;
    selection-background-color: #2563eb;
}
QLineEdit:focus { border-color: #3b82f6; }
QLineEdit:disabled { color: #6b7280; background-color: #12161d; }
QCheckBox { color: #c9ced6; spacing: 8px; }
QCheckBox:disabled { color: #636b78; }
QCheckBox#panelToggle {
    color: #f4f6f8;
    font-size: 14px;
    font-weight: 600;
    spacing: 10px;
    padding: 12px 14px;
    background-color: #101b2e;
    border: 1px solid #2b4a7a;
    border-radius: 7px;
}
QCheckBox#panelToggle:hover {
    border-color: #3b82f6;
    background-color: #13233d;
}
QCheckBox#panelToggle:checked {
    border-color: #3b82f6;
    background-color: #13233d;
}
QCheckBox#panelToggle:disabled {
    color: #7a8496;
    border-color: #263247;
    background-color: #121722;
}
QLabel#optionHint { color: #93a4c4; font-size: 11px; padding-left: 14px; }
QPushButton {
    background-color: #1b2029;
    border: 1px solid #2a3140;
    border-radius: 6px;
    padding: 9px 16px;
    color: #e6e8eb;
}
QPushButton:hover { background-color: #232a36; border-color: #3a4354; }
QPushButton:pressed { background-color: #151a22; }
QPushButton:disabled {
    color: #636b78;
    background-color: #141920;
    border-color: #232936;
}
QPushButton#primary {
    background-color: #2563eb;
    border-color: #2563eb;
    color: #ffffff;
    font-weight: 600;
}
QPushButton#primary:hover { background-color: #3b82f6; }
QPushButton#primary:disabled {
    background-color: #1e3a6e;
    border-color: #1e3a6e;
    color: #93a4c4;
}
QPushButton#danger {
    background-color: #3a1c22;
    border-color: #5b2630;
    color: #fda4af;
}
QPushButton#danger:hover { background-color: #4a222a; border-color: #7f3040; }
QPushButton#ghost { background-color: transparent; }
QPlainTextEdit#log {
    background-color: #000000;
    color: #d4d7dd;
    border: 1px solid #232936;
    border-radius: 8px;
    padding: 8px;
    selection-background-color: #1d4ed8;
}
QScrollBar:vertical {
    background: #0b0e13;
    width: 10px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background: #2c3442;
    min-height: 24px;
    border-radius: 5px;
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QToolTip {
    background-color: #1b2029;
    color: #e6e8eb;
    border: 1px solid #2a3140;
}
"""


def apply_theme(app: QApplication) -> None:
    app.setStyle("Fusion")
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor("#0f1115"))
    palette.setColor(QPalette.ColorRole.WindowText, QColor("#e6e8eb"))
    palette.setColor(QPalette.ColorRole.Base, QColor("#000000"))
    palette.setColor(QPalette.ColorRole.AlternateBase, QColor("#141820"))
    palette.setColor(QPalette.ColorRole.Text, QColor("#e6e8eb"))
    palette.setColor(QPalette.ColorRole.Button, QColor("#1b2029"))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor("#e6e8eb"))
    palette.setColor(QPalette.ColorRole.Highlight, QColor("#2563eb"))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor("#ffffff"))
    app.setPalette(palette)
    app.setStyleSheet(STYLE)


# ---------------------------------------------------------------- 主窗口

class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.root = find_package_root()
        self.version = package_version(self.root)
        self._proc: QProcess | None = None
        self._action: str | None = None
        self._action_title = ""
        self._started_at = 0.0
        self._pending_stdin: bytes | None = None
        self._decoder = ConsoleDecoder()
        self._pending_text: list[str] = []
        self._buttons: list[QPushButton] = []
        self._deploy_with_panel = False

        self.setWindowTitle(APP_TITLE)
        self.resize(1000, 740)
        self.setMinimumSize(860, 600)

        self._flush_timer = QTimer(self)
        self._flush_timer.setInterval(60)
        self._flush_timer.timeout.connect(self._flush_log)

        self._build_ui()

        if self.root:
            version_text = f"  ·  v{self.version}" if self.version else ""
            self.title_label.setText(f"Sunshine 串流控制台{version_text}")
            self._append(
                f"{APP_TITLE}\n"
                f"部署包：{self.root}\n"
                f"管理员：{'是' if is_admin() else '否'}\n"
            )
        else:
            self.root_error.show()
            self._append(
                "未找到 一键部署.cmd。\n"
                "请把 Sunshine控制台.exe 放到解压后的安装包根目录，"
                "与 一键部署.cmd、一键卸载.cmd 放在一起。\n"
            )
            self._set_status("未找到部署包", "err")

    # ---- 界面

    def _build_ui(self) -> None:
        central = QWidget()
        self.setCentralWidget(central)
        outer = QVBoxLayout(central)
        outer.setContentsMargins(20, 18, 20, 16)
        outer.setSpacing(12)

        self.title_label = QLabel("Sunshine 串流控制台")
        self.title_label.setObjectName("title")
        subtitle = QLabel("局域网串流 · 部署 / 虚拟屏 / 免登录面板 / 卸载")
        subtitle.setObjectName("subtitle")
        outer.addWidget(self.title_label)
        outer.addWidget(subtitle)

        self.root_error = QLabel(
            "未找到部署脚本：请将本程序放到安装包根目录（与 一键部署.cmd 同级）。"
        )
        self.root_error.setObjectName("rootError")
        self.root_error.setWordWrap(True)
        self.root_error.hide()
        outer.addWidget(self.root_error)

        # 顶部操作区
        top_card = QFrame()
        top_card.setObjectName("card")
        top_layout = QVBoxLayout(top_card)
        top_layout.setContentsMargins(16, 16, 16, 14)
        top_layout.setSpacing(12)

        button_row = QHBoxLayout()
        button_row.setSpacing(10)
        self.btn_deploy = self._button("一键部署", "primary", self._deploy)
        self.btn_panel = self._button("启动免登录面板", None, self._panel_open)
        self.btn_uninstall = self._button("一键卸载", "danger", self._uninstall)
        button_row.addWidget(self.btn_deploy, 2)
        button_row.addWidget(self.btn_panel, 1)
        button_row.addWidget(self.btn_uninstall, 1)
        top_layout.addLayout(button_row)

        form = QHBoxLayout()
        form.setSpacing(12)
        user_col = QVBoxLayout()
        user_col.setSpacing(6)
        user_label = QLabel("Sunshine 用户名")
        user_label.setObjectName("fieldLabel")
        self.username = QLineEdit()
        self.username.setPlaceholderText("留空 = admin（默认）")
        self.username.setClearButtonEnabled(True)
        user_col.addWidget(user_label)
        user_col.addWidget(self.username)

        pwd_col = QVBoxLayout()
        pwd_col.setSpacing(6)
        pwd_label = QLabel("Sunshine 密码")
        pwd_label.setObjectName("fieldLabel")
        self.password = QLineEdit()
        self.password.setPlaceholderText("留空 = 随机生成 16 位")
        self.password.setEchoMode(QLineEdit.EchoMode.Password)
        pwd_col.addWidget(pwd_label)
        pwd_col.addWidget(self.password)

        form.addLayout(user_col, 1)
        form.addLayout(pwd_col, 1)
        top_layout.addLayout(form)

        self.deploy_panel = QCheckBox("同时部署免登录面板（推荐）")
        self.deploy_panel.setObjectName("panelToggle")
        self.deploy_panel.setChecked(True)
        self.deploy_panel.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        self.deploy_panel.setCursor(Qt.CursorShape.PointingHandCursor)
        self.deploy_panel.setToolTip(
            "勾选后调用 一键部署-免登录面板.cmd；取消则只做标准部署。"
        )
        top_layout.addWidget(self.deploy_panel)

        option_hint = QLabel(
            "安装到 ProgramData，并创建桌面快捷方式；之后打开面板无需账号密码。"
        )
        option_hint.setObjectName("optionHint")
        top_layout.addWidget(option_hint)

        hint = QLabel(
            "凭据只用于本次部署；留空时用户名 admin、密码随机生成，结果会写入日志。"
        )
        hint.setObjectName("hint")
        top_layout.addWidget(hint)
        outer.addWidget(top_card)

        # 中部维护区
        maint_card = QFrame()
        maint_card.setObjectName("card")
        maint_layout = QHBoxLayout(maint_card)
        maint_layout.setContentsMargins(14, 10, 14, 10)
        maint_layout.setSpacing(8)
        maint_title = QLabel("维护")
        maint_title.setObjectName("section")
        maint_layout.addWidget(maint_title)
        maint_layout.addSpacing(6)
        self.btn_restore_display = self._button(
            "恢复显示（修复黑屏）", "ghost", self._restore_display, height=32
        )
        self.btn_restore_baseline = self._button(
            "恢复基线", "ghost", self._restore_baseline, height=32
        )
        self.btn_panel_stop = self._button(
            "停止面板", "ghost", self._panel_stop, height=32
        )
        self.btn_clear = self._button("清空日志", "ghost", self._clear_log, height=32)
        maint_layout.addWidget(self.btn_restore_display)
        maint_layout.addWidget(self.btn_restore_baseline)
        maint_layout.addWidget(self.btn_panel_stop)
        maint_layout.addStretch(1)
        maint_layout.addWidget(self.btn_clear)
        outer.addWidget(maint_card)

        # 日志区
        log_head = QHBoxLayout()
        log_title = QLabel("运行日志")
        log_title.setObjectName("section")
        self.status_label = QLabel("就绪")
        self.status_label.setObjectName("status")
        log_head.addWidget(log_title)
        log_head.addStretch(1)
        log_head.addWidget(self.status_label)
        outer.addLayout(log_head)

        self.log = QPlainTextEdit()
        self.log.setObjectName("log")
        self.log.setReadOnly(True)
        self.log.setMaximumBlockCount(30000)
        self.log.setFont(QFont("Consolas", 10))
        self.log.setLineWrapMode(QPlainTextEdit.LineWrapMode.NoWrap)
        outer.addWidget(self.log, 1)

        if not self.root:
            for button in self._buttons:
                button.setEnabled(False)
            self.username.setEnabled(False)
            self.password.setEnabled(False)
            self.deploy_panel.setEnabled(False)

    def _button(
        self,
        text: str,
        kind: str | None,
        slot,
        height: int = 40,
    ) -> QPushButton:
        button = QPushButton(text)
        if kind:
            button.setObjectName(kind)
        button.setCursor(Qt.CursorShape.PointingHandCursor)
        button.setMinimumHeight(height)
        button.clicked.connect(slot)
        self._buttons.append(button)
        return button

    # ---- 日志

    def _append(self, text: str) -> None:
        self._pending_text.append(text)
        self._flush_log()

    def _flush_log(self) -> None:
        if not self._pending_text:
            self._flush_timer.stop()
            return
        text = "".join(self._pending_text)
        self._pending_text.clear()

        text = text.replace("\r\n", "\n").replace("\r", "\n")
        cursor = self.log.textCursor()
        cursor.movePosition(QTextCursor.MoveOperation.End)
        cursor.insertText(text)
        self.log.setTextCursor(cursor)
        self.log.ensureCursorVisible()

    def _set_status(self, text: str, kind: str = "idle") -> None:
        colors = {
            "idle": "#8b93a1",
            "busy": "#60a5fa",
            "ok": "#4ade80",
            "err": "#f87171",
        }
        self.status_label.setText(text)
        self.status_label.setStyleSheet(f"color: {colors.get(kind, colors['idle'])};")

    def _clear_log(self) -> None:
        self.log.clear()
        self._set_status("就绪", "idle")

    # ---- 进程

    def _set_busy(self, busy: bool, title: str = "") -> None:
        enabled = (not busy) and (self.root is not None)
        for button in self._buttons:
            button.setEnabled(enabled)
        self.username.setEnabled(enabled)
        self.password.setEnabled(enabled)
        self.deploy_panel.setEnabled(enabled)
        if busy:
            self._set_status(f"执行中：{title}", "busy")

    def _run(
        self,
        action: str,
        title: str,
        program: str,
        arguments: list[str],
        stdin_data: bytes | None = None,
    ) -> None:
        if self._proc is not None:
            return
        if not self.root:
            QMessageBox.warning(
                self, "未找到部署包", "请把本程序放到安装包根目录后再试。"
            )
            return

        self._action = action
        self._action_title = title
        self._started_at = time.monotonic()
        self._pending_stdin = stdin_data
        self._decoder = ConsoleDecoder()
        self._pending_text.clear()

        self._append(f"\n===== [{time.strftime('%H:%M:%S')}] {title} =====\n")
        self._set_busy(True, title)

        process = QProcess(self)
        process.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
        process.setWorkingDirectory(str(self.root))
        environment = QProcessEnvironment.systemEnvironment()
        # 让 OneClick/Uninstall 把 Show-Result 切到 PrintOnly，避免内部弹窗抢焦点。
        environment.insert("SUNSHINE_GUI", "1")
        process.setProcessEnvironment(environment)

        process.readyReadStandardOutput.connect(self._on_output)
        process.readyReadStandardError.connect(self._on_output)
        process.started.connect(self._on_started)
        process.finished.connect(self._on_finished)
        process.errorOccurred.connect(self._on_error)

        self._proc = process
        process.start(program, arguments)

    def _on_started(self) -> None:
        if not self._proc:
            return
        if self._pending_stdin is not None:
            self._proc.write(self._pending_stdin)
        self._pending_stdin = None
        self._proc.closeWriteChannel()

    def _on_output(self) -> None:
        if not self._proc:
            return
        data = bytes(self._proc.readAllStandardOutput())
        data += bytes(self._proc.readAllStandardError())
        if not data:
            return
        text = self._decoder.feed(data)
        if text:
            self._pending_text.append(text)
            if not self._flush_timer.isActive():
                self._flush_timer.start()

    def _on_error(self, error: QProcess.ProcessError) -> None:
        if error != QProcess.ProcessError.FailedToStart or not self._proc:
            return
        message = self._proc.errorString()
        self._append(f"\nFAIL 无法启动进程：{message}\n")
        self._finish_process(False, -1, "启动失败")

    def _on_finished(
        self, exit_code: int, exit_status: QProcess.ExitStatus
    ) -> None:
        if not self._proc:
            return

        data = bytes(self._proc.readAllStandardOutput())
        data += bytes(self._proc.readAllStandardError())
        text = self._decoder.feed(data, final=True)
        if text:
            self._pending_text.append(text)
        self._flush_log()

        ok = (
            exit_status == QProcess.ExitStatus.NormalExit
            and exit_code == 0
        )
        elapsed = time.monotonic() - self._started_at
        self._append(
            f"\n----- 退出码 {exit_code}，耗时 {elapsed:.1f} 秒 -----\n"
        )
        self._finish_process(ok, exit_code, self._action_title)

    def _finish_process(self, ok: bool, exit_code: int, title: str) -> None:
        action = self._action
        process = self._proc
        self._proc = None
        self._action = None
        self._pending_stdin = None
        if process:
            process.deleteLater()

        self._set_busy(False)
        self._set_status("完成" if ok else "未完成", "ok" if ok else "err")
        self._notify_result(action, ok, exit_code, title)

    def _notify_result(
        self, action: str | None, ok: bool, exit_code: int, title: str
    ) -> None:
        if action == "deploy":
            if ok:
                message = (
                    "一键部署已执行完成。\n\n"
                    "Sunshine 的账号密码、Web UI 地址和每一步结果已写入下方日志。"
                )
                if self._deploy_with_panel:
                    message += (
                        "\n\n免登录面板已安装，"
                        "可从桌面「Sunshine 控制台」快捷方式启动。"
                    )
                QMessageBox.information(self, "部署完成", message)
            else:
                QMessageBox.warning(
                    self,
                    "部署未完成",
                    f"{title}退出码 {exit_code}。\n\n请查看下方日志定位失败的步骤。",
                )
            return

        if action == "uninstall":
            if ok:
                QMessageBox.information(
                    self, "卸载完成", "虚拟屏、Sunshine 和 ViGEmBus 已按顺序清理。"
                )
            else:
                QMessageBox.warning(
                    self,
                    "卸载未完成",
                    f"退出码 {exit_code}。\n\n请查看下方日志确认残留项。",
                )
            return

        if action == "panel_open":
            if ok:
                self._set_status("面板已启动", "ok")
            else:
                QMessageBox.warning(
                    self,
                    "面板未启动",
                    f"退出码 {exit_code}。\n\n请确认已安装免登录面板，或查看日志。",
                )
            return

        if not ok:
            QMessageBox.warning(
                self,
                "执行未完成",
                f"{title}退出码 {exit_code}。\n\n请查看下方日志。",
            )

    # ---- 动作

    def _deploy(self) -> None:
        if not self.root:
            return
        username = self.username.text().strip()
        password = self.password.text()
        if "\r" in username or "\n" in username or "\r" in password or "\n" in password:
            QMessageBox.warning(self, "凭据格式", "用户名或密码不能包含换行符。")
            return

        # 两行凭据 + 一个备用空行：失败时 cmd 末尾的 pause 不会卡住。
        try:
            stdin_data = (
                username + "\r\n" + password + "\r\n\r\n"
            ).encode("gbk")
        except UnicodeEncodeError:
            QMessageBox.warning(
                self,
                "凭据编码",
                "用户名或密码包含 GBK 无法表示的字符（例如 emoji），"
                "请改用常见字符后重试。",
            )
            return

        with_panel = self.deploy_panel.isChecked()
        cmd_name = (
            "一键部署-免登录面板.cmd" if with_panel else "一键部署.cmd"
        )
        cmd_path = self.root / cmd_name
        if not cmd_path.is_file():
            QMessageBox.warning(
                self,
                "缺少入口脚本",
                f"当前安装包没有 {cmd_name}。\n"
                "请取消勾选，或换用 0.7.3 及之后的完整安装包。",
            )
            return

        self._deploy_with_panel = with_panel
        title = "一键部署（含免登录面板）" if with_panel else "一键部署"
        self._run(
            "deploy",
            title,
            "cmd.exe",
            ["/c", str(cmd_path)],
            stdin_data,
        )

    def _uninstall(self) -> None:
        if not self.root:
            return
        confirm = QMessageBox.question(
            self,
            "确认卸载",
            "将卸载虚拟屏、Sunshine 和 ViGEmBus，并清理防火墙规则、快捷方式与状态目录。\n\n"
            "确定继续吗？",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        if confirm != QMessageBox.StandardButton.Yes:
            return

        # Y 回应 cmd 的确认；后面的空行给失败分支的 pause 用。
        self._run(
            "uninstall",
            "一键卸载",
            "cmd.exe",
            ["/c", str(self.root / "一键卸载.cmd")],
            b"Y\r\n\r\n",
        )

    def _panel_script(self) -> Path | None:
        program_data = Path(os.environ.get("ProgramData", r"C:\ProgramData"))
        installed = (
            program_data
            / "sunshine-lan-streaming"
            / "panel"
            / "Panel.ps1"
        )
        if installed.is_file():
            return installed
        if self.root:
            local = self.root / "scripts" / "Panel.ps1"
            if local.is_file():
                return local
        return None

    def _panel_open(self) -> None:
        script = self._panel_script()
        if not script:
            QMessageBox.warning(
                self,
                "未安装面板",
                "没有找到 Panel.ps1。请先用「一键部署-免登录面板.cmd」部署，"
                "或确认安装包完整。",
            )
            return
        self._run(
            "panel_open",
            "启动免登录面板",
            "powershell.exe",
            [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
                "-Action",
                "open",
            ],
        )

    def _panel_stop(self) -> None:
        script = self._panel_script()
        if not script:
            QMessageBox.warning(self, "未安装面板", "没有找到 Panel.ps1。")
            return
        self._run(
            "panel_stop",
            "停止免登录面板",
            "powershell.exe",
            [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
                "-Action",
                "stop",
            ],
        )

    def _restore_display(self) -> None:
        if not self.root:
            return
        script = self.root / "scripts" / "Restore-Display.ps1"
        if not script.is_file():
            QMessageBox.warning(self, "缺少脚本", f"找不到 {script}")
            return
        self._run(
            "restore_display",
            "恢复显示",
            "powershell.exe",
            [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
            ],
        )

    def _restore_baseline(self) -> None:
        if not self.root:
            return
        script = self.root / "scripts" / "Restore-Baseline.ps1"
        if not script.is_file():
            QMessageBox.warning(self, "缺少脚本", f"找不到 {script}")
            return
        self._run(
            "restore_baseline",
            "恢复基线",
            "powershell.exe",
            [
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(script),
            ],
        )

    # ---- 关闭保护

    def closeEvent(self, event) -> None:
        if self._proc is not None:
            QMessageBox.warning(
                self,
                "任务进行中",
                "脚本仍在执行，请等待完成后再关闭窗口，避免安装或卸载被中断。",
            )
            event.ignore()
            return
        event.accept()


# ---------------------------------------------------------------- 入口

def main() -> int:
    smoke_test = "--smoke-test" in sys.argv
    if smoke_test:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    elif not is_admin():
        if request_elevation():
            return 0
        _native_error(
            "需要管理员权限才能安装驱动、服务并写入 Program Files。\n"
            "请在 UAC 提示中点击“是”，或右键以管理员身份运行。"
        )
        return 1

    app = QApplication(sys.argv)
    app.setApplicationName(APP_TITLE)
    app.setOrganizationName("sunshine-lan-streaming")
    apply_theme(app)

    window = MainWindow()
    window.show()

    if smoke_test:
        QTimer.singleShot(300, app.quit)
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
