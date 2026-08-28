#!/usr/bin/env python3
"""Safely read the task-state JSON file for the Simple Task plugin.

Runs as a short-lived helper process invoked from Tasks.qml, instead of
letting Quickshell's FileView read the path directly. The path is
predictable (~/.local/state/omarchy/tasks.json), and the plugin runs
unsandboxed inside the shared omarchy-shell process, so a planted symlink
or FIFO at that path shouldn't be able to make this plugin read an
arbitrary file, block the shell, or exhaust its memory.

Output is always a JSON array that has already been bounded and
normalized by tasklimits.sanitize_tasks, so QML never has to publish an
unbounded number of rows built from unvalidated fields. Any rejection
prints an empty array and exits 0, so callers never need to distinguish
"empty" from "refused".
"""
import json
import os
import stat
import sys

import tasklimits

READ_CHUNK = 65536

EMPTY = b"[]"


def read_bounded(fd, max_bytes):
    """Read at most max_bytes from fd, or None if the file exceeds it."""
    chunks = []
    total = 0
    while True:
        chunk = os.read(fd, READ_CHUNK)
        if not chunk:
            return b"".join(chunks)
        total += len(chunk)
        if total > max_bytes:
            return None
        chunks.append(chunk)


def read_raw(path):
    try:
        # O_NOFOLLOW: refuse atomically if the final path component is a
        # symlink, instead of following it.
        # O_NONBLOCK: if it turns out to be a FIFO, open() returns
        # immediately instead of blocking the caller until a writer shows
        # up (the actual open denial-of-service being guarded against).
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError:
        # Missing file, symlink, or anything else that can't be opened
        # this way: treat it as "no saved tasks yet".
        return None

    try:
        # Check the type of the file descriptor that's actually open, not
        # the path (a stat/lstat on the path first would leave a race
        # between the check and the open).
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            return None
        return read_bounded(fd, tasklimits.MAX_BYTES)
    finally:
        os.close(fd)


def main():
    if len(sys.argv) != 2:
        sys.stdout.buffer.write(EMPTY)
        return

    raw = read_raw(sys.argv[1])
    if raw is None:
        sys.stdout.buffer.write(EMPTY)
        return

    try:
        parsed = json.loads(raw)
    except (ValueError, RecursionError):
        sys.stdout.buffer.write(EMPTY)
        return

    tasks = tasklimits.sanitize_tasks(parsed)
    sys.stdout.buffer.write(json.dumps(tasks).encode("utf-8"))


if __name__ == "__main__":
    main()
