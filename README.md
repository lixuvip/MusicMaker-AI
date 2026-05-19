# MusicMaker-AI

MusicMaker-AI 是一个面向创作流程的桌面工具，提供两项核心能力：

- 使用 MiniMax Music Generation API 生成音乐
- 对生成后的音频或本地音频进行转码处理

当前 macOS 版本还在继续扩展第三类能力：

- 以插件模块形式接入本地 VoxCPM，用于声音克隆与声音设计

项目同时维护 macOS 与 Windows 两个桌面版本，目标是让两端在能力上尽量保持一致，同时保留各自平台更自然的交互方式。

当前版本的音乐生成能力主要基于 MiniMax Music Generation API。也特别感谢 MiniMax 提供了现阶段稳定、易于接入的音乐生成模型能力，让 MusicMaker-AI 可以先把创作、试听、筛选与转码这套桌面工作流跑通。后续版本会在保持现有体验的基础上，逐步兼容更多模型与服务 API，给创作流程留出更大的选择空间。

## 当前发布状态

- 当前推荐版本：`v1.0.1`
- GitHub Releases：
  [MusicMaker-AI Releases](https://github.com/lixuvip/MusicMaker-AI/releases)

- macOS：已提供可下载发布包
- Windows：源码与打包脚本已就绪，`.exe` 可在 Windows 环境中构建后追加到 Release

当前版本已接入 MiniMax 音乐生成能力，后续会继续扩展更多模型 API、更多服务接口与本地工具能力，方便在同一个桌面应用中完成生成、试听、分类、筛选与转码等工作流。

## v1.0.1 重点更新

- 新增“项目”维度管理，生成前即可切换当前项目，并按项目归档批次结果
- 历史记录升级为项目 / 轮次 / 选中状态 / 分类多条件筛选
- 历史详情支持备注、移动到项目、分类调整、推进下一轮、标记已选中、淘汰
- 详情区的“展开 / 收起”标题栏已扩大点击范围，点击文字区域也可操作
- macOS 增加更稳定的空格键播放 / 暂停快捷键
- Windows 代码结构继续向 macOS 能力靠齐，便于后续统一迭代

## 后续规划

- 声音克隆能力：后续会评估以独立模块方式接入，和当前音乐生成、转码、历史整理并列，避免把主生成页继续堆复杂
- 独立作词模块：计划把歌词撰写、润色、版本管理从当前生成表单里拆出来，做成更适合反复编辑和对比的单独工作区
- 多模型兼容层：在保持 MiniMax 现有工作流稳定的前提下，逐步增加更多模型 API 的接入能力
- 双端能力继续对齐：macOS 先验证，Windows 再同步补齐，尽量保持相同的功能语义和整理流程

## 功能概览

- 音乐生成
- 声音克隆插件模块
- 音乐参数配置：模型、输出格式、音频格式、采样率、比特率
- 歌词输入与纯音乐模式
- Seed 随机或手动控制
- 单次生成数量可选 `1-10`
- 批量生成进度反馈
- 项目管理与批次归档
- 本地历史记录
- 分类列表复用与筛选
- 按项目、轮次、选中状态、分类筛选
- 历史备注与项目内整理
- 本地音频播放、打开目录、定位文件
- 全局播放器、播放进度条、拖拽播放
- macOS 空格键播放 / 暂停
- 音频转码模块
- macOS VoxCPM 插件设置、环境验证、快速克隆、声音设计、任务历史
- 生成结果自动加入转码列表
- 手动添加本地音频文件到转码列表
- 自动检测 `ffmpeg`，并支持在 macOS 上一键安装
- 调整目标比特率与采样率
- 输出转码文件并保留任务状态

## 下载

- 最新版本：
  [v1.0.1](https://github.com/lixuvip/MusicMaker-AI/releases/tag/v1.0.1)

- 首个版本：
  [v1.0.0](https://github.com/lixuvip/MusicMaker-AI/releases/tag/v1.0.0)

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

如果要使用 `声音克隆` 模块，还需要准备一个本地 VoxCPM checkout，并在 app 内配置：

- VoxCPM 根目录
- 可运行 VoxCPM 的 Python 命令

当前插件式接入方式说明：

- 以 MusicMaker-AI 原生 UI 展示，不嵌入 VoxCPM 原网页界面
- 通过 Python bridge 调用本地 VoxCPM CLI
- 不强依赖固定绝对路径，可按设备分别配置不同的 VoxCPM 目录

### Windows

直接运行源码：

```bash
cd windows
py musicmaker_ai_windows.py
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
- Windows 版打包脚本会自动探测 `py` / `python` / `python3`，并在需要时下载 `ffmpeg.exe` 一起带入 exe。
- 两端功能尽量保持一致，但界面实现会分别遵循各自平台的技术栈。

## 子项目说明

- [macos/README.md](./macos/README.md)
- [windows/README.md](./windows/README.md)

## 适用场景

- 快速验证音乐创意提示词
- 在本地沉淀生成历史与参数
- 将生成结果进一步转为目标比特率与采样率
- 维护一套双端桌面工具代码库，服务后续扩展
