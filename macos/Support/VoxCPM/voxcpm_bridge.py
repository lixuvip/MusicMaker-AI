#!/usr/bin/env python3
"""Stable JSON bridge for the VoxCPM plugin MVP."""

from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import Any


BRIDGE_VERSION = "1.0"
SUPPORTED_COMMANDS = {
    "health-check",
    "generate-design",
    "generate-clone",
    "recognize-reference-text",
}
EXPECTED_ROOT_FILES = (
    "pyproject.toml",
    "app.py",
    "src/voxcpm/cli.py",
)
DEFAULT_MODEL_IDENTIFIER = "openbmb/VoxCPM2"
DEFAULT_DEVICE = "mps" if sys.platform == "darwin" else "auto"


class BridgeError(Exception):
    def __init__(self, code: str, message: str, details: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = details or {}


@dataclass
class BridgeRequest:
    version: str
    request_id: str | None
    command: str
    arguments: dict[str, Any]


def build_response(
    *,
    request: BridgeRequest | None,
    ok: bool,
    runtime_state: str,
    details: dict[str, Any] | None = None,
    error: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "version": BRIDGE_VERSION,
        "request_id": request.request_id if request else None,
        "command": request.command if request else None,
        "ok": ok,
        "runtime_state": runtime_state,
        "details": details or {},
        "error": error,
    }


def parse_request(raw_text: str) -> BridgeRequest:
    try:
        payload = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise BridgeError(
            "invalid_json",
            "Request body must be valid JSON.",
            {"line": exc.lineno, "column": exc.colno},
        ) from exc

    if not isinstance(payload, dict):
        raise BridgeError("invalid_request", "Request envelope must be a JSON object.")

    version = payload.get("version")
    if version != BRIDGE_VERSION:
        raise BridgeError(
            "unsupported_version",
            "Unsupported bridge version.",
            {"expected": BRIDGE_VERSION, "received": version},
        )

    command = payload.get("command")
    if not isinstance(command, str) or not command:
        raise BridgeError("invalid_request", "Request envelope must include a command string.")
    if command not in SUPPORTED_COMMANDS:
        raise BridgeError(
            "unsupported_command",
            "Unsupported command.",
            {"supported_commands": sorted(SUPPORTED_COMMANDS), "received": command},
        )

    arguments = payload.get("arguments", {})
    if not isinstance(arguments, dict):
        raise BridgeError("invalid_request", "Request arguments must be a JSON object.")

    request_id = payload.get("request_id")
    if request_id is not None and not isinstance(request_id, str):
        raise BridgeError("invalid_request", "request_id must be a string when provided.")

    return BridgeRequest(
        version=version,
        request_id=request_id,
        command=command,
        arguments=arguments,
    )


def handle_health_check(request: BridgeRequest) -> dict[str, Any]:
    root_value = request.arguments.get("voxcpm_root", "")
    root_path = Path(root_value).expanduser() if isinstance(root_value, str) and root_value else None

    if root_path is None:
        return build_response(
            request=request,
            ok=False,
            runtime_state="unconfigured",
            details={
                "voxcpm_root": root_value,
                "exists": False,
                "required_files": _required_files_status(None),
            },
            error={
                "code": "missing_voxcpm_root",
                "message": "Provide arguments.voxcpm_root to validate the VoxCPM checkout.",
            },
        )

    root_exists = root_path.exists() and root_path.is_dir()
    required_files = _required_files_status(root_path if root_exists else None)
    missing_files = [relative_path for relative_path, info in required_files.items() if not info["exists"]]

    if not root_exists:
        runtime_state = "unconfigured"
        ok = False
        error = {
            "code": "missing_root_directory",
            "message": "The provided VoxCPM root directory does not exist.",
        }
    elif missing_files:
        runtime_state = "unconfigured"
        ok = False
        error = {
            "code": "missing_required_files",
            "message": "The VoxCPM root is missing required files.",
            "details": {"missing_files": missing_files},
        }
    else:
        runtime_state = "ready"
        ok = True
        error = None

    return build_response(
        request=request,
        ok=ok,
        runtime_state=runtime_state,
        details={
            "voxcpm_root": str(root_path),
            "exists": root_exists,
            "required_files": required_files,
        },
        error=error,
    )


def handle_generate_clone(request: BridgeRequest) -> dict[str, Any]:
    validated = _validate_generation_request(
        request,
        required_fields=(
            "voxcpm_root",
            "reference_audio_path",
            "target_text",
        ),
    )
    output_audio_path = _build_output_audio_path(
        output_directory=validated["output_directory"],
        mode="quick_clone",
        request_id=request.request_id,
    )
    cli_arguments = [
        "clone",
        "--text",
        validated["target_text"],
        "--reference-audio",
        validated["reference_audio_path"],
        "--output",
        str(output_audio_path),
        "--hf-model-id",
        validated["model_identifier"],
        "--device",
        validated["device"],
    ]
    control_instruction = validated.get("control_instruction", "")
    if control_instruction:
        cli_arguments.extend(["--control", control_instruction])

    invocation = _invoke_voxcpm_cli(
        voxcpm_root=Path(validated["voxcpm_root"]),
        cli_arguments=cli_arguments,
        output_audio_path=output_audio_path,
    )

    return build_response(
        request=request,
        ok=True,
        runtime_state="ready",
        details={
            "status": "completed",
            "mode": "quickClone",
            "voxcpm_root": validated["voxcpm_root"],
            "model_identifier": validated["model_identifier"],
            "device": validated["device"],
            "reference_audio_path": validated["reference_audio_path"],
            "target_text": validated["target_text"],
            "control_instruction": control_instruction,
            "output_directory": str(validated["output_directory"]),
            "output_audio_path": str(output_audio_path),
            "cli_command": invocation["command"],
            "cli_stderr": invocation["stderr"],
        },
    )


def handle_generate_design(request: BridgeRequest) -> dict[str, Any]:
    validated = _validate_generation_request(
        request,
        required_fields=(
            "voxcpm_root",
            "target_text",
            "design_description",
        ),
    )
    output_audio_path = _build_output_audio_path(
        output_directory=validated["output_directory"],
        mode="voice_design",
        request_id=request.request_id,
    )
    control_instruction = _combine_design_control(
        validated["design_description"],
        validated.get("control_instruction", ""),
    )
    cli_arguments = [
        "design",
        "--text",
        validated["target_text"],
        "--output",
        str(output_audio_path),
        "--hf-model-id",
        validated["model_identifier"],
        "--device",
        validated["device"],
        "--control",
        control_instruction,
    ]
    invocation = _invoke_voxcpm_cli(
        voxcpm_root=Path(validated["voxcpm_root"]),
        cli_arguments=cli_arguments,
        output_audio_path=output_audio_path,
    )

    return build_response(
        request=request,
        ok=True,
        runtime_state="ready",
        details={
            "status": "completed",
            "mode": "voiceDesign",
            "voxcpm_root": validated["voxcpm_root"],
            "model_identifier": validated["model_identifier"],
            "device": validated["device"],
            "target_text": validated["target_text"],
            "design_description": validated["design_description"],
            "control_instruction": validated.get("control_instruction", ""),
            "output_directory": str(validated["output_directory"]),
            "output_audio_path": str(output_audio_path),
            "cli_command": invocation["command"],
            "cli_stderr": invocation["stderr"],
        },
    )


def _required_files_status(root_path: Path | None) -> dict[str, dict[str, Any]]:
    status: dict[str, dict[str, Any]] = {}
    for relative_path in EXPECTED_ROOT_FILES:
        absolute_path = root_path / relative_path if root_path else None
        status[relative_path] = {
            "exists": bool(absolute_path and absolute_path.is_file()),
            "path": str(absolute_path) if absolute_path else None,
        }
    return status


def _validate_generation_request(
    request: BridgeRequest,
    *,
    required_fields: tuple[str, ...],
) -> dict[str, Any]:
    arguments = request.arguments
    voxcpm_root = _validated_root(arguments)
    output_directory = _validated_output_directory(arguments)
    target_text = _required_string(arguments, "target_text")
    model_identifier = _optional_string(arguments, "model_identifier") or DEFAULT_MODEL_IDENTIFIER
    control_instruction = _optional_string(arguments, "control_instruction") or ""
    device = _optional_string(arguments, "device") or os.environ.get("VOXCPM_DEVICE") or DEFAULT_DEVICE

    validated: dict[str, Any] = {
        "voxcpm_root": str(voxcpm_root),
        "output_directory": output_directory,
        "target_text": target_text,
        "model_identifier": model_identifier,
        "control_instruction": control_instruction,
        "device": device,
    }

    if "reference_audio_path" in required_fields:
        reference_audio_path = _validated_reference_audio(arguments)
        validated["reference_audio_path"] = str(reference_audio_path)

    if "design_description" in required_fields:
        validated["design_description"] = _required_string(arguments, "design_description")

    return validated


def _validated_root(arguments: dict[str, Any]) -> Path:
    root_value = _required_string(arguments, "voxcpm_root")
    root_path = Path(root_value).expanduser()
    if not root_path.is_dir():
        raise BridgeError(
            "missing_root_directory",
            "The provided VoxCPM root directory does not exist.",
            {"field": "voxcpm_root", "path": str(root_path)},
        )

    required_files = _required_files_status(root_path)
    missing_files = [relative_path for relative_path, info in required_files.items() if not info["exists"]]
    if missing_files:
        raise BridgeError(
            "missing_required_files",
            "The VoxCPM root is missing required files.",
            {"field": "voxcpm_root", "missing_files": missing_files},
        )
    return root_path


def _validated_output_directory(arguments: dict[str, Any]) -> Path:
    output_value = _optional_string(arguments, "output_directory")
    if output_value:
        output_directory = Path(output_value).expanduser()
    else:
        output_directory = Path.cwd() / "voxcpm_outputs"
    output_directory.mkdir(parents=True, exist_ok=True)
    return output_directory


def _validated_reference_audio(arguments: dict[str, Any]) -> Path:
    reference_value = _required_string(arguments, "reference_audio_path")
    reference_path = Path(reference_value).expanduser()
    if not reference_path.is_file():
        raise BridgeError(
            "missing_reference_audio",
            "Reference audio file does not exist.",
            {"field": "reference_audio_path", "path": str(reference_path)},
        )
    return reference_path


def _required_string(arguments: dict[str, Any], field: str) -> str:
    value = _optional_string(arguments, field)
    if value:
        return value
    raise BridgeError(
        f"missing_{field}",
        f"Provide arguments.{field} as a non-empty string.",
        {"field": field},
    )


def _optional_string(arguments: dict[str, Any], field: str) -> str | None:
    value = arguments.get(field)
    if value is None:
        return None
    if not isinstance(value, str):
        raise BridgeError(
            "invalid_request",
            f"arguments.{field} must be a string when provided.",
            {"field": field},
        )
    stripped = value.strip()
    return stripped or None


def _build_output_audio_path(*, output_directory: Path, mode: str, request_id: str | None) -> Path:
    slug_source = request_id or mode
    slug = re.sub(r"[^A-Za-z0-9_-]+", "-", slug_source).strip("-") or mode
    filename = f"{mode}_{slug}.wav"
    return output_directory / filename


def _combine_design_control(design_description: str, control_instruction: str) -> str:
    control_instruction = control_instruction.strip()
    if not control_instruction:
        return design_description
    return f"{design_description}; {control_instruction}"


def _invoke_voxcpm_cli(
    *,
    voxcpm_root: Path,
    cli_arguments: list[str],
    output_audio_path: Path,
) -> dict[str, str]:
    if os.environ.get("VOXCPM_BRIDGE_TEST_MODE") == "stub_success":
        _synthesize_stub_audio(output_audio_path)
        return {
            "command": "stubbed voxcpm invocation",
            "stderr": "stubbed successful generation",
        }

    command = [sys.executable, "-m", "voxcpm.cli", *cli_arguments]
    environment = os.environ.copy()
    source_path = voxcpm_root / "src"
    existing_pythonpath = environment.get("PYTHONPATH", "")
    environment["PYTHONPATH"] = (
        f"{source_path}{os.pathsep}{existing_pythonpath}"
        if existing_pythonpath
        else str(source_path)
    )
    environment.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    environment.setdefault("VOXCPM_BATCH_SIZE", "8")
    environment.setdefault("VOXCPM_COMPILE", "1")
    environment.setdefault("OMP_NUM_THREADS", "8")
    environment.setdefault("MKL_NUM_THREADS", "8")

    completed = subprocess.run(
        command,
        cwd=voxcpm_root,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    stderr_text = completed.stderr.strip()
    stdout_text = completed.stdout.strip()

    if completed.returncode != 0:
        failure_text = stderr_text or stdout_text or f"Exit code {completed.returncode}"
        raise BridgeError(
            "voxcpm_cli_failed",
            f"VoxCPM CLI 执行失败：{failure_text}",
            {
                "exit_code": completed.returncode,
                "command": " ".join(command),
            },
        )

    if not output_audio_path.is_file():
        raise BridgeError(
            "missing_output_audio",
            "VoxCPM CLI 已完成，但没有找到输出音频文件。",
            {
                "expected_output_audio_path": str(output_audio_path),
                "command": " ".join(command),
            },
        )

    return {
        "command": " ".join(command),
        "stderr": stderr_text or stdout_text,
    }


def _synthesize_stub_audio(output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    sample_rate = 16000
    duration_seconds = 0.5
    amplitude = 12000
    base_frequency = 220
    frame_count = int(sample_rate * duration_seconds)

    with wave.open(str(output_path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)

        frames = bytearray()
        for index in range(frame_count):
            progress = index / sample_rate
            sample = int(
                amplitude
                * math.sin(2 * math.pi * base_frequency * progress)
                * (0.5 + 0.5 * math.sin(2 * math.pi * 2 * progress))
            )
            frames.extend(sample.to_bytes(2, byteorder="little", signed=True))
        handle.writeframes(bytes(frames))


def dispatch(request: BridgeRequest) -> dict[str, Any]:
    if request.command == "health-check":
        return handle_health_check(request)
    if request.command == "generate-clone":
        return handle_generate_clone(request)
    if request.command == "generate-design":
        return handle_generate_design(request)
    raise BridgeError(
        "not_implemented",
        f"Command '{request.command}' is not implemented yet.",
        {"command": request.command},
    )


def main() -> int:
    raw_text = sys.stdin.read()
    request: BridgeRequest | None = None

    try:
        request = parse_request(raw_text)
        response = dispatch(request)
    except BridgeError as exc:
        response = build_response(
            request=request,
            ok=False,
            runtime_state="error",
            details=exc.details,
            error={"code": exc.code, "message": exc.message},
        )
    except Exception as exc:  # pragma: no cover - last-resort contract guard
        response = build_response(
            request=request,
            ok=False,
            runtime_state="error",
            details={},
            error={"code": "internal_error", "message": str(exc)},
        )

    json.dump(response, sys.stdout, ensure_ascii=True, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
