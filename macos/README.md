# MusicMaker-AI

一个原生 macOS 小工具，当前包含音乐生成、声音克隆与音频整理相关能力。

## 运行

```bash
cd macos
chmod +x build_app.sh
./build_app.sh
open build/MusicMaker-AI.app
```

## 使用

1. 在左侧填写 `BASE_URL`，默认是 `https://api.minimaxi.com`。
2. 填写 MiniMax API Key。
3. 输入音乐要求和歌词。
4. Seed 默认每次在 `0...1000000` 内随机；关闭「每次随机」后可以手动指定。
5. 点击「生成音乐」。
6. 生成完成后，最新音频会自动加入「音频转码」列表，可直接按默认 `320 kbps / 44.1 kHz` 或自定义参数执行转码。

### VoxCPM 插件

在 `声音克隆` 模块中，可以把一个本地 VoxCPM 工程作为插件式能力接入当前 app：

1. 打开 `声音克隆 -> 插件设置`
2. 配置本地 VoxCPM 根目录，例如 `/Users/sirius/VoxCPM`
3. 配置可运行 VoxCPM 的 Python 命令
4. 保存后执行运行环境验证
5. 验证通过后，可在 `快速克隆` 与 `声音设计` 中直接提交任务

当前 macOS 版 VoxCPM 插件说明：

- UI 是 MusicMaker-AI 原生 SwiftUI，不直接嵌入 VoxCPM 自带网页界面
- 运行时通过 `macos/Support/VoxCPM/voxcpm_bridge.py` 调用本地 VoxCPM CLI
- 任务历史与配置会单独保存在 `~/Music/MusicMaker-AI/VoxCPMPlugin/`
- 目前已支持 `快速克隆`、`声音设计`、任务历史与结果文件操作

生成完成后，音频会保存到：

```text
~/Music/MusicMaker-AI/
```

生成结果会显示本次使用的 Seed，并提供播放/暂停、打开文件夹、定位文件、复制文件操作。

历史记录保存在：

```text
~/Music/MusicMaker-AI/history.json
```

每条历史包含提交参数、Seed、模型、音频设置、保存目录、文件路径和 MiniMax 临时链接。

转码列表保存在：

```text
~/Music/MusicMaker-AI/transcode-queue.json
```

转码后的音频默认输出到：

```text
~/Music/MusicMaker-AI/Transcoded/
```

## 接口

按 MiniMax 官方文档接入 `POST /v1/music_generation`：

<https://platform.minimaxi.com/docs/api-reference/music-generation>
