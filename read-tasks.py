#!/usr/bin/env python3
"""Safely read the task-state JSON file for the Simple Task plugin.

Runs as a short-lived helper process invoked from Tasks.qml, instead of
letting Quickshell's FileView read the path directly. The path is
predictable (~/.local/state/omarchy/tasks.json), and the plugin runs
unsandboxed inside the shared omarchy-shell process, so a planted symlink
or FIFO at that path shouldn't be able to make this plugin read an
arbitrary file, block the shell, or exhaust its memory.

Always prints something JSON-parseable (an empty array on any rejection)
and exits 0, so callers never need to distinguish "empty" from "refused".
"""
import os
import stat
import sys

# Comfortably larger than any real task list; anything bigger is refused
# rather than parsed.
MAX_BYTES = 2 * 1024 * 1024
READ_CHUNK = 65536

EMPTY = b"[]"


def read_bounded(fd, max_bytes):
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


def read_task_file(path):
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
        return EMPTY

    try:
        # Check the type of the file descriptor that's actually open, not
        # the path (a stat/lstat on the path first would leave a race
        # between the check and the open).
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return EMPTY

        data = read_bounded(fd, MAX_BYTES)
        return data if data is not None else EMPTY
    finally:
        os.close(fd)


def main():
    if len(sys.argv) != 2:
        sys.stdout.buffer.write(EMPTY)
        return
    sys.stdout.buffer.write(read_task_file(sys.argv[1]))


if __name__ == "__main__":
    main()
