#!/usr/bin/env python3
"""Flag obvious non-editor screenshots found by macOS Vision OCR."""

import argparse
import collections
import pathlib


PATTERNS = {
    "missing resource or data": (
        "one of the files this plug-in",
        "resource image",
        "data not found",
        "mdaummer data not found",
        "cannot find any instruments",
    ),
    "helper error": ("could not get editor view size", "could not get edltor vlew slz"),
    "welcome or activation": ("welcome to", "welcometo", "welcomeio", "activate", "activation"),
    "license": ("invalid license", "imialid license", "authorization"),
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ocr", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    flagged = []
    for line in args.ocr.read_text().splitlines():
        name, _, content = line.partition("\t")
        lower = content.lower()
        for category, patterns in PATTERNS.items():
            if any(pattern in lower for pattern in patterns):
                flagged.append((name, category, content))
                break
    counts = collections.Counter(category for _, category, _ in flagged)
    report = ["# BubblePlug image quality screening", "",
              f"OCR flagged **{len(flagged)} potentially unacceptable images**.",
              "This is a lower bound: OCR cannot verify every plugin interface and can miss short or stylized messages.", "",
              "## Categories", ""]
    report += [f"- {category}: {count}" for category, count in sorted(counts.items())]
    report += ["", "## Flagged images", "", "| Plugin | Category | Recognized text |", "|---|---|---|"]
    report += [f"| {name.replace('|', '/')} | {category} | {content.replace('|', '/')} |"
               for name, category, content in flagged]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(report) + "\n")
    print(f"Flagged {len(flagged)} images; wrote {args.output}")


if __name__ == "__main__":
    main()
