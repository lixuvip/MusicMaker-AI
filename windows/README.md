# MusicMaker-AI Windows

Windows 桌面版源码。使用 Python 标准库 + Tkinter 实现，运行功能不依赖第三方 Python 库；打包 `.exe` 时需要 PyInstaller。

**音频转码功能依赖系统安装 [FFmpeg](https://ffmpeg.org/download.html)**（不装也能用音乐生成，只是转码不可用）。

## 直接运行

```bat
cd /d "windows"
python musicmaker_ai_windows.py
```

## 打包 exe

在 Windows 上运行：

```bat
build_windows.bat
```

生成文件：

```text
dist\MusicMaker-AI.exe
```

> FFmpeg 为外部工具，不会打包进 exe。用户需自行安装并确保 `ffmpeg` 在 PATH 中，或在转码页面手动填写路径。

## 功能

### 音乐生成

- 配置 `BASE_URL` 和 API Key
- 自然语言音乐要求
- 歌词输入，自动把字面量 `\n` 转为换行
- 模型、输出格式、音频格式、采样率、比特率
- 纯音乐、歌词优化、AI 水印
- Seed 默认在 `0...1000000` 内随机，也可手动设置
- 生成后保存到 `~/Music/MusicMaker-AI/`
- 播放文件、打开文件夹、定位文件、复制文件
- 历史记录保存到 `~/Music/MusicMaker-AI/history.json`

### 音频转码

- 侧边栏切换到"音频转码"页面
- 生成完的音乐自动加入转码列表
- 支持手动添加单个文件或整个文件夹
- 调整比特率（128/192/256/320 KBps）和采样率（22050/32000/44100/48000 Hz）
- 输出格式可选 mp3 / wav / flac / aac / ogg
- 自定义输出目录，默认 `~/Music/MusicMaker-AI/Transcoded/`
- 自动检测 FFmpeg，也支持手动配置路径
- 转码在后台线程执行，不阻塞 UI
