# VoxCPM Bridge Smoke Test

## Preconditions

- Local VoxCPM checkout is available, for example `/Users/sirius/VoxCPM`
- The checkout can already be run manually with the Python environment you plan to use in MusicMaker-AI
- At least one short reference audio file is available for `快速克隆`

## Configuration

1. Build the macOS app with `./build_app.sh`
2. Open `/Users/sirius/Documents/Codex_Project/MusicMaker-AI-voxcpm-plugin-mvp/macos/build/MusicMaker-AI.app`
3. Enter the `声音克隆` module
4. In `插件设置`, set:
   - `VoxCPM 根目录` -> your local checkout, such as `/Users/sirius/VoxCPM`
   - `Python 命令` -> the interpreter that can run VoxCPM
   - optional output directory if you do not want to use the default Music folder
5. Save the configuration
6. Run `运行环境验证`
7. Confirm the status becomes ready and the required files are all found

## Voice Design

1. Open `声音设计`
2. Fill in:
   - target text
   - design description
   - optional control instruction
3. Start the task
4. Confirm:
   - the task reaches `已完成`
   - an output audio path is recorded
   - `任务历史` shows the new record
   - `打开文件夹` and `定位文件` both work

## Quick Clone

1. Open `快速克隆`
2. Select a local reference audio file
3. Fill in target text
4. Optionally add a control instruction
5. Start the task
6. Confirm:
   - the task reaches `已完成`
   - an output audio path is recorded
   - the output file is playable in Finder/Quick Look

## Persistence

1. Quit the app
2. Relaunch the app
3. Confirm the saved VoxCPM configuration is still present
4. Confirm completed tasks still appear in `任务历史`

## Current MVP boundary

- `快速克隆` and `声音设计` now call the local VoxCPM CLI through the Python bridge
- `参考音频文本识别` is not wired into the native plugin yet
- Runtime success still depends on the selected Python command having all VoxCPM dependencies installed
