#!/usr/bin/env python3
"""Record BubblePlug and Live process CPU/RSS while running a manual scenario."""

import argparse
import csv
import pathlib
import subprocess
import time


def snapshot():
    result = subprocess.run(
        ["/bin/ps", "-axo", "pid=,%cpu=,rss=,comm="],
        capture_output=True, text=True, check=True,
    )
    found = {}
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) != 4:
            continue
        pid, cpu, rss, command = parts
        name = pathlib.Path(command).name
        if name in ("BubblePlugApp", "BubblePlugCapture", "Live"):
            found.setdefault(name, []).append((int(pid), float(cpu), int(rss)))
    return found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seconds", type=float, default=60)
    parser.add_argument("--interval", type=float, default=0.5)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + args.seconds
    with args.output.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(("time_unix", "app_pid", "app_cpu_percent", "app_rss_kib",
                         "helper_pid", "helper_cpu_percent", "helper_rss_kib",
                         "live_pid", "live_cpu_percent", "live_rss_kib"))
        while time.monotonic() < deadline:
            processes = snapshot()
            app = (processes.get("BubblePlugApp") or [("", "", "")])[0]
            helper = (processes.get("BubblePlugCapture") or [("", "", "")])[0]
            live = (processes.get("Live") or [("", "", "")])[0]
            writer.writerow((time.time(), *app, *helper, *live))
            stream.flush()
            time.sleep(args.interval)


if __name__ == "__main__":
    main()
