#!/usr/bin/env python3
"""Summarize one complete BubblePlug image capture run for release notes."""

import argparse
import collections
import datetime as dt
import pathlib
import re
import statistics


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", type=pathlib.Path, default=pathlib.Path.home() / "Library/Application Support/PlugSpot/artwork-capture.log")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("artifacts/artwork-scan-report.md"))
    args = parser.parse_args()
    lines = args.log.read_text().splitlines()
    starts = [i for i, line in enumerate(lines) if " RUN_START id=" in line]
    if not starts:
        raise SystemExit("No measured capture run has started yet.")
    run = lines[starts[-1]:]
    start = run[0]
    run_id = re.search(r"id=(\S+)", start).group(1)
    run = [line for line in run if f"id={run_id}" in line]
    complete = any(" RUN_END " in line for line in run)
    successes = []
    failures = []
    for line in run:
        if " OK " in line:
            name = line.split(" OK ", 1)[1].split(" elapsed=", 1)[0]
            successes.append((name, float(re.search(r"elapsed=([\d.]+)s", line).group(1)),
                              float(re.search(r"firstVisible=([\d.]+)s", line).group(1)),
                              int(re.search(r"rejectedWindows=(\d+)", line).group(1))))
        elif " FAIL " in line:
            name = line.split(" FAIL ", 1)[1].split(" elapsed=", 1)[0]
            reason = line.split(f"id={run_id}: ", 1)[-1]
            failures.append((name, float(re.search(r"elapsed=([\d.]+)s", line).group(1)), reason))
    waits = [entry[1] for entry in successes]
    counts = collections.Counter("timeout" if "within 25 seconds" in reason else
                                 "scanner match" if "Could not match" in reason else
                                 "helper exit" if "helper exited" in reason else "other"
                                 for _, _, reason in failures)
    start_time = dt.datetime.fromisoformat(start.split(" ", 1)[0].replace("Z", "+00:00"))
    end_time = dt.datetime.fromisoformat(run[-1].split(" ", 1)[0].replace("Z", "+00:00"))
    total = int(re.search(r"plugins=(\d+)", start).group(1))
    minimum = float(re.search(r"minimumWait=([\d.]+)s", start).group(1))
    output = ["# BubblePlug image capture study", "",
              f"Run: `{run_id}`", f"Status: {'complete' if complete else 'in progress'}",
              f"Started: {start_time.isoformat()}", f"Observed duration: {end_time - start_time}",
              f"Plugins scheduled for editor capture: {total}",
              f"Minimum editor wait: {minimum:.1f} s; timeout: 25 s", "",
              "## Capture results", "",
              f"- Captured: {len(successes)}",
              f"- Failed: {len(failures)}",
              f"- Rejected empty or unusable frames during successful captures: {sum(entry[3] for entry in successes)}",
              f"- First usable frame after {minimum:.1f} s: {sum(entry[2] > minimum for entry in successes)}",
              f"- Failure types: {dict(counts)}", ""]
    if waits:
        output += ["## Timing for successful captures", "",
                   f"- Median: {statistics.median(waits):.2f} s",
                   f"- Mean: {statistics.mean(waits):.2f} s",
                   f"- Maximum: {max(waits):.2f} s", "",
                   "## Slowest successful plugins", "",
                   "| Plugin | Elapsed | First usable frame | Rejected frames |",
                   "|---|---:|---:|---:|"]
        output += [f"| {name.replace('|', '/')} | {elapsed:.2f} s | {first:.2f} s | {rejected} |"
                   for name, elapsed, first, rejected in sorted(successes, key=lambda item: -item[1])[:30]]
        output.append("")
    output += ["## Failures", "", "| Plugin | Elapsed | Reason |", "|---|---:|---|"]
    output += [f"| {name.replace('|', '/')} | {elapsed:.2f} s | {reason.replace('|', '/')} |"
               for name, elapsed, reason in failures]
    output += ["", "Automated content checks reject empty windows. They do not prove that every saved image shows the finished plugin interface; visual review is still required.", ""]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(output))
    print(args.output)


if __name__ == "__main__":
    main()
