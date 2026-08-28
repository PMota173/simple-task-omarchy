#!/usr/bin/env python3
"""Safely write the task-state JSON file for the Simple Task plugin.

Counterpart to read-tasks.py. Quickshell's FileView.setText() with
atomicWrites keeps a reader from seeing half a document, but it does not
make the destination symlink-safe: the path is predictable, so another
same-user process can drop a symlink there and redirect a save into some
other file the user owns.

This helper never opens the destination at all. It creates a fresh file
beside it with O_CREAT|O_EXCL|O_NOFOLLOW (exclusive creation refuses to
open anything that already exists, symlink included), writes and fsyncs
that, then rename()s it over the destination. rename() replaces whatever
sits at the path, following no symlink, so a planted link is simply
overwritten instead of followed.

The payload arrives on stdin and is bounded and normalized by
tasklimits.sanitize_tasks before being written, so the same task-count
and field-length caps applied when loading also apply when saving.

Exits 0 on success, 1 on any failure (the caller logs a warning).
"""
import json
import os
import stat
import sys

import tasklimits

READ_CHUNK = 65536


def read_stdin_bounded(max_bytes):
    # The document is expected on a pipe. If stdin is a terminal (or absent)
    # the caller wired us up wrong, and reading would block indefinitely
    # holding a slot in the save queue; fail fast instead.
    try:
        if sys.stdin is None or sys.stdin.isatty():
            return None
    except (ValueError, OSError):
        return None

    chunks = []
    total = 0
    while True:
        chunk = sys.stdin.buffer.read(READ_CHUNK)
        if not chunk:
            return b"".join(chunks)
        total += len(chunk)
        if total > max_bytes:
            return None
        chunks.append(chunk)


def open_state_dir(directory):
    """Open the containing directory and confirm we own it.

    The directory itself is resolved normally (a user may legitimately
    symlink ~/.local/state elsewhere); what matters is that what we end up
    writing into is a real directory belonging to this user. The fd is
    reused afterwards to fsync the rename.
    """
    os.makedirs(directory, exist_ok=True)
    fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        info = os.fstat(fd)
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            os.close(fd)
            return None
    except OSError:
        os.close(fd)
        return None
    return fd


def write_atomically(path, payload):
    directory = os.path.dirname(path) or "."
    dir_fd = open_state_dir(directory)
    if dir_fd is None:
        return False

    # Unpredictable name so nothing can pre-create it and win the O_EXCL.
    temp_path = os.path.join(
        directory, ".tasks.%d.%s.tmp" % (os.getpid(), os.urandom(8).hex())
    )

    try:
        # O_EXCL|O_CREAT fails outright if anything already exists at this
        # name, and O_NOFOLLOW additionally refuses a symlink, so this can
        # only ever be a brand-new regular file we just made.
        fd = os.open(
            temp_path,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
            0o600,
        )
        try:
            os.write(fd, payload)
            os.fsync(fd)
        finally:
            os.close(fd)

        # Atomic replace. Never opens the destination, so a symlink sitting
        # there is replaced rather than written through.
        os.replace(temp_path, path)
        os.fsync(dir_fd)
        return True
    except OSError:
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        return False
    finally:
        os.close(dir_fd)


def main():
    if len(sys.argv) != 2:
        return 1

    raw = read_stdin_bounded(tasklimits.MAX_BYTES)
    if raw is None:
        return 1

    try:
        parsed = json.loads(raw)
    except (ValueError, RecursionError):
        return 1

    tasks = tasklimits.sanitize_tasks(parsed)
    payload = (json.dumps(tasks, indent=2) + "\n").encode("utf-8")

    return 0 if write_atomically(sys.argv[1], payload) else 1


if __name__ == "__main__":
    sys.exit(main())
