# MusicMaker-AI

MusicMaker-AI 是一个同时包含 macOS 与 Windows 桌面端的音乐生成与音频转码项目。它基于 MiniMax Music Generation API 生成音乐，并提供本地音频转码能力，支持把生成结果自动加入转码列表，也支持手动添加本地音频进行处理。

目前直接入了MiniMax，后续持续更新各家接口方便调试使用，尤其给不会变成的同学们便捷实用。

## 功能概览

- 音乐生成
- 音乐参数配置：模型、输出格式、音频格式、采样率、比特率
- 歌词输入与纯音乐模式
- Seed 随机或手动控制
- 本地历史记录
- 本地音频播放、打开目录、定位文件
- 音频转码模块
- 生成结果自动加入转码列表
- 手动添加本地音频文件到转码列表
- 调整目标比特率与采样率
- 输出转码文件并保留任务状态

## 平台实现

- `macos/`
  SwiftUI + Swift Package 桌面版。

- `windows/`
  Python 标准库 + Tkinter 桌面版。

## 仓库结构

```text
MusicMaker-AI/
  README.md
  .gitignore
  macos/
    Package.swift
    build_app.sh
    Assets/
    Sources/
  windows/
    musicmaker_ai_windows.py
    build_windows.bat
    assets/
    README.md
```

## 运行方式

### macOS

```bash
cd macos
chmod +x build_app.sh
./build_app.sh
```

构建完成后可打开：

```text
macos/build/MusicMaker-AI.app
```

### Windows

直接运行源码：

```bash
cd windows
python musicmaker_ai_windows.py
```

如果要打包为 exe，请在 Windows 环境运行：

```bat
cd windows
build_windows.bat
```

生成文件：

```text
windows/dist/MusicMaker-AI.exe
```

## 输出目录

两个桌面端现在统一使用下面这些输出位置：

- 音乐输出目录：`~/Music/MusicMaker-AI/`
- 历史记录：`~/Music/MusicMaker-AI/history.json`
- 转码列表：`~/Music/MusicMaker-AI/transcode-queue.json`
- 转码输出目录：`~/Music/MusicMaker-AI/Transcoded/`

## 平台说明

- macOS 版当前使用本机 `ffmpeg` 执行转码。
- Windows 版支持自动检测 `ffmpeg`，也支持打包时把 `ffmpeg.exe` 一起带入 exe。
- 两端功能尽量保持一致，但界面实现会分别遵循各自平台的技术栈。

## 子项目说明

- [macos/README.md](/Users/sirius/Documents/Codex_Project/MusicMaker-AI/macos/README.md)
- [windows/README.md](/Users/sirius/Documents/Codex_Project/MusicMaker-AI/windows/README.md)

## 后续建议

- 把当前目录最终重命名为 `MusicMaker-AI`
- 在该目录根部初始化 Git 仓库并创建 GitHub 私有仓库
- 后续继续把双端能力保持同步推进
