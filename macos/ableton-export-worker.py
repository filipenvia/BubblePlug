#!/usr/bin/env python3
"""Safely replace Ableton Live 12.4.2 Browser Collections while Live is closed."""

import argparse
import datetime as dt
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path

HOME = Path.home()
SUPPORT = HOME / "Library/Application Support/PlugSpot"
PREFS = HOME / "Library/Preferences/Ableton"
DB_DIR = HOME / "Library/Application Support/Ableton/Live Database"
LIVE_BUNDLE_ID = "com.ableton.live"


class ExportError(Exception):
    pass


def normalized(value):
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(char for char in value if not unicodedata.combining(char))
    return " ".join(value.casefold().split())


def family_base(name):
    match = re.match(r"^(.*)\s+([^\s]+)$", name or "")
    if not match:
        return (name or "").strip()
    base, suffix = match.groups()
    tokens = suffix.split("/")
    channel_tokens = {"mono", "stereo", "quad", "lcr", "ambix", "ambix-fuma", "fuma-ambix"}
    composite = len(tokens) > 1
    def is_channel(token):
        numeric_pattern = r"\d+(?:\.\d+){0,2}" if composite else r"\d+\.\d+(?:\.\d+)?"
        return token.casefold() in channel_tokens or bool(re.fullmatch(numeric_pattern, token))
    if tokens and all(is_channel(token) for token in tokens):
        return base.strip()
    return (name or "").strip()


def discover_targets():
    cfgs = [path for path in PREFS.glob("Live */Library.cfg") if path.is_file()]
    if not cfgs:
        raise ExportError("Could not find an Ableton Live Library.cfg.")
    cfg = max(cfgs, key=lambda path: path.stat().st_mtime)
    if "Live 12.4.2" not in str(cfg):
        raise ExportError("Collection export is validated only for Ableton Live 12.4.2 on this Mac.")
    dbs = [path for path in DB_DIR.glob("Live-files-*.db") if path.is_file()]
    if not dbs:
        raise ExportError("Could not find Ableton's indexed file database.")
    db = max(dbs, key=lambda path: path.stat().st_mtime)
    plugin_db = DB_DIR / "Live-plugins-1.db"
    if not plugin_db.is_file():
        raise ExportError("Could not find Ableton's plugin metadata database.")
    return cfg, db, plugin_db


def load_document(path):
    try:
        document = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:
        raise ExportError("The staged PlugSpot library is not valid JSON.") from exc
    if document.get("schemaVersion") != 2:
        raise ExportError("This export requires PlugSpot library schema version 2.")
    categories = document.get("categories", [])
    if len(categories) > 6:
        raise ExportError("Ableton supports six PlugSpot categories plus Favorites.")
    colors = [item.get("colorIndex") for item in categories]
    if any(not isinstance(color, int) or not 2 <= color <= 7 for color in colors) or len(set(colors)) != len(colors):
        raise ExportError("PlugSpot categories must use unique Ableton colors 2 through 7.")
    names = [normalized(item.get("name", "")) for item in categories]
    if any(not name for name in names) or len(set(names)) != len(names):
        raise ExportError("PlugSpot category names must be non-empty and unique.")
    return document


def expected_families(document):
    expected = {}
    for favorite in document.get("favorites", []):
        if (favorite.get("format") or "VST3").upper() != "VST3":
            raise ExportError("Favorites in formats other than VST3 cannot be exported yet. No Ableton files were changed.")
        expected[favorite.get("id", "")] = {
            "name": favorite.get("name", ""),
            "vendor": favorite.get("vendor", ""),
            "colors": {1},
        }
    color_by_name = {normalized(category["name"]): category["colorIndex"] for category in document.get("categories", [])}
    for label in document.get("labels", []):
        if label.get("kind") != "category":
            continue
        if (label.get("format") or "VST3").upper() != "VST3":
            raise ExportError("Category assignments in formats other than VST3 cannot be exported yet. No Ableton files were changed.")
        plugin_id = label.get("pluginID", "")
        record = expected.setdefault(plugin_id, {"name": label.get("pluginName") or "", "vendor": label.get("vendor") or "", "colors": set()})
        if label.get("pluginName"):
            record["name"] = label["pluginName"]
        if label.get("vendor"):
            record["vendor"] = label["vendor"]
        index = color_by_name.get(normalized(label.get("name", "")))
        if index is None:
            raise ExportError("A category assignment refers to a category that no longer exists.")
        record["colors"].add(index)
    for family_id, record in list(expected.items()):
        if not record["name"]:
            pieces = family_id.split("|")
            if len(pieces) >= 2:
                record["vendor"] = record["vendor"] or pieces[0]
                record["name"] = pieces[1]
        record["name"] = family_base(record["name"])
        if not record["name"] or not record["colors"]:
            del expected[family_id]
    return expected


