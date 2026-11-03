#!/usr/bin/env python3
"""Build a disposable three-light fixture and run it with a matching DRP engine."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bob", type=Path, required=True, help="Matching current bob.jar")
    parser.add_argument("--engine", type=Path, required=True, help="Engine containing this version of DRP")
    parser.add_argument("--platform", default="arm64-macos")
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="drp-shadow-smoke-") as directory:
        root = Path(directory)
        for name in ("drp", "examples", "tests"):
            shutil.copytree(project / name, root / name, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        if (project / ".internal/lib").is_dir():
            shutil.copytree(project / ".internal/lib", root / ".internal/lib")
        text = (project / "game.project").read_text()
        lines = []
        for line in text.splitlines():
            if line.startswith("main_collection ="):
                line = "main_collection = /examples/shadows/shadows.collectionc"
            lines.append(line)
        (root / "game.project").write_text("\n".join(lines) + "\n")
        # Resource-only build. The supplied engine already contains the tested extension.
        (root / "drp/ext.manifest").unlink()
        script = root / "drp/drp.render_script"
        script.write_text(script.read_text() + '\nupdate = require("tests.shadow_runtime_smoke").install(pipeline, update)\n')
        # Freeze geometry while asserting explicit cache reuse.
        (root / "examples/shadows/demo.script").write_text("function init(self) end\n")
        subprocess.run(["java", "-jar", str(args.bob.resolve()), "--root", str(root),
                        "--platform", args.platform, "--architectures", args.platform,
                        "--debug-output-glsl", "true", "--debug-output-msl", "true",
                        "--debug-output-spirv", "true", "build"], check=True, cwd=root)
        result = subprocess.run([str(args.engine.resolve()), "build/default/game.projectc"],
                                cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        print(result.stdout)
        if result.returncode or "SHADOW_RUNTIME_PASS" not in result.stdout or "SHADOW_RUNTIME_FAIL" in result.stdout:
            raise SystemExit("Shadow runtime smoke failed")
        print("shadow_runtime_smoke: PASS")


if __name__ == "__main__":
    main()
