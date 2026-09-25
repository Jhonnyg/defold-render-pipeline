#!/usr/bin/env python3
"""Create a source tree whose reachable render resources require no compute/SSBOs.

Run Bob (or open the exported project in Defold) to build the result normally.
The original project is never modified. Model/material resource paths and tags
are preserved so scenes do not need separate compatibility versions.
"""

import argparse
import re
import shutil
from pathlib import Path


def set_setting(text, section, key, value):
    lines = text.splitlines()
    header = f"[{section}]"
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == header)
    except StopIteration:
        return text.rstrip() + f"\n\n{header}\n{key} = {value}\n"
    end = next((i for i in range(start + 1, len(lines)) if lines[i].strip().startswith("[")), len(lines))
    for i in range(start + 1, end):
        if re.match(rf"\s*{re.escape(key)}\s*=", lines[i]):
            lines[i] = f"{key} = {value}"
            break
    else:
        lines.insert(end, f"{key} = {value}")
    return "\n".join(lines) + "\n"


def prepare(project, output):
    project, output = Path(project).resolve(), Path(output).resolve()
    if output == project or project in output.parents or output in project.parents:
        raise ValueError("output must be a separate directory outside the source project")
    if output.exists():
        raise ValueError("output already exists; choose a new directory")
    if not (project / "game.project").is_file() or not (project / "drp/compatibility.render").is_file():
        raise ValueError("project must contain game.project and the drp directory")

    shutil.copytree(project, output, ignore=shutil.ignore_patterns(
        ".git", ".internal", "build", ".editor_settings", "__pycache__", ".DS_Store"))
    # Retain downloaded dependency archives for reproducible/offline builds.
    libraries = project / ".internal/lib"
    if libraries.is_dir():
        shutil.copytree(libraries, output / ".internal/lib")

    for surface in ("opaque", "mask", "transparent"):
        material = (output / f"drp/materials/compat_{surface}.material").read_text()
        material = material.replace(f'name: "drp_compat_{surface}"', f'name: "drp_clustered_{surface}"')
        material = material.replace(f'tags: "drp_compat_{surface}"', f'tags: "drp_cluster_{surface}"')
        (output / f"drp/materials/clustered_{surface}.material").write_text(material)

    # Also replace the default render resource. Existing references to drp.render
    # must not accidentally pull the compute programs back into the build graph.
    shutil.copyfile(output / "drp/compatibility.render", output / "drp/drp.render")
    settings = (output / "game.project").read_text()
    settings = set_setting(settings, "bootstrap", "render", "/drp/compatibility.renderc")
    settings = set_setting(settings, "drp", "default_profile", "compatibility")
    settings = set_setting(settings, "drp", "clustered_resources", "0")
    (output / "game.project").write_text(settings)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        output = prepare(args.project, args.output)
    except (ValueError, OSError) as error:
        parser.exit(1, f"Compatibility export failed: {error}\n")
    print(f"Compatibility project: {output}")
    print("Build this directory with Bob or the Defold editor.")


if __name__ == "__main__":
    main()
