import base64
import binascii
import json
import os
import random
import shutil
import subprocess
import sys
import threading
import urllib.error
import urllib.request
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from tkinter import BooleanVar, IntVar, StringVar, Tk, filedialog, messagebox
from tkinter import ttk
from typing import Optional, Tuple
import tkinter as tk


APP_NAME = "MusicMaker-AI"
SEED_MIN = 0
SEED_MAX = 1_000_000
MAX_BATCH_COUNT = 10

TRANSCODE_BITRATES = [128, 192, 256, 320]
TRANSCODE_SAMPLE_RATES = [22050, 32000, 44100, 48000]
TRANSCODE_FORMATS = ["mp3", "wav", "flac", "aac", "ogg"]
DEFAULT_TRANSCODE_BITRATE = 320
DEFAULT_TRANSCODE_SAMPLE_RATE = 44100
DEFAULT_TRANSCODE_FORMAT = "mp3"


@dataclass
class HistoryItem:
    id: str
    created_at: str
    base_url: str
    model: str
    prompt: str
    lyrics: str
    output_format: str
    audio_format: str
    sample_rate: int
    bitrate: int
    lyrics_optimizer: bool
    aigc_watermark: bool
    instrumental: bool
    reference_audio_url: str
    seed: int
    directory_path: str
    file_path: str
    remote_url: str
    is_favorite: bool = False
    category: str = ""
    batch_id: str = ""
    batch_index: int = 1
    batch_total: int = 1


@dataclass
class TranscodeItem:
    id: str
    source_path: str
    source_filename: str
    target_bitrate: int
    target_sample_rate: int
    target_format: str
    status: str = "等待转码"
    output_path: str = ""
    error_message: str = ""
    auto_added: bool = False


def app_data_dir() -> Path:
    root = os.environ.get("APPDATA")
    if root:
        path = Path(root) / APP_NAME
    else:
        path = Path.home() / ".minimax_music_maker"
    path.mkdir(parents=True, exist_ok=True)
    return path


def output_dir() -> Path:
    music = Path.home() / "Music"
    path = music / "MusicMaker-AI"
    path.mkdir(parents=True, exist_ok=True)
    return path


def transcode_output_dir() -> Path:
    path = output_dir() / "Transcoded"
    path.mkdir(parents=True, exist_ok=True)
    return path


def config_path() -> Path:
    return app_data_dir() / "config.json"


def history_path() -> Path:
    return output_dir() / "history.json"


def normalize_text(value: str) -> str:
    return value.replace("\\n", "\n")


def http_json(url: str, api_key: str, payload: dict) -> dict:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            body = response.read()
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(body or f"HTTP {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc

    try:
        return json.loads(body.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"MiniMax 返回内容不是 JSON：{body[:300]!r}") from exc


def extract_audio(response: dict) -> Tuple[Optional[bytes], str]:
    base_resp = response.get("base_resp") or {}
    status_code = base_resp.get("status_code")
    if status_code not in (None, 0):
        raise RuntimeError(base_resp.get("status_msg") or f"MiniMax 错误：{status_code}")

    data = response.get("data") or {}
    audio_value = data.get("audio") or response.get("audio") or ""
    remote_url = data.get("audio_url") or response.get("audio_url") or ""

    if isinstance(audio_value, str) and audio_value.startswith(("http://", "https://")):
        return None, audio_value
    if isinstance(remote_url, str) and remote_url.startswith(("http://", "https://")):
        return None, remote_url
    if isinstance(audio_value, str) and audio_value:
        try:
            return binascii.unhexlify(audio_value), ""
        except (binascii.Error, ValueError):
            try:
                return base64.b64decode(audio_value, validate=True), ""
            except binascii.Error as exc:
                raise RuntimeError("响应里有 audio 字段，但既不是 URL、hex，也不是 base64。") from exc

    raise RuntimeError("MiniMax 响应缺少 audio 或 audio_url。")


def download(url: str) -> bytes:
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=240) as response:
        return response.read()


def open_path(path: Path) -> None:
    if sys.platform.startswith("win"):
        os.startfile(str(path))  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])


def reveal_file(path: Path) -> None:
    if sys.platform.startswith("win"):
        subprocess.Popen(["explorer", "/select,", str(path)])
    else:
        open_path(path.parent)


