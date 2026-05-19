# VoxCPM Bridge

`voxcpm_bridge.py` is the MVP JSON bridge between the macOS app and a local VoxCPM checkout. In the current phase it provides both a stable JSON contract and a real CLI-backed execution path for `快速克隆` and `声音设计`.

## Request envelope

Send a single JSON object on `stdin`:

```json
{
  "version": "1.0",
  "request_id": "example-001",
  "command": "health-check",
  "arguments": {
    "voxcpm_root": "/path/to/VoxCPM"
  }
}
```

Fields:

- `version`: must be `"1.0"`
- `request_id`: optional caller-generated correlation id
- `command`: one of `health-check`, `generate-design`, `generate-clone`, `recognize-reference-text`
- `arguments`: command-specific object

## Response envelope

The bridge always writes one JSON object to `stdout`:

```json
{
  "version": "1.0",
  "request_id": "example-001",
  "command": "health-check",
  "ok": true,
  "runtime_state": "ready",
  "details": {
    "voxcpm_root": "/path/to/VoxCPM",
    "exists": true,
    "required_files": {
      "pyproject.toml": {
        "exists": true,
        "path": "/path/to/VoxCPM/pyproject.toml"
      }
    }
  },
  "error": null
}
```

Fields:

- `ok`: success flag for the command
- `runtime_state`: stable high-level state such as `ready`, `unconfigured`, or `error`
- `details`: structured command result payload
- `error`: `null` on success, otherwise an object with `code` and `message`

## Current commands

### `health-check`

Validates `arguments.voxcpm_root` and checks for these expected files:

- `pyproject.toml`
- `app.py`
- `src/voxcpm/cli.py`

If any are missing, the bridge returns `ok: false` and `runtime_state: "unconfigured"` with per-file details.

### `generate-design`

Runs the local VoxCPM CLI in `design` mode and writes a single output WAV file.

Expected arguments:

- `voxcpm_root`
- `target_text`
- `design_description`
- `output_directory` (optional)
- `model_identifier` (optional, defaults to `openbmb/VoxCPM2`)
- `device` (optional, defaults to `mps` on macOS)
- `control_instruction` (optional)

The bridge combines `design_description` and `control_instruction` before forwarding them to `voxcpm design --control ...`.

### `generate-clone`

Runs the local VoxCPM CLI in `clone` mode and writes a single output WAV file.

Expected arguments:

- `voxcpm_root`
- `reference_audio_path`
- `target_text`
- `output_directory` (optional)
- `model_identifier` (optional, defaults to `openbmb/VoxCPM2`)
- `device` (optional, defaults to `mps` on macOS)
- `control_instruction` (optional)

### Current MVP boundary

- The bridge invokes `python -m voxcpm.cli ...` with `PYTHONPATH` pointed at the selected VoxCPM checkout's `src/`.
- It mirrors the practical runtime assumptions from the user's `start.sh` by defaulting `PYTORCH_ENABLE_MPS_FALLBACK=1` and the related VoxCPM environment variables when they are not already set.
- `recognize-reference-text` is still reserved for a later phase and remains unimplemented.

## Lightweight verification

Use the standard library test runner in minimal environments:

```bash
python3 -m unittest macos/Support/VoxCPM/tests/test_voxcpm_bridge.py -v
```

The unit tests run the bridge in a stubbed-success mode for deterministic contract verification. Real VoxCPM model execution should be validated through the manual smoke checklist.

## Local example

```bash
printf '%s\n' '{
  "version": "1.0",
  "request_id": "manual-health-check",
  "command": "health-check",
  "arguments": {
    "voxcpm_root": "/path/to/VoxCPM"
  }
}' | python3 macos/Support/VoxCPM/voxcpm_bridge.py
```
