# Simple Task

A dead-simple task list for [Omarchy](https://omarchy.org/): an overlay plugin
for the Omarchy shell, styled with whatever theme you have active. No webapp,
no separate window, no account. Type a task, hit Enter, check it off.

![Simple Task screenshot](preview.png)

Requires `python3`, used to read the saved task file safely (see
[Security](#security) below). It's part of virtually every Arch/Omarchy
install already, so this is rarely something you need to think about.

## Install

```bash
omarchy plugin add https://github.com/PMota173/simple-task-omarchy.git --enable
```

This clones the plugin into `~/.config/omarchy/plugins/pedro.simple-task/`
and registers it in `~/.config/omarchy/shell.json`.

## Bind a key to it

Simple Task is an overlay, summoned like Omarchy's built-in Clipboard manager
or Reminders. It doesn't ship with a keybinding of its own, so add one in
`~/.config/hypr/bindings.lua`. The suggested default is **SUPER + SHIFT + T**:

```lua
o.bind("SUPER + SHIFT + T", "Simple Task", "omarchy-shell shell toggle pedro.simple-task")
```

If that combo is already taken on your setup, check
`omarchy menu keybindings --print` and pick a free one instead.

## Using it

Open it with your keybind (**SUPER + SHIFT + T** if you used the suggested
default above), then:

- Type anything and press **Enter** to add it as a task
- **↑ / ↓** to move the selection
- **Enter** (with nothing typed) checks/unchecks the selected task
- **Delete** removes the selected task
- **Shift+Delete** clears every completed task (asks to confirm)
- **Esc** clears what you're typing, or closes the overlay if the input is empty

Completed tasks drop to the bottom of the list, struck through. Everything
is saved to `~/.local/state/omarchy/tasks.json` as you go, so it survives
restarts.

## Theming

Colors are pulled straight from the active Omarchy theme (`Color.menu.*` for
the card, `Color.popups.border` for the border, the same accent color
Hyprland uses for active window borders), so it re-themes itself automatically
whenever you switch themes with `omarchy theme set`.

## Security

Plugins run unsandboxed inside the shared `omarchy-shell` process, so this
one never opens the saved task file (`~/.local/state/omarchy/tasks.json`)
from inside that process. Both directions go through small helper
processes, because the path is predictable and another process running as
you could plant something hostile there.

**Reading** (`read-tasks.py`) opens the path with `O_NOFOLLOW | O_NONBLOCK`
and checks the resulting file descriptor (not the path, to dodge a
check-then-open race) is a regular file before reading a capped number of
bytes. A symlink can't redirect the read, a FIFO can't hang the shell on
`open()`, and an oversized file can't be parsed into unbounded memory.

**Writing** (`write-tasks.py`) never opens the destination either. It
creates a fresh file beside it with `O_CREAT | O_EXCL | O_NOFOLLOW`, fsyncs
it, and `rename()`s it over the destination. `rename()` follows no symlink,
so a link planted at the path is replaced rather than written through, and
the file it pointed at is left alone. Atomic writes on their own would not
give you this.

**Bounds** (`tasklimits.py`, mirrored in `TasksModel.js`) cap the task count
and per-field lengths, not just the raw byte size. A file that stays under
the byte ceiling can still hold tens of thousands of tiny valid task
objects, which would otherwise become that many retained objects and list
rows inside the shell process. The same caps apply when loading, when
adding tasks in-app, and when saving.

## Uninstall

```bash
omarchy plugin remove pedro.simple-task
```

This removes the plugin folder and un-registers it from
`~/.config/omarchy/shell.json`. If you added a keybinding for it, remove that
line from `~/.config/hypr/bindings.lua` too. Your saved tasks stay at
`~/.local/state/omarchy/tasks.json` in case you reinstall later; delete that
file yourself if you want them gone for good.

## License

MIT
