import importlib.util
import re
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("prepare_compatibility", ROOT / "tools/prepare_compatibility.py")
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class CompatibilityExport(unittest.TestCase):
    def test_reachable_resources_are_portable_and_source_is_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            project, output = Path(tmp) / "source", Path(tmp) / "export"
            project.mkdir()
            shutil.copytree(ROOT / "drp", project / "drp")
            settings = "[bootstrap]\nmain_collection = /main.collectionc\nrender = /drp/drp.renderc\n[drp]\ndefault_profile = ultra\n"
            (project / "game.project").write_text(settings)
            scene = '\n'.join(f'material: "/drp/materials/clustered_{s}.material"' for s in ("opaque", "mask", "transparent"))
            (project / "scene.model").write_text(scene)
            cached = project / ".internal/lib/cached.zip"
            cached.parent.mkdir(parents=True)
            cached.write_bytes(b"dependency archive")
            original = {p.relative_to(project): p.read_bytes() for p in project.rglob("*") if p.is_file()}
            exporter.prepare(project, output)
            for name, data in original.items():
                self.assertEqual((project / name).read_bytes(), data)
            self.assertEqual((output / "scene.model").read_text(), scene)
            self.assertEqual((output / ".internal/lib/cached.zip").read_bytes(), cached.read_bytes())
            self.assertIn("clustered_resources = 0", (output / "game.project").read_text())
            self.assertIn("render = /drp/compatibility.renderc", (output / "game.project").read_text())

            # Walk the actual material/include/render dependencies, starting
            # from both renderer paths and the unchanged model material slots.
            visited = set()
            def visit(path):
                if path in visited or path.startswith("/defold-pbr/"):
                    return
                visited.add(path)
                self.assertFalse(path.endswith((".compute", ".cp")), path)
                text = (output / path.lstrip("/")).read_text()
                if path.endswith((".fp", ".glsl")):
                    self.assertNotRegex(text, r"\bbuffer\s+\w+\s*\{")
                for reference in re.findall(r'"(/[^"\n]+)"', text):
                    if reference.endswith((".material", ".fp", ".vp", ".glsl", ".compute")):
                        visit(reference)
            for path in ("/drp/drp.render", "/drp/compatibility.render", "/scene.model"):
                visit(path)
            self.assertGreater(len(visited), 8)
            for surface in ("opaque", "mask", "transparent"):
                self.assertIn(f'tags: "drp_cluster_{surface}"',
                    (output / f"drp/materials/clustered_{surface}.material").read_text())

    def test_refuses_existing_or_nested_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source"
            source.mkdir()
            for output in (source, source / "export", Path(tmp)):
                with self.assertRaises(ValueError):
                    exporter.prepare(source, output)

    def test_settings_preserve_other_sections(self):
        before = "[drp]\ndefault_profile = ultra\n\n[display]\nwidth = 960\n"
        after = exporter.set_setting(before, "drp", "clustered_resources", "0")
        self.assertEqual(after.count("[drp]"), 1)
        self.assertIn("[display]\nwidth = 960", after)
        self.assertLess(after.index("clustered_resources"), after.index("[display]"))


if __name__ == "__main__":
    unittest.main()
