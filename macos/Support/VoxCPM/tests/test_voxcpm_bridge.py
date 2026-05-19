import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import wave


BRIDGE_PATH = Path(__file__).resolve().parents[1] / "voxcpm_bridge.py"


def run_bridge(payload):
    env = os.environ.copy()
    env["VOXCPM_BRIDGE_TEST_MODE"] = "stub_success"
    result = subprocess.run(
        [sys.executable, str(BRIDGE_PATH)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        check=True,
    )
    return json.loads(result.stdout)


class VoxCPMBridgeTests(unittest.TestCase):
    def test_health_check_reports_missing_required_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "voxcpm-root"
            (root / "src" / "voxcpm").mkdir(parents=True)
            (root / "pyproject.toml").write_text("[project]\nname='voxcpm'\n", encoding="utf-8")

            response = run_bridge(
                {
                    "version": "1.0",
                    "request_id": "test-health-check",
                    "command": "health-check",
                    "arguments": {
                        "voxcpm_root": str(root),
                    },
                }
            )

        self.assertEqual(response["version"], "1.0")
        self.assertEqual(response["request_id"], "test-health-check")
        self.assertEqual(response["command"], "health-check")
        self.assertFalse(response["ok"])
        self.assertEqual(response["runtime_state"], "unconfigured")
        self.assertEqual(response["error"]["code"], "missing_required_files")
        self.assertEqual(
            response["error"]["details"]["missing_files"],
            ["app.py", "src/voxcpm/cli.py"],
        )
        self.assertEqual(response["details"]["voxcpm_root"], str(root))
        self.assertTrue(response["details"]["exists"])
        required_files = response["details"]["required_files"]
        self.assertTrue(required_files["pyproject.toml"]["exists"])
        self.assertFalse(required_files["app.py"]["exists"])
        self.assertFalse(required_files["src/voxcpm/cli.py"]["exists"])

    def test_generate_clone_writes_output_audio_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            root = self._create_valid_voxcpm_root(temp_root / "voxcpm-root")
            output_dir = temp_root / "outputs"
            reference_audio = temp_root / "reference.wav"
            self._write_reference_audio(reference_audio)

            response = run_bridge(
                {
                    "version": "1.0",
                    "request_id": "test-generate-clone",
                    "command": "generate-clone",
                    "arguments": {
                        "voxcpm_root": str(root),
                        "output_directory": str(output_dir),
                        "model_identifier": "openbmb/VoxCPM2",
                        "reference_audio_path": str(reference_audio),
                        "target_text": "请用清晰稳定的口播方式读这段话。",
                        "control_instruction": "保持自然停顿，语气温和。",
                    },
                }
            )

            self.assertTrue(response["ok"])
            self.assertEqual(response["command"], "generate-clone")
            self.assertEqual(response["runtime_state"], "ready")
            self.assertEqual(response["details"]["mode"], "quickClone")
            self.assertEqual(response["details"]["reference_audio_path"], str(reference_audio))
            self.assertEqual(response["details"]["model_identifier"], "openbmb/VoxCPM2")
            self.assertEqual(response["details"]["device"], "mps")
            self.assertTrue(Path(response["details"]["output_audio_path"]).is_file())
            self.assertEqual(response["details"]["cli_command"], "stubbed voxcpm invocation")
            self.assertEqual(response["error"], None)

    def test_generate_design_writes_output_audio_file(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            root = self._create_valid_voxcpm_root(temp_root / "voxcpm-root")
            output_dir = temp_root / "outputs"

            response = run_bridge(
                {
                    "version": "1.0",
                    "request_id": "test-generate-design-success",
                    "command": "generate-design",
                    "arguments": {
                        "voxcpm_root": str(root),
                        "output_directory": str(output_dir),
                        "model_identifier": "openbmb/VoxCPM2",
                        "target_text": "欢迎来到 MusicMaker-AI 的声音设计模块。",
                        "design_description": "沉稳、清晰、偏产品讲解风格。",
                        "control_instruction": "保持亲和力，停顿自然。",
                    },
                }
            )

            self.assertTrue(response["ok"])
            self.assertEqual(response["command"], "generate-design")
            self.assertEqual(response["runtime_state"], "ready")
            self.assertEqual(response["details"]["mode"], "voiceDesign")
            self.assertEqual(response["details"]["design_description"], "沉稳、清晰、偏产品讲解风格。")
            self.assertTrue(Path(response["details"]["output_audio_path"]).is_file())
            self.assertEqual(response["details"]["cli_command"], "stubbed voxcpm invocation")

    def test_generate_design_requires_design_description(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            root = self._create_valid_voxcpm_root(temp_root / "voxcpm-root")
            output_dir = temp_root / "outputs"

            response = run_bridge(
                {
                    "version": "1.0",
                    "request_id": "test-generate-design",
                    "command": "generate-design",
                    "arguments": {
                        "voxcpm_root": str(root),
                        "output_directory": str(output_dir),
                        "target_text": "为产品介绍视频生成一段旁白。",
                        "design_description": "",
                    },
                }
            )

            self.assertFalse(response["ok"])
            self.assertEqual(response["command"], "generate-design")
            self.assertEqual(response["runtime_state"], "error")
            self.assertEqual(response["error"]["code"], "missing_design_description")
            self.assertEqual(response["details"]["field"], "design_description")

    def _create_valid_voxcpm_root(self, root: Path) -> Path:
        (root / "src" / "voxcpm").mkdir(parents=True)
        (root / "pyproject.toml").write_text("[project]\nname='voxcpm'\n", encoding="utf-8")
        (root / "app.py").write_text("print('voxcpm')\n", encoding="utf-8")
        (root / "src" / "voxcpm" / "cli.py").write_text("def main():\n    return 0\n", encoding="utf-8")
        return root

    def _write_reference_audio(self, path: Path) -> None:
        with wave.open(str(path), "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(16000)
            handle.writeframes(b"\x00\x00" * 1600)


if __name__ == "__main__":
    unittest.main()