def match_families(document, cfg, db, plugin_db):
    expected = expected_families(document)
    connection = sqlite3.connect("file:%s?mode=ro" % db, uri=True, timeout=8)
    connection.execute("PRAGMA query_only=ON")
    try:
        files = connection.execute("""
            SELECT name, device_id
            FROM files
            WHERE device_id LIKE 'device:vst3:%' AND device_type IN (1, 2)
        """).fetchall()
        total_rows = connection.execute("SELECT COUNT(*) FROM files").fetchone()[0]
        colored_rows = connection.execute("SELECT COUNT(*) FROM files WHERE colors != 1").fetchone()[0]
    finally:
        connection.close()
    plugins = sqlite3.connect("file:%s?mode=ro" % plugin_db, uri=True, timeout=8)
    plugins.execute("PRAGMA query_only=ON")
    try:
        vendor_by_id = {identifier: vendor or "" for identifier, vendor in plugins.execute(
            "SELECT dev_identifier, MAX(vendor) FROM plugins GROUP BY dev_identifier"
        )}
    finally:
        plugins.close()
    index = {}
    for name, device_id in files:
        vendor = vendor_by_id.get(device_id, "")
        key = (normalized(vendor), normalized(family_base(name or "")))
        index.setdefault(key, set()).add(device_id)
    mapped = {}
    missing = []
    for family_id, family in expected.items():
        key = (normalized(family["vendor"]), normalized(family["name"]))
        candidates = set(index.get(key, set()))
        if not candidates and not family["vendor"]:
            candidates = set().union(*(device_ids for (vendor, name), device_ids in index.items() if name == key[1]))
        if not candidates:
            missing.append({"name": family["name"], "vendor": family["vendor"], "reason": "not_found"})
            continue
        # Multiple identifiers are channel/layout variants of the same family,
        # matching PlugSpot's own grouping rule; assign every variant.
        for device_id in candidates:
            mapped.setdefault(device_id, set()).update(family["colors"])
    return {
        "cfg": str(cfg), "db": str(db), "plugin_db": str(plugin_db),
        "matchedFamilies": len(expected) - len(missing), "expectedFamilies": len(expected),
        "missing": missing, "mappedDevices": len(mapped), "coloredItemsToClear": colored_rows,
        "totalBrowserItems": total_rows, "mapped": {key: sorted(value) for key, value in mapped.items()},
    }


