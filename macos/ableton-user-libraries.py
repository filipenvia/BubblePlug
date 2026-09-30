#!/usr/bin/python3
"""Print Ableton Live User Library paths stored in Library.cfg files."""

from __future__ import annotations

import glob
import os
import sys
import xml.etree.ElementTree as ET


def value(parent: ET.Element, name: str) -> str:
    element = parent.find(name)
    return element.get("Value", "").strip() if element is not None else ""


def configured_libraries(home: str) -> list[str]:
    preferences = os.path.join(home, "Library", "Preferences", "Ableton")
    configs = glob.glob(os.path.join(preferences, "Live *", "Library.cfg"))
    found: list[tuple[float, str]] = []

    for config in configs:
        try:
            root = ET.parse(config).getroot()
            project = root.find("./ContentLibrary/UserLibrary/LibraryProject")
            if project is None:
                continue
            path = value(project, "ProjectPath")
            name = value(project, "ProjectName")
            if not path:
                continue
            path = os.path.abspath(os.path.expanduser(os.path.expandvars(path)))
            if name and os.path.basename(os.path.normpath(path)).casefold() != name.casefold():
                path = os.path.join(path, name)
            found.append((os.path.getmtime(config), os.path.normpath(path)))
        except (OSError, ET.ParseError) as error:
            print(f"Skipping unreadable Ableton library settings {config}: {error}", file=sys.stderr)

    if not found:
        return [os.path.join(home, "Music", "Ableton", "User Library")]

    # Newer Live versions can have separate preferences. Install into each
    # distinct configured User Library so every installed version can load the
    # Control Surface from its own Browser library.
    return list(dict.fromkeys(path for _, path in sorted(found, reverse=True)))


def main() -> int:
    home = os.path.abspath(os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~"))
    for path in configured_libraries(home):
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