def _ffmpeg_try_paths() -> Optional[str]:
    candidates = []
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", "")
        if meipass:
            candidates.append(os.path.join(meipass, "ffmpeg.exe"))

    try:
        script_dir = os.path.dirname(os.path.abspath(sys.argv[0]))
    except Exception:
        script_dir = os.getcwd()
    candidates.append(os.path.join(script_dir, "ffmpeg.exe"))
    candidates.append("ffmpeg")

    if sys.platform.startswith("win"):
        candidates += [
            os.path.expandvars(r"%ProgramFiles%\ffmpeg\bin\ffmpeg.exe"),
            os.path.expandvars(r"%ProgramFiles(x86)%\ffmpeg\bin\ffmpeg.exe"),
            r"C:\ffmpeg\bin\ffmpeg.exe",
            r"C:\tools\ffmpeg\bin\ffmpeg.exe",
        ]
    for candidate in candidates:
        try:
            result = subprocess.run(
                [candidate, "-version"],
                capture_output=True,
                timeout=10,
                **({"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform.startswith("win") else {}),
            )
            if result.returncode == 0:
                return candidate
        except Exception:
            continue
    return None


def find_ffmpeg(configured: str = "") -> Optional[str]:
    if configured:
        try:
            result = subprocess.run(
                [configured, "-version"],
                capture_output=True,
                timeout=10,
                **({"creationflags": subprocess.CREATE_NO_WINDOW} if sys.platform.startswith("win") else {}),
            )
            if result.returncode == 0:
                return configured
        except Exception:
            pass
    return _ffmpeg_try_paths()


class App(Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_NAME)
        self.geometry("1240x860")
        self.minsize(1080, 760)

        self.history: list[HistoryItem] = []
        self.filtered_history_ids: list[str] = []
        self.selected_history: Optional[HistoryItem] = None
        self.last_file: Optional[Path] = None
        self.last_remote_url = ""
        self.last_seed: Optional[int] = None
        self.selected_module = StringVar(value="music_generation")

        self.base_url = StringVar(value="https://api.minimaxi.com")
        self.api_key = StringVar(value="")
        self.model = StringVar(value="music-2.6-free")
        self.output_format = StringVar(value="url")
        self.audio_format = StringVar(value="mp3")
        self.sample_rate = IntVar(value=44100)
        self.bitrate = IntVar(value=256000)
        self.lyrics_optimizer = BooleanVar(value=True)
        self.instrumental = BooleanVar(value=False)
        self.aigc_watermark = BooleanVar(value=False)
        self.random_seed = BooleanVar(value=True)
        self.manual_seed = StringVar(value="")
        self.reference_audio_url = StringVar(value="")
        self.batch_count = IntVar(value=1)
        self.auto_play_after_generation = BooleanVar(value=False)
        self.category_input = StringVar(value="")
        self.status = StringVar(value="准备就绪")
        self.batch_status = StringVar(value="单首生成模式")

        self.history_search = StringVar(value="")
        self.history_category_filter = StringVar(value="全部分类")
        self.history_favorites_only = BooleanVar(value=False)

        self.category_library: list[str] = []

        self.transcode_items: list[TranscodeItem] = []
        self.tc_bitrate = IntVar(value=DEFAULT_TRANSCODE_BITRATE)
        self.tc_sample_rate = IntVar(value=DEFAULT_TRANSCODE_SAMPLE_RATE)
        self.tc_format = StringVar(value=DEFAULT_TRANSCODE_FORMAT)
        self.tc_output_dir = StringVar(value=str(transcode_output_dir()))
        self.tc_ffmpeg_path = StringVar(value="")
        self.tc_status = StringVar(value="准备就绪")

        self.load_config()
        self.load_history()
        self.build_ui()
        self.refresh_all_history_views()
        self.refresh_result()
        self.protocol("WM_DELETE_WINDOW", self.on_close)

    def build_ui(self) -> None:
        root = ttk.Frame(self, padding=(0, 0, 0, 0))
        root.pack(fill=tk.BOTH, expand=True)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(0, weight=1)

        shell = ttk.PanedWindow(root, orient=tk.HORIZONTAL)
        shell.grid(row=0, column=0, sticky="nsew")

        nav = ttk.Frame(shell, padding=10)
        self.module_host = ttk.Frame(shell)
        shell.add(nav, weight=0)
        shell.add(self.module_host, weight=1)

        self.build_module_nav(nav)
        self._build_active_module("music_generation")

        footer = ttk.Frame(root, padding=(12, 8))
        footer.grid(row=1, column=0, sticky="ew")
        footer.columnconfigure(0, weight=1)
        ttk.Separator(footer, orient=tk.HORIZONTAL).grid(row=0, column=0, columnspan=2, sticky="ew", pady=(0, 8))
        self.footer_info = StringVar(value="播放器将在后续版本升级为内置控制器；当前使用系统默认播放器打开音频。")
        ttk.Label(footer, textvariable=self.footer_info, foreground="#666666").grid(row=1, column=0, sticky="w")
        ttk.Button(footer, text="播放当前歌曲", command=self.play_file).grid(row=1, column=1, sticky="e")

    def build_module_nav(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        ttk.Label(parent, text="工具", font=("Segoe UI", 14, "bold")).grid(row=0, column=0, sticky="w", pady=(0, 10))

        self.module_tree = ttk.Treeview(parent, show="tree", selectmode="browse", height=10)
        self.module_tree.grid(row=1, column=0, sticky="nsew")
        self.module_tree.insert("", tk.END, iid="music_generation", text="音乐生成", open=True)
        self.module_tree.insert("", tk.END, iid="audio_transcode", text="音频转码", open=True)
        self.module_tree.insert("", tk.END, iid="history", text="历史记录", open=True)
        self.module_tree.selection_set("music_generation")
        self.module_tree.bind("<<TreeviewSelect>>", self.on_module_select)

        self.module_subtitle = ttk.Label(parent, text="MiniMax /v1/music_generation", foreground="#666666")
        self.module_subtitle.grid(row=2, column=0, sticky="w", pady=(8, 0))

    def on_module_select(self, _event=None) -> None:
        selected = self.module_tree.selection()
        if not selected:
            return
        module_id = selected[0]
        if module_id == self.selected_module.get():
            return
        self.selected_module.set(module_id)
        self._build_active_module(module_id)

        subtitles = {
            "music_generation": "MiniMax /v1/music_generation",
            "audio_transcode": "音频格式与码率转换",
            "history": "历史、收藏与分类管理",
        }
        self.module_subtitle.configure(text=subtitles.get(module_id, ""))

    def _build_active_module(self, module_id: str) -> None:
        for child in self.module_host.winfo_children():
            child.destroy()
        if module_id == "music_generation":
            self.build_music_generation_module(self.module_host)
        elif module_id == "audio_transcode":
            self.build_transcode_module(self.module_host)
        elif module_id == "history":
            self.build_history_module(self.module_host)

    def build_music_generation_module(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(0, weight=1)

        module = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        module.grid(row=0, column=0, sticky="nsew")

        left = ttk.Frame(module, padding=12)
        right = ttk.Frame(module, padding=12)
        module.add(left, weight=0)
        module.add(right, weight=1)

        self.build_settings(left)
        self.build_generator(right)

    def build_settings(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)

        api = ttk.LabelFrame(parent, text="MiniMax 配置", padding=10)
        api.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        api.columnconfigure(0, weight=1)
        ttk.Label(api, text="BASE_URL").grid(row=0, column=0, sticky="w")
        ttk.Entry(api, textvariable=self.base_url).grid(row=1, column=0, sticky="ew", pady=(2, 8))
        ttk.Label(api, text="API Key").grid(row=2, column=0, sticky="w")
        ttk.Entry(api, textvariable=self.api_key, show="*").grid(row=3, column=0, sticky="ew")

        model_box = ttk.LabelFrame(parent, text="模型", padding=10)
        model_box.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        model_box.columnconfigure(0, weight=1)
        ttk.Combobox(
            model_box,
            textvariable=self.model,
            values=["music-2.6-free", "music-2.6", "music-2.6-cover"],
            state="readonly",
        ).grid(row=0, column=0, sticky="ew")
        ttk.Label(model_box, text="参考音频 URL").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(model_box, textvariable=self.reference_audio_url).grid(row=2, column=0, sticky="ew")

        output = ttk.LabelFrame(parent, text="输出", padding=10)
        output.grid(row=2, column=0, sticky="ew", pady=(0, 10))
        output.columnconfigure(1, weight=1)
        self.combo(output, "返回", self.output_format, ["url", "hex"], 0)
        self.combo(output, "格式", self.audio_format, ["mp3", "wav"], 1)
        self.combo(output, "采样率", self.sample_rate, [32000, 44100], 2)
        self.combo(output, "比特率", self.bitrate, [128000, 256000], 3)

        options = ttk.LabelFrame(parent, text="选项", padding=10)
        options.grid(row=3, column=0, sticky="ew", pady=(0, 10))
        ttk.Checkbutton(options, text="歌词优化", variable=self.lyrics_optimizer).pack(anchor="w")
        ttk.Checkbutton(options, text="纯音乐", variable=self.instrumental).pack(anchor="w")
        ttk.Checkbutton(options, text="添加 AI 水印", variable=self.aigc_watermark).pack(anchor="w")
        ttk.Checkbutton(
            options,
            text="生成后自动播放（批量生成时自动禁用）",
            variable=self.auto_play_after_generation,
        ).pack(anchor="w", pady=(6, 0))

        batch_box = ttk.LabelFrame(parent, text="批量生成", padding=10)
        batch_box.grid(row=4, column=0, sticky="ew", pady=(0, 10))
        batch_box.columnconfigure(1, weight=1)
        ttk.Label(batch_box, text="本次生成数量").grid(row=0, column=0, sticky="w", padx=(0, 8))
        ttk.Spinbox(batch_box, from_=1, to=MAX_BATCH_COUNT, textvariable=self.batch_count, width=8).grid(
            row=0, column=1, sticky="w"
        )
        ttk.Label(
            batch_box,
            text="Windows 端按顺序逐首提交，方便稳定记录进度与结果。",
            foreground="#666666",
        ).grid(row=1, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Label(batch_box, textvariable=self.batch_status, foreground="#1f5f9f").grid(
            row=2, column=0, columnspan=2, sticky="w", pady=(8, 0)
        )

        category_box = ttk.LabelFrame(parent, text="分类", padding=10)
        category_box.grid(row=5, column=0, sticky="ew", pady=(0, 10))
        category_box.columnconfigure(0, weight=1)
        self.category_combo = ttk.Combobox(category_box, textvariable=self.category_input, values=self.category_library)
        self.category_combo.grid(row=0, column=0, sticky="ew")
        ttk.Label(
            category_box,
            text="可选择已有分类，也可以直接输入新分类，生成后会自动保留到历史中。",
            foreground="#666666",
        ).grid(row=1, column=0, sticky="w", pady=(6, 0))

        seed = ttk.LabelFrame(parent, text="Seed", padding=10)
        seed.grid(row=6, column=0, sticky="ew")
        seed.columnconfigure(0, weight=1)
        ttk.Checkbutton(seed, text="每次随机", variable=self.random_seed).grid(row=0, column=0, sticky="w")
        ttk.Entry(seed, textvariable=self.manual_seed).grid(row=1, column=0, sticky="ew", pady=(6, 4))
        ttk.Label(seed, text="手动 Seed 范围：0 到 1000000").grid(row=2, column=0, sticky="w")

    def combo(self, parent: ttk.Frame, label: str, variable, values: list, row: int) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 8), pady=3)
        ttk.Combobox(parent, textvariable=variable, values=values, state="readonly").grid(
            row=row, column=1, sticky="ew", pady=3
        )

    def build_generator(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(5, weight=1)

        ttk.Label(parent, text="音乐生成", font=("Segoe UI", 18, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(parent, text="音乐要求可用自然语言描述；歌词框建议只放歌词正文。").grid(
            row=1, column=0, sticky="w", pady=(0, 10)
        )

        ttk.Label(parent, text="音乐要求").grid(row=2, column=0, sticky="w")
        self.prompt_text = tk.Text(parent, height=8, wrap="word", undo=True)
        self.prompt_text.grid(row=3, column=0, sticky="nsew", pady=(2, 10))

        ttk.Label(parent, text="歌词").grid(row=4, column=0, sticky="w")
        self.lyrics_text = tk.Text(parent, height=10, wrap="word", undo=True)
        self.lyrics_text.grid(row=5, column=0, sticky="nsew", pady=(2, 10))

        actions = ttk.Frame(parent)
        actions.grid(row=6, column=0, sticky="ew", pady=(0, 10))
        actions.columnconfigure(5, weight=1)
        ttk.Button(actions, text="生成音乐", command=self.generate).grid(row=0, column=0, padx=(0, 8))
        ttk.Button(actions, text="播放文件", command=self.play_file).grid(row=0, column=1, padx=(0, 8))
        ttk.Button(actions, text="打开文件夹", command=self.open_folder).grid(row=0, column=2, padx=(0, 8))
        ttk.Button(actions, text="定位文件", command=self.reveal_current_file).grid(row=0, column=3, padx=(0, 8))
        ttk.Button(actions, text="复制文件", command=self.copy_current_file).grid(row=0, column=4, padx=(0, 8))
        ttk.Label(actions, textvariable=self.status).grid(row=0, column=5, sticky="e")

        self.result_text = tk.Text(parent, height=8, wrap="word")
        self.result_text.grid(row=7, column=0, sticky="ew", pady=(0, 10))
        self.result_text.configure(state="disabled")

    def build_transcode_module(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(0, weight=1)

        module = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        module.grid(row=0, column=0, sticky="nsew")

        left = ttk.Frame(module, padding=12)
        right = ttk.Frame(module, padding=12)
        module.add(left, weight=0)
        module.add(right, weight=1)

        self._build_transcode_settings(left)
        self._build_transcode_main(right)

    def _build_transcode_settings(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)

        params = ttk.LabelFrame(parent, text="转码参数", padding=10)
        params.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        params.columnconfigure(1, weight=1)
        self.combo(params, "比特率 (KBps)", self.tc_bitrate, TRANSCODE_BITRATES, 0)
        self.combo(params, "采样率 (Hz)", self.tc_sample_rate, TRANSCODE_SAMPLE_RATES, 1)
        self.combo(params, "输出格式", self.tc_format, TRANSCODE_FORMATS, 2)

        out_box = ttk.LabelFrame(parent, text="输出目录", padding=10)
        out_box.grid(row=1, column=0, sticky="ew", pady=(0, 10))
        out_box.columnconfigure(0, weight=1)
        ttk.Entry(out_box, textvariable=self.tc_output_dir).grid(row=0, column=0, sticky="ew")
        ttk.Button(out_box, text="浏览", command=self._transcode_browse_output).grid(row=0, column=1, padx=(6, 0))

        ffmpeg_box = ttk.LabelFrame(parent, text="FFmpeg", padding=10)
        ffmpeg_box.grid(row=2, column=0, sticky="ew")
        ffmpeg_box.columnconfigure(0, weight=1)
        detected = find_ffmpeg()
        if detected and not self.tc_ffmpeg_path.get():
            self.tc_ffmpeg_path.set(detected)
        ttk.Entry(ffmpeg_box, textvariable=self.tc_ffmpeg_path).grid(row=0, column=0, sticky="ew")
        ttk.Button(ffmpeg_box, text="检测", command=self._transcode_detect_ffmpeg).grid(row=0, column=1, padx=(6, 0))
        ttk.Label(
            ffmpeg_box,
            text="需要系统已安装 FFmpeg\n下载：https://ffmpeg.org/download.html",
            foreground="#666666",
        ).grid(row=1, column=0, columnspan=2, sticky="w", pady=(4, 0))

    def _build_transcode_main(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(2, weight=1)

        ttk.Label(parent, text="音频转码", font=("Segoe UI", 18, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(
            parent,
            text="生成完的音乐会自动加入列表；也可手动添加文件或整个文件夹。",
        ).grid(row=1, column=0, sticky="w", pady=(0, 10))

        self.transcode_tree = ttk.Treeview(
            parent,
            columns=("source", "info", "target", "status"),
            show="headings",
            height=12,
        )
        for col, title, width in [
            ("source", "源文件", 260),
            ("info", "原始信息", 140),
            ("target", "目标参数", 190),
            ("status", "状态", 120),
        ]:
            self.transcode_tree.heading(col, text=title)
            self.transcode_tree.column(col, width=width, anchor="w")
        self.transcode_tree.grid(row=2, column=0, sticky="nsew", pady=(0, 10))

        actions = ttk.Frame(parent)
        actions.grid(row=3, column=0, sticky="ew", pady=(0, 8))
        actions.columnconfigure(7, weight=1)
        ttk.Button(actions, text="添加文件", command=self._transcode_add_files).grid(row=0, column=0, padx=(0, 6))
        ttk.Button(actions, text="添加文件夹", command=self._transcode_add_folder).grid(row=0, column=1, padx=(0, 6))
        ttk.Button(actions, text="从历史加入", command=self._transcode_add_selected_history).grid(row=0, column=2, padx=(0, 6))
        ttk.Button(actions, text="移除选中", command=self._transcode_remove_selected).grid(row=0, column=3, padx=(0, 6))
        ttk.Button(actions, text="清空列表", command=self._transcode_clear_list).grid(row=0, column=4, padx=(0, 6))
        ttk.Button(actions, text="开始转码", command=self._transcode_start).grid(row=0, column=5, padx=(0, 6))
        ttk.Button(actions, text="打开输出目录", command=self._transcode_open_output).grid(row=0, column=6, padx=(0, 6))
        ttk.Label(actions, textvariable=self.tc_status).grid(row=0, column=7, sticky="e")

        self._refresh_transcode_tree()

    def build_history_module(self, parent: ttk.Frame) -> None:
        parent.columnconfigure(0, weight=1)
        parent.rowconfigure(1, weight=1)

        header = ttk.Frame(parent, padding=12)
        header.grid(row=0, column=0, sticky="ew")
        header.columnconfigure(5, weight=1)
        ttk.Label(header, text="历史记录", font=("Segoe UI", 18, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(header, text="搜索").grid(row=1, column=0, sticky="w", pady=(8, 0))
        search_entry = ttk.Entry(header, textvariable=self.history_search)
        search_entry.grid(row=1, column=1, sticky="ew", padx=(6, 12), pady=(8, 0))
        search_entry.bind("<KeyRelease>", lambda _e: self.refresh_all_history_views())

        ttk.Label(header, text="分类").grid(row=1, column=2, sticky="w", pady=(8, 0))
        self.history_category_combo = ttk.Combobox(
            header,
            textvariable=self.history_category_filter,
            values=self.history_filter_values(),
            state="readonly",
            width=16,
        )
        self.history_category_combo.grid(row=1, column=3, sticky="w", padx=(6, 12), pady=(8, 0))
        self.history_category_combo.bind("<<ComboboxSelected>>", lambda _e: self.refresh_all_history_views())
        ttk.Checkbutton(
            header,
            text="仅看收藏",
            variable=self.history_favorites_only,
            command=self.refresh_all_history_views,
        ).grid(row=1, column=4, sticky="w", pady=(8, 0))
        ttk.Button(header, text="清空历史", command=self.clear_history).grid(row=1, column=5, sticky="e", pady=(8, 0))

        body = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        body.grid(row=1, column=0, sticky="nsew", padx=12, pady=(0, 12))

        left = ttk.Frame(body)
        right = ttk.Frame(body)
        body.add(left, weight=1)
        body.add(right, weight=1)

        left.columnconfigure(0, weight=1)
        left.rowconfigure(0, weight=1)
        right.columnconfigure(0, weight=1)
        right.rowconfigure(0, weight=1)

        self.history_tree = ttk.Treeview(
            left,
            columns=("fav", "time", "category", "seed", "file"),
            show="headings",
            height=16,
        )
        for column, title, width in [
            ("fav", "收藏", 55),
            ("time", "时间", 135),
            ("category", "分类", 120),
            ("seed", "Seed", 80),
            ("file", "文件", 280),
        ]:
            self.history_tree.heading(column, text=title)
            self.history_tree.column(column, width=width, anchor="w")
        self.history_tree.grid(row=0, column=0, sticky="nsew")
        self.history_tree.bind("<<TreeviewSelect>>", self.on_history_select)

        self.history_detail = tk.Text(right, height=18, wrap="word")
        self.history_detail.grid(row=0, column=0, sticky="nsew")

        actions = ttk.Frame(right)
        actions.grid(row=1, column=0, sticky="ew", pady=(10, 0))
        for index in range(3):
            actions.columnconfigure(index, weight=1)
        ttk.Button(actions, text="加载参数", command=self.load_selected_history_parameters).grid(row=0, column=0, padx=(0, 6), sticky="ew")
        ttk.Button(actions, text="播放文件", command=self.play_selected_history).grid(row=0, column=1, padx=(0, 6), sticky="ew")
        ttk.Button(actions, text="加入转码", command=self._transcode_add_selected_history).grid(row=0, column=2, sticky="ew")
        ttk.Button(actions, text="收藏/取消收藏", command=self.toggle_selected_history_favorite).grid(row=1, column=0, padx=(0, 6), pady=(8, 0), sticky="ew")
        ttk.Button(actions, text="修改分类", command=self.prompt_update_selected_history_category).grid(row=1, column=1, padx=(0, 6), pady=(8, 0), sticky="ew")
        ttk.Button(actions, text="定位文件", command=self.reveal_selected_history_file).grid(row=1, column=2, pady=(8, 0), sticky="ew")

        self.refresh_all_history_views()

    def history_filter_values(self) -> list[str]:
        values = ["全部分类"]
        values.extend(self.category_library)
        return values

    def ensure_category(self, category: str) -> str:
        normalized = category.strip()
        if not normalized:
            return ""
        if normalized not in self.category_library:
            self.category_library.append(normalized)
            self.category_library.sort(key=str.lower)
        return normalized

    def sync_category_controls(self) -> None:
        values = self.category_library
        if hasattr(self, "category_combo"):
            self.category_combo.configure(values=values)
        if hasattr(self, "history_category_combo"):
            self.history_category_combo.configure(values=self.history_filter_values())
            if self.history_category_filter.get() not in self.history_filter_values():
                self.history_category_filter.set("全部分类")

    def refresh_all_history_views(self) -> None:
        self.sync_category_controls()
        self.refresh_history()
        self.refresh_history_detail()
        self.refresh_result()

    def filtered_history(self) -> list[HistoryItem]:
        keyword = self.history_search.get().strip().lower()
        category = self.history_category_filter.get().strip()
        favorites_only = self.history_favorites_only.get()

        rows: list[HistoryItem] = []
        for item in self.history:
            if favorites_only and not item.is_favorite:
                continue
            if category and category != "全部分类" and item.category != category:
                continue
            if keyword:
                haystack = " ".join(
                    [
                        item.created_at,
                        item.prompt,
                        item.lyrics,
                        item.model,
                        item.category,
                        Path(item.file_path).name,
                    ]
                ).lower()
                if keyword not in haystack:
                    continue
            rows.append(item)
        return rows

    def _refresh_transcode_tree(self) -> None:
        if not hasattr(self, "transcode_tree"):
            return
        tree = self.transcode_tree
        tree.delete(*tree.get_children())
        for item in self.transcode_items:
            src = Path(item.source_path)
            original_info = src.suffix.upper().lstrip(".") if src.suffix else ""
            bitrate_k = item.target_bitrate // 1000
            sample_k = item.target_sample_rate / 1000
            target_desc = f"{bitrate_k}KBps / {sample_k:.1f}KHz / {item.target_format.upper()}"
            prefix = "[自动] " if item.auto_added else ""
            tree.insert("", tk.END, iid=item.id, values=(prefix + item.source_filename, original_info, target_desc, item.status))

    def _transcode_add_files(self) -> None:
        paths = filedialog.askopenfilenames(
            title="选择音频文件",
            filetypes=[("音频文件", "*.mp3 *.wav *.flac *.aac *.ogg *.m4a *.wma"), ("所有文件", "*.*")],
        )
        for path in paths:
            self._add_transcode_item(Path(path), auto=False)

    def _transcode_add_folder(self) -> None:
        folder = filedialog.askdirectory(title="选择文件夹")
        if not folder:
            return
        extensions = {".mp3", ".wav", ".flac", ".aac", ".ogg", ".m4a", ".wma"}
        for path in Path(folder).iterdir():
            if path.is_file() and path.suffix.lower() in extensions:
                self._add_transcode_item(path, auto=False)

    def _transcode_add_selected_history(self) -> None:
        item = self.selected_history
        if not item:
            self.tc_status.set("请先在历史记录中选中一首歌")
            return
        self._add_transcode_item(Path(item.file_path), auto=False)

    def _add_transcode_item(self, source: Path, auto: bool = False) -> None:
        if not source.exists():
            return
        for existing in self.transcode_items:
            if Path(existing.source_path) == source:
                if auto:
                    self.tc_status.set(f"已在转码列表中：{source.name}")
                return
        item = TranscodeItem(
            id=str(uuid.uuid4()),
            source_path=str(source),
            source_filename=source.name,
            target_bitrate=self.tc_bitrate.get() * 1000,
            target_sample_rate=self.tc_sample_rate.get(),
            target_format=self.tc_format.get(),
            auto_added=auto,
        )
        self.transcode_items.append(item)
        self._refresh_transcode_tree()
        self.tc_status.set(f"{'已自动添加' if auto else '已添加'}：{source.name}")

    def _transcode_remove_selected(self) -> None:
        if not hasattr(self, "transcode_tree"):
            return
        selected = self.transcode_tree.selection()
        if not selected:
            return
        ids = set(selected)
        self.transcode_items = [item for item in self.transcode_items if item.id not in ids]
        self._refresh_transcode_tree()

    def _transcode_clear_list(self) -> None:
        if not self.transcode_items:
            return
        if not messagebox.askyesno(APP_NAME, "确定清空转码列表？"):
            return
        self.transcode_items = []
        self._refresh_transcode_tree()
        self.tc_status.set("列表已清空")

    def _transcode_browse_output(self) -> None:
        folder = filedialog.askdirectory(title="选择转码输出目录")
        if folder:
            self.tc_output_dir.set(folder)

    def _transcode_detect_ffmpeg(self) -> None:
        path = find_ffmpeg()
        if path:
            self.tc_ffmpeg_path.set(path)
            self.tc_status.set(f"检测到 FFmpeg：{path}")
        else:
            self.tc_ffmpeg_path.set("")
            self.tc_status.set("未找到 FFmpeg，请手动填写路径")
            messagebox.showwarning(APP_NAME, "未在系统中检测到 FFmpeg。\n请从 https://ffmpeg.org/download.html 下载安装后重试。")

    def _transcode_open_output(self) -> None:
        out = Path(self.tc_output_dir.get())
        out.mkdir(parents=True, exist_ok=True)
        open_path(out)

    def _transcode_start(self) -> None:
        ffmpeg = find_ffmpeg(self.tc_ffmpeg_path.get().strip())
        if not ffmpeg:
            messagebox.showerror(APP_NAME, "未找到 FFmpeg，请先安装或手动填写路径。")
            return
        self.tc_ffmpeg_path.set(ffmpeg)

        pending = [item for item in self.transcode_items if item.status in ("等待转码", "失败")]
        if not pending:
            self.tc_status.set("没有需要转码的文件")
            return

        self.tc_status.set(f"准备转码 {len(pending)} 个文件")
        thread = threading.Thread(target=self._transcode_worker, args=(pending, ffmpeg), daemon=True)
        thread.start()

    def _transcode_worker(self, items: list[TranscodeItem], ffmpeg: str) -> None:
        out_dir = Path(self.tc_output_dir.get())
        out_dir.mkdir(parents=True, exist_ok=True)

        for index, item in enumerate(items, start=1):
            item.status = "转码中…"
            self.after(0, self._refresh_transcode_tree)
            self.after(0, lambda m=f"转码中 {index}/{len(items)}：{item.source_filename}": self.tc_status.set(m))
            try:
                src = Path(item.source_path)
                stem = src.stem
                bitrate_k = item.target_bitrate // 1000
                sample_rate = item.target_sample_rate
                fmt = item.target_format
                out_name = f"{stem}_{bitrate_k}kbps_{sample_rate}hz.{fmt}"
                out_path = out_dir / out_name
                cmd = [ffmpeg, "-y", "-i", str(src), "-ar", str(sample_rate)]
                if fmt == "wav":
                    cmd += ["-acodec", "pcm_s16le"]
                elif fmt == "flac":
                    cmd += ["-acodec", "flac"]
                else:
                    cmd += ["-b:a", f"{bitrate_k}k"]
                cmd.append(str(out_path))

                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=300,
                    creationflags=subprocess.CREATE_NO_WINDOW if sys.platform.startswith("win") else 0,
                )
                if result.returncode != 0:
                    raise RuntimeError(result.stderr.strip() or f"exit code {result.returncode}")
                item.output_path = str(out_path)
                item.status = "已完成"
            except Exception as exc:
                item.status = "失败"
                item.error_message = str(exc)
            finally:
                self.after(0, self._refresh_transcode_tree)
        self.after(0, lambda: self.tc_status.set("转码完成"))

    def load_config(self) -> None:
        try:
            data = json.loads(config_path().read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            return
        self.base_url.set(data.get("base_url", self.base_url.get()))
        self.api_key.set(data.get("api_key", ""))
        self.model.set(data.get("model", self.model.get()))
        self.output_format.set(data.get("output_format", self.output_format.get()))
        self.audio_format.set(data.get("audio_format", self.audio_format.get()))
        self.sample_rate.set(data.get("sample_rate", self.sample_rate.get()))
        self.bitrate.set(data.get("bitrate", self.bitrate.get()))
        self.lyrics_optimizer.set(data.get("lyrics_optimizer", self.lyrics_optimizer.get()))
        self.instrumental.set(data.get("instrumental", self.instrumental.get()))
        self.aigc_watermark.set(data.get("aigc_watermark", self.aigc_watermark.get()))
        self.random_seed.set(data.get("random_seed", self.random_seed.get()))
        self.manual_seed.set(data.get("manual_seed", self.manual_seed.get()))
        self.reference_audio_url.set(data.get("reference_audio_url", self.reference_audio_url.get()))
        self.batch_count.set(int(data.get("batch_count", self.batch_count.get())))
        self.auto_play_after_generation.set(bool(data.get("auto_play_after_generation", self.auto_play_after_generation.get())))
        self.category_input.set(data.get("category_input", self.category_input.get()))
        self.category_library = list(dict.fromkeys(data.get("category_library", [])))
        self.tc_bitrate.set(data.get("tc_bitrate", self.tc_bitrate.get()))
        self.tc_sample_rate.set(data.get("tc_sample_rate", self.tc_sample_rate.get()))
        self.tc_format.set(data.get("tc_format", self.tc_format.get()))
        self.tc_output_dir.set(data.get("tc_output_dir", self.tc_output_dir.get()))
        self.tc_ffmpeg_path.set(data.get("tc_ffmpeg_path", self.tc_ffmpeg_path.get()))

    def save_config(self) -> None:
        data = {
            "base_url": self.base_url.get(),
            "api_key": self.api_key.get(),
            "model": self.model.get(),
            "output_format": self.output_format.get(),
            "audio_format": self.audio_format.get(),
            "sample_rate": self.sample_rate.get(),
            "bitrate": self.bitrate.get(),
            "lyrics_optimizer": self.lyrics_optimizer.get(),
            "instrumental": self.instrumental.get(),
            "aigc_watermark": self.aigc_watermark.get(),
            "random_seed": self.random_seed.get(),
            "manual_seed": self.manual_seed.get(),
            "reference_audio_url": self.reference_audio_url.get(),
            "batch_count": self.batch_count.get(),
            "auto_play_after_generation": self.auto_play_after_generation.get(),
            "category_input": self.category_input.get(),
            "category_library": self.category_library,
            "tc_bitrate": self.tc_bitrate.get(),
            "tc_sample_rate": self.tc_sample_rate.get(),
            "tc_format": self.tc_format.get(),
            "tc_output_dir": self.tc_output_dir.get(),
            "tc_ffmpeg_path": self.tc_ffmpeg_path.get(),
        }
        config_path().write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    def load_history(self) -> None:
        try:
            rows = json.loads(history_path().read_text(encoding="utf-8"))
        except (FileNotFoundError, json.JSONDecodeError):
            self.history = []
            return

        self.history = []
        for row in rows:
            row.setdefault("is_favorite", False)
            row.setdefault("category", "")
            row.setdefault("batch_id", "")
            row.setdefault("batch_index", 1)
            row.setdefault("batch_total", 1)
            item = HistoryItem(**row)
            self.history.append(item)
            if item.category:
                self.ensure_category(item.category)

    def save_history(self) -> None:
        history_path().write_text(
            json.dumps([asdict(item) for item in self.history], ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def make_seed(self) -> int:
        if self.random_seed.get():
            return random.randint(SEED_MIN, SEED_MAX)
        try:
            seed = int(self.manual_seed.get().strip())
        except ValueError as exc:
            raise RuntimeError("Seed 必须是 0 到 1000000 之间的整数。") from exc
        if not SEED_MIN <= seed <= SEED_MAX:
            raise RuntimeError("Seed 必须是 0 到 1000000 之间的整数。")
        return seed

    def collect_payload(self, seed: int) -> Tuple[dict, str, str]:
        prompt = normalize_text(self.prompt_text.get("1.0", tk.END).strip())
        lyrics = normalize_text(self.lyrics_text.get("1.0", tk.END).strip())
        if not prompt:
            raise RuntimeError("请填写音乐要求。")
        if not self.instrumental.get() and not lyrics:
            raise RuntimeError("MiniMax 要求 lyrics 字段。请填写歌词，或选择纯音乐。")

        submitted_lyrics = lyrics if lyrics else "[instrumental]"
        payload = {
            "model": self.model.get(),
            "prompt": prompt,
            "lyrics": submitted_lyrics,
            "output_format": self.output_format.get(),
            "audio_setting": {
                "sample_rate": int(self.sample_rate.get()),
                "bitrate": int(self.bitrate.get()),
                "format": self.audio_format.get(),
            },
            "lyrics_optimizer": bool(self.lyrics_optimizer.get()),
            "aigc_watermark": bool(self.aigc_watermark.get()),
            "is_instrumental": bool(self.instrumental.get()),
            "seed": seed,
        }
        reference_audio_url = self.reference_audio_url.get().strip()
        if self.model.get() == "music-2.6-cover" and reference_audio_url:
            payload["audio_url"] = reference_audio_url
        return payload, prompt, submitted_lyrics

    def generate(self) -> None:
        count = max(1, min(MAX_BATCH_COUNT, int(self.batch_count.get())))
        self.batch_count.set(count)
        if count > 1 and self.auto_play_after_generation.get():
            self.auto_play_after_generation.set(False)
            self.footer_info.set("批量生成时已自动关闭“生成后自动播放”，避免打断当前工作。")
        self.save_config()
        thread = threading.Thread(target=self.generate_worker, daemon=True)
        thread.start()

    def generate_worker(self) -> None:
        try:
            batch_total = max(1, min(MAX_BATCH_COUNT, int(self.batch_count.get())))
            category = self.ensure_category(self.category_input.get())
            self.after(0, self.sync_category_controls)
            batch_id = str(uuid.uuid4()) if batch_total > 1 else ""
            self.set_batch_status(f"准备生成 {batch_total} 首歌曲")

            for index in range(1, batch_total + 1):
                seed = self.make_seed()
                payload, prompt, lyrics = self.collect_payload(seed)
                self.set_status(f"正在提交到 MiniMax... {index}/{batch_total}，Seed: {seed}")
                self.set_batch_status(f"生成中 {index}/{batch_total}")
                endpoint = self.base_url.get().strip().rstrip("/") + "/v1/music_generation"
                response = http_json(endpoint, self.api_key.get().strip(), payload)
                audio_data, remote_url = extract_audio(response)
                self.set_status(f"正在保存音频... {index}/{batch_total}")
                if audio_data is None:
                    audio_data = download(remote_url)

                suffix = f"_{index:02d}" if batch_total > 1 else ""
                filename = f"minimax-{datetime.now().strftime('%Y%m%d-%H%M%S')}{suffix}.{self.audio_format.get()}"
                file_path = output_dir() / filename
                file_path.write_bytes(audio_data)

                item = self.append_history(
                    file_path=file_path,
                    remote_url=remote_url,
                    seed=seed,
                    prompt=prompt,
                    lyrics=lyrics,
                    category=category,
                    batch_id=batch_id,
                    batch_index=index,
                    batch_total=batch_total,
                )
                self.after(0, lambda row=item: self.apply_generated_result(row))
                self.after(0, lambda path=file_path: self._add_transcode_item(path, auto=True))

            self.set_batch_status(f"批量生成完成，共 {batch_total} 首")
        except Exception as exc:
            self.after(0, lambda: self.fail(str(exc)))

    def append_history(
        self,
        file_path: Path,
        remote_url: str,
        seed: int,
        prompt: str,
        lyrics: str,
        category: str,
        batch_id: str,
        batch_index: int,
        batch_total: int,
    ) -> HistoryItem:
        item = HistoryItem(
            id=str(uuid.uuid4()),
            created_at=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            base_url=self.base_url.get().strip(),
            model=self.model.get(),
            prompt=prompt,
            lyrics=lyrics,
            output_format=self.output_format.get(),
            audio_format=self.audio_format.get(),
            sample_rate=int(self.sample_rate.get()),
            bitrate=int(self.bitrate.get()),
            lyrics_optimizer=bool(self.lyrics_optimizer.get()),
            aigc_watermark=bool(self.aigc_watermark.get()),
            instrumental=bool(self.instrumental.get()),
            reference_audio_url=self.reference_audio_url.get().strip(),
            seed=seed,
            directory_path=str(file_path.parent),
            file_path=str(file_path),
            remote_url=remote_url,
            category=category,
            batch_id=batch_id,
            batch_index=batch_index,
            batch_total=batch_total,
        )
        self.history.insert(0, item)
        self.save_history()
        return item

    def apply_generated_result(self, item: HistoryItem) -> None:
        self.selected_history = item
        self.last_file = Path(item.file_path)
        self.last_remote_url = item.remote_url
        self.last_seed = item.seed
        self.set_status(f"生成完成：{Path(item.file_path).name}，Seed: {item.seed}")
        self.footer_info.set(f"当前歌曲：{Path(item.file_path).name}")
        self.refresh_all_history_views()
        if self.auto_play_after_generation.get() and item.batch_total == 1:
            self.play_file()

    def refresh_result(self) -> None:
        if not hasattr(self, "result_text"):
            return
        self.result_text.configure(state="normal")
        self.result_text.delete("1.0", tk.END)
        if self.last_file:
            self.result_text.insert(tk.END, f"文件：{self.last_file}\n")
        if self.last_seed is not None:
            self.result_text.insert(tk.END, f"Seed：{self.last_seed}\n")
        if self.selected_history and self.selected_history.category:
            self.result_text.insert(tk.END, f"分类：{self.selected_history.category}\n")
        if self.selected_history and self.selected_history.batch_total > 1:
            self.result_text.insert(
                tk.END,
                f"批量进度：第 {self.selected_history.batch_index} 首 / 共 {self.selected_history.batch_total} 首\n",
            )
        if self.last_remote_url:
            self.result_text.insert(tk.END, f"临时链接：{self.last_remote_url}\n")
        self.result_text.configure(state="disabled")

    def refresh_history(self) -> None:
        if not hasattr(self, "history_tree"):
            return
        self.history_tree.delete(*self.history_tree.get_children())
        visible_rows = self.filtered_history()
        self.filtered_history_ids = [item.id for item in visible_rows]
        for item in visible_rows:
            favorite_mark = "★" if item.is_favorite else ""
            file_name = Path(item.file_path).name
            if item.batch_total > 1:
                file_name = f"[{item.batch_index}/{item.batch_total}] {file_name}"
            self.history_tree.insert(
                "",
                tk.END,
                iid=item.id,
                values=(favorite_mark, item.created_at, item.category or "-", item.seed, file_name),
            )
        if self.selected_history and self.selected_history.id in self.filtered_history_ids:
            self.history_tree.selection_set(self.selected_history.id)

    def on_history_select(self, _event=None) -> None:
        if not hasattr(self, "history_tree"):
            return
        selected = self.history_tree.selection()
        if not selected:
            return
        item_id = selected[0]
        item = next((row for row in self.history if row.id == item_id), None)
        if not item:
            return
        self.selected_history = item
        self.last_file = Path(item.file_path)
        self.last_remote_url = item.remote_url
        self.last_seed = item.seed
        self.footer_info.set(f"当前歌曲：{Path(item.file_path).name}")
        self.refresh_result()
        self.refresh_history_detail()

    def refresh_history_detail(self) -> None:
        if not hasattr(self, "history_detail"):
            return
        self.history_detail.configure(state="normal")
        self.history_detail.delete("1.0", tk.END)
        item = self.selected_history
        if item:
            detail = (
                f"时间：{item.created_at}\n"
                f"收藏：{'是' if item.is_favorite else '否'}\n"
                f"分类：{item.category or '-'}\n"
                f"模型：{item.model}\n"
                f"Seed：{item.seed}\n"
                f"输出：{item.output_format} / {item.audio_format}\n"
                f"音频：{item.sample_rate} Hz / {item.bitrate} bps\n"
                f"批量：第 {item.batch_index} 首 / 共 {item.batch_total} 首\n"
                f"选项：{'纯音乐' if item.instrumental else '含歌词'}，"
                f"{'歌词优化' if item.lyrics_optimizer else '不优化歌词'}，"
                f"{'AI 水印' if item.aigc_watermark else '无 AI 水印'}\n"
                f"目录：{item.directory_path}\n"
                f"文件：{item.file_path}\n"
                f"远端链接：{item.remote_url}\n\n"
                f"音乐要求：\n{item.prompt}\n\n"
                f"歌词：\n{item.lyrics}\n"
            )
            self.history_detail.insert(tk.END, detail)
        self.history_detail.configure(state="disabled")

    def load_selected_history_parameters(self) -> None:
        item = self.selected_history
        if not item:
            return
        self.model.set(item.model)
        self.output_format.set(item.output_format)
        self.audio_format.set(item.audio_format)
        self.sample_rate.set(item.sample_rate)
        self.bitrate.set(item.bitrate)
        self.lyrics_optimizer.set(item.lyrics_optimizer)
        self.instrumental.set(item.instrumental)
        self.aigc_watermark.set(item.aigc_watermark)
        self.random_seed.set(False)
        self.manual_seed.set(str(item.seed))
        self.reference_audio_url.set(item.reference_audio_url)
        self.category_input.set(item.category)
        if hasattr(self, "prompt_text"):
            self.prompt_text.delete("1.0", tk.END)
            self.prompt_text.insert(tk.END, item.prompt)
        if hasattr(self, "lyrics_text"):
            self.lyrics_text.delete("1.0", tk.END)
            self.lyrics_text.insert(tk.END, item.lyrics)
        self.module_tree.selection_set("music_generation")
        self.selected_module.set("music_generation")
        self._build_active_module("music_generation")
        self.set_status(f"已加载历史参数，Seed: {item.seed}")

    def clear_history(self) -> None:
        if not self.history:
            return
        if not messagebox.askyesno(APP_NAME, "确定清空历史记录？不会删除音频文件。"):
            return
        self.history = []
        self.selected_history = None
        self.save_history()
        self.refresh_all_history_views()
        self.set_status("历史记录已清空")

    def toggle_selected_history_favorite(self) -> None:
        item = self.selected_history
        if not item:
            return
        item.is_favorite = not item.is_favorite
        self.save_history()
        self.refresh_all_history_views()
        self.set_status("已更新收藏状态")

    def prompt_update_selected_history_category(self) -> None:
        item = self.selected_history
        if not item:
            return
        dialog = tk.Toplevel(self)
        dialog.title("修改分类")
        dialog.transient(self)
        dialog.grab_set()
        dialog.geometry("360x140")
        dialog.columnconfigure(0, weight=1)

        value = StringVar(value=item.category)
        ttk.Label(dialog, text="输入新的分类名称").grid(row=0, column=0, sticky="w", padx=12, pady=(12, 6))
        combo = ttk.Combobox(dialog, textvariable=value, values=self.category_library)
        combo.grid(row=1, column=0, sticky="ew", padx=12)

        buttons = ttk.Frame(dialog)
        buttons.grid(row=2, column=0, sticky="e", padx=12, pady=12)

        def submit() -> None:
            item.category = self.ensure_category(value.get())
            self.category_input.set(item.category)
            self.save_history()
            self.save_config()
            self.refresh_all_history_views()
            dialog.destroy()
            self.set_status("已更新分类")

        ttk.Button(buttons, text="取消", command=dialog.destroy).pack(side=tk.RIGHT)
        ttk.Button(buttons, text="保存", command=submit).pack(side=tk.RIGHT, padx=(0, 8))

    def play_selected_history(self) -> None:
        item = self.selected_history
        if not item:
            return
        file_path = Path(item.file_path)
        if file_path.exists():
            self.last_file = file_path
            self.footer_info.set(f"当前歌曲：{file_path.name}")
            open_path(file_path)

    def reveal_selected_history_file(self) -> None:
        item = self.selected_history
        if not item:
            return
        file_path = Path(item.file_path)
        if file_path.exists():
            reveal_file(file_path)

    def play_file(self) -> None:
        if self.last_file and self.last_file.exists():
            open_path(self.last_file)

    def open_folder(self) -> None:
        if self.last_file and self.last_file.exists():
            open_path(self.last_file.parent)

    def reveal_current_file(self) -> None:
        if self.last_file and self.last_file.exists():
            reveal_file(self.last_file)

    def copy_current_file(self) -> None:
        if not self.last_file or not self.last_file.exists():
            return
        if sys.platform.startswith("win"):
            ps_path = str(self.last_file).replace("'", "''")
            script = (
                "Add-Type -AssemblyName System.Windows.Forms; "
                "$files = New-Object System.Collections.Specialized.StringCollection; "
                f"[void]$files.Add('{ps_path}'); "
                "[System.Windows.Forms.Clipboard]::SetFileDropList($files)"
            )
            result = subprocess.run(["powershell", "-NoProfile", "-Command", script], check=False)
            if result.returncode != 0:
                subprocess.run(f'echo {str(self.last_file)}|clip', shell=True, check=False)
        else:
            target = filedialog.asksaveasfilename(initialfile=self.last_file.name)
            if target:
                shutil.copyfile(self.last_file, target)
        self.set_status("已复制文件")

    def fail(self, message: str) -> None:
        self.set_status("生成失败")
        self.set_batch_status("批量任务中断")
        messagebox.showerror("生成失败", message)

    def set_status(self, message: str) -> None:
        self.after(0, lambda: self.status.set(message))

    def set_batch_status(self, message: str) -> None:
        self.after(0, lambda: self.batch_status.set(message))

    def on_close(self) -> None:
        self.save_config()
        self.destroy()


if __name__ == "__main__":
    App().mainloop()