def preflight(request_path, output_path):
    try:
        document = load_document(request_path)
        cfg, db, plugin_db = discover_targets()
        match = match_families(document, cfg, db, plugin_db)
        root = ET.parse(cfg).getroot()
        if "Ableton Live 12.4.2" not in root.attrib.get("Creator", ""):
            raise ExportError("The selected Live preferences file is not from Live 12.4.2.")
        result = {"ok": True, **match}
    except Exception as exc:
        result = {"ok": False, "error": str(exc)}
    Path(output_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def live_is_running():
    result = subprocess.run(["/usr/bin/pgrep", "-x", "Live"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def make_backup(paths):
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = SUPPORT / "backups" / ("ableton-collections-" + stamp)
    backup_dir.mkdir(parents=True, exist_ok=False)
    for path in paths:
        destination = backup_dir / path.name
        clone = subprocess.run(["/bin/cp", "-c", str(path), str(destination)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if clone.returncode != 0:
            required = path.stat().st_size + 256 * 1024 * 1024
            if shutil.disk_usage(backup_dir).free < required:
                shutil.rmtree(backup_dir, ignore_errors=True)
                raise ExportError("Could not create an APFS clone and there is not enough free space for a full backup.")
            shutil.copy2(path, destination)
        if destination.stat().st_size != path.stat().st_size:
            shutil.rmtree(backup_dir, ignore_errors=True)
            raise ExportError("A backup copy failed its size verification.")
    return backup_dir


def update_library_config(cfg_path, categories):
    tree = ET.parse(cfg_path)
    root = tree.getroot()
    if "Ableton Live 12.4.2" not in root.attrib.get("Creator", ""):
        raise ExportError("Live preferences changed since preflight; no changes were applied.")
    label_infos = root.find("LabelInfos")
    if label_infos is None:
        raise ExportError("Library.cfg has no LabelInfos section; no changes were applied.")
    names = {1: "Favorites"}
    names.update({item["colorIndex"]: item["name"] for item in categories})
    found = set()
    for element in label_infos.findall("LabelInfo"):
        uri = element.attrib.get("Uri", "")
        match = re.fullmatch(r"color:colors=([1-7])", uri)
        if not match:
            continue
        index = int(match.group(1))
        found.add(index)
        element.set("DisplayName", names.get(index, ""))
        element.set("IsEnabled", "true" if index in names else "false")
    if found != set(range(1, 8)):
        raise ExportError("Library.cfg does not contain all seven Collection labels; no changes were applied.")
    original_mode = cfg_path.stat().st_mode
    temp_path = cfg_path.with_name(cfg_path.name + ".plugspot-tmp")
    tree.write(temp_path, encoding="UTF-8", xml_declaration=True)
    os.chmod(temp_path, original_mode)
    os.replace(temp_path, cfg_path)


def apply_export(request_path, result_path):
    result = {"ok": False}
    cfg = db = plugin_db = backup_dir = None
    config_changed = False
    try:
        if live_is_running():
            raise ExportError("Ableton Live is still running. No files were changed.")
        document = load_document(request_path)
        cfg, db, plugin_db = discover_targets()
        matched = match_families(document, cfg, db, plugin_db)
        if matched["missing"]:
            names = ", ".join(item["name"] for item in matched["missing"][:12])
            more = " and more" if len(matched["missing"]) > 12 else ""
            raise ExportError("Some PlugSpot plugins could not be matched (%s%s). No Collections were changed." % (names, more))
        database_parts = [db]
        database_parts.extend(Path(str(db) + suffix) for suffix in ("-wal", "-shm") if Path(str(db) + suffix).exists())
        backup_dir = make_backup([cfg, *database_parts])
        update_library_config(cfg, document.get("categories", []))
        config_changed = True
        connection = sqlite3.connect(db, timeout=10)
        try:
            checkpoint = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
            if checkpoint and checkpoint[0] != 0:
                raise ExportError("The Live database checkpoint was busy. No Collections were changed.")
            connection.execute("PRAGMA journal_mode=DELETE")
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("UPDATE files SET colors=1 WHERE colors != 1")
            cleared = connection.total_changes
            for device_id, color_indexes in matched["mapped"].items():
                mask = sum(1 << index for index in color_indexes)
                cursor = connection.execute(
                    "UPDATE files SET colors=? WHERE device_id=? AND device_type IN (1,2)",
                    (1 | mask, device_id),
                )
                if cursor.rowcount < 1:
                    raise ExportError("A matched VST3 entry disappeared during export. The database transaction was rolled back.")
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            connection.close()
        result.update({
            "ok": True, "message": "Ableton Collections were replaced from PlugSpot.",
            "backupDirectory": str(backup_dir), "matchedFamilies": matched["matchedFamilies"],
            "mappedDevices": matched["mappedDevices"], "clearedItems": cleared,
            "categories": len(document.get("categories", [])),
        })
    except Exception as exc:
        if config_changed and backup_dir and cfg:
            try:
                shutil.copy2(backup_dir / cfg.name, cfg)
            except Exception as rollback_error:
                result["rollbackError"] = str(rollback_error)
        result.update({"ok": False, "error": str(exc), "backupDirectory": str(backup_dir) if backup_dir else None})
    Path(result_path).write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preflight", nargs=2, metavar=("REQUEST", "RESULT"))
    parser.add_argument("--apply", nargs=2, metavar=("REQUEST", "RESULT"))
    args = parser.parse_args()
    if args.preflight:
        result = preflight(*args.preflight)
    elif args.apply:
        result = apply_export(*args.apply)
    else:
        parser.error("Choose --preflight or --apply")
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
