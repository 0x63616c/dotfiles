#!/usr/bin/python3
"""Sample Data-volume fullness and block-device throughput; render a local page."""

import json
import os
import plistlib
import re
import sqlite3
import subprocess
import sys
import time
from pathlib import Path


DB = Path(os.environ.get("DIAGNOSTICS_DB", Path.home() / "Library/Application Support/Diagnostics/history.sqlite3"))
TEMPLATE = Path(__file__).resolve().parents[1] / "diagnostics.html"
THEME = TEMPLATE.parent / "lib/theme.lua"
HOUR = 3600
DAY = 86400


def connect():
    DB.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(DB, timeout=5)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("""CREATE TABLE IF NOT EXISTS samples (
        ts INTEGER PRIMARY KEY, used INTEGER, total INTEGER,
        read_bps REAL, write_bps REAL, read_bytes INTEGER, write_bytes INTEGER)""")
    for table in ("hourly", "daily"):
        db.execute(f"""CREATE TABLE IF NOT EXISTS {table} (
            ts INTEGER PRIMARY KEY, used REAL, total REAL,
            read_bps REAL, write_bps REAL)""")
    return db


def disk_space():
    # APFS volumes share a container. Its free bytes describe when writes to
    # the Data volume will fail; Data's own allocation misses sibling volumes.
    info = plistlib.loads(subprocess.check_output(
        ["/usr/sbin/diskutil", "info", "-plist", "/System/Volumes/Data"], timeout=10))
    total, free = info["APFSContainerSize"], info["APFSContainerFree"]
    return total - free, total


def io_counters():
    drivers = plistlib.loads(subprocess.check_output(
        ["/usr/sbin/ioreg", "-a", "-r", "-c", "IOBlockStorageDriver"], timeout=10))
    stats = [driver.get("Statistics", {}) for driver in drivers]
    return (sum(s.get("Bytes (Read)", 0) for s in stats),
            sum(s.get("Bytes (Write)", 0) for s in stats))


def archive(db, now):
    # Only fold complete hours/days, so a later run cannot replace a partial
    # aggregate with just the remaining samples from that same bucket.
    hour_cutoff = ((now - 30 * DAY) // HOUR) * HOUR
    day_cutoff = ((now - 365 * DAY) // DAY) * DAY
    db.execute("""INSERT OR REPLACE INTO hourly
        SELECT (ts / 3600) * 3600, AVG(used), AVG(total), AVG(read_bps), AVG(write_bps)
        FROM samples WHERE ts < ? GROUP BY ts / 3600""", (hour_cutoff,))
    db.execute("DELETE FROM samples WHERE ts < ?", (hour_cutoff,))
    db.execute("""INSERT OR REPLACE INTO daily
        SELECT (ts / 86400) * 86400, AVG(used), AVG(total), AVG(read_bps), AVG(write_bps)
        FROM hourly WHERE ts < ? GROUP BY ts / 86400""", (day_cutoff,))
    db.execute("DELETE FROM hourly WHERE ts < ?", (day_cutoff,))


def sample():
    now = int(time.time())
    used, total = disk_space()
    read, write = io_counters()
    with connect() as db:
        previous = db.execute("SELECT ts, read_bytes, write_bytes FROM samples ORDER BY ts DESC LIMIT 1").fetchone()
        read_bps = write_bps = None
        if previous and now > previous[0] and read >= previous[1] and write >= previous[2]:
            elapsed = now - previous[0]
            read_bps = (read - previous[1]) / elapsed
            write_bps = (write - previous[2]) / elapsed
        db.execute("INSERT OR REPLACE INTO samples VALUES (?, ?, ?, ?, ?, ?, ?)",
                   (now, used, total, read_bps, write_bps, read, write))
        archive(db, now)


def rows(db, table, since, bucket):
    if bucket == 0:
        sql = f"SELECT ts, used, total, read_bps, write_bps FROM {table} WHERE ts >= ? ORDER BY ts"
        return db.execute(sql, (since,)).fetchall()
    sql = f"""SELECT (ts / ?) * ?, AVG(used), AVG(total), AVG(read_bps), AVG(write_bps)
        FROM {table} WHERE ts >= ? GROUP BY ts / ? ORDER BY ts"""
    return db.execute(sql, (bucket, bucket, since, bucket)).fetchall()


def theme_css():
    """Read the shared pure-data Lua tokens for this webview's CSS variables."""
    source = THEME.read_text()
    declarations = []
    for section in ("color", "alpha", "radius", "text", "space", "font", "shadow"):
        body = re.search(rf"M\.{section}\s*=\s*\{{(.*?)\n\}}", source, re.S).group(1)
        for key, string, number in re.findall(r'(\w+)\s*=\s*(?:"([^"]+)"|([\d.]+))', body):
            value = string or number
            if section == "font":
                value = f'"{value}"'
            elif section in ("radius", "text", "space") or (section == "shadow" and key in ("blur", "dy")):
                value += "px"
            declarations.append(f"--{section}-{key}: {value};")
    return ":root { " + " ".join(declarations) + " }"


def render():
    now = int(time.time())
    with connect() as db:
        series = {
            "1h": rows(db, "samples", now - HOUR, 0),
            "6h": rows(db, "samples", now - 6 * HOUR, 0),
            "24h": rows(db, "samples", now - DAY, 0),
            "7d": rows(db, "samples", now - 7 * DAY, 600),
            "30d": rows(db, "samples", now - 30 * DAY, HOUR),
            "All": (rows(db, "daily", 0, 0)
                    + rows(db, "hourly", 0, DAY)
                    + rows(db, "samples", 0, DAY)),
        }
    for key in series:
        series[key] = sorted(series[key], key=lambda row: row[0])
    html = (TEMPLATE.read_text()
            .replace("/*__THEME__*/", theme_css())
            .replace("/*__DATA__*/", "const DATA = " + json.dumps(series, separators=(",", ":")) + ";"))
    output = DB.with_name("diagnostics.html")
    temporary = output.with_suffix(".tmp")
    temporary.write_text(html)
    temporary.replace(output)
    print(output.as_uri())


if __name__ == "__main__":
    {"sample": sample, "render": render}[sys.argv[1]]()
