"""Shared bounds and normalization for the Simple Task state file.

Imported by both read-tasks.py and write-tasks.py so the read side and the
write side can never drift apart on what counts as an acceptable document.

The byte ceiling alone doesn't bound how much work the shell ends up doing:
a 2 MiB file can hold tens of thousands of small valid task objects, and
every one of them would become a retained object plus a ListModel row
inside the shared omarchy-shell process. These caps bound the object count
and per-field sizes as well, and are applied before the data is handed to
QML and again before anything is written back to disk.
"""

# Generous next to any real task list (the UI is a single scrolling column),
# but small enough that a hostile file can't turn into unbounded objects,
# rows, and delegates inside the shell process.
MAX_TASKS = 1000
MAX_TEXT_CHARS = 1000
MAX_ID_CHARS = 64

# Ceiling on raw document size, checked before anything is parsed.
MAX_BYTES = 2 * 1024 * 1024

# JSON numbers stay in the range JS integers represent exactly.
MAX_TIMESTAMP = 2 ** 53 - 1


def _clean_text(value):
    if not isinstance(value, str):
        return ""
    return value.strip()[:MAX_TEXT_CHARS]


def _clean_id(value):
    if not isinstance(value, str):
        return ""
    return value[:MAX_ID_CHARS]


def _clean_timestamp(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    try:
        number = int(value)
    except (ValueError, OverflowError):
        return 0
    return max(0, min(number, MAX_TIMESTAMP))


def sanitize_tasks(data):
    """Coerce parsed JSON into a bounded list of well-formed task dicts.

    Anything unexpected (wrong type, missing text, extra keys) is dropped
    rather than repaired, and the result is truncated to MAX_TASKS.
    """
    if not isinstance(data, list):
        return []

    tasks = []
    for entry in data:
        if len(tasks) >= MAX_TASKS:
            break
        if not isinstance(entry, dict):
            continue

        text = _clean_text(entry.get("text"))
        if not text:
            continue

        tasks.append({
            "id": _clean_id(entry.get("id")),
            "text": text,
            "done": entry.get("done") is True,
            "createdAt": _clean_timestamp(entry.get("createdAt")),
        })

    return tasks
