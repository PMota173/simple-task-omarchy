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
one avoids trusting the saved task file (`~/.local/state/omarchy/tasks.json`)
any more than it has to. Reading it goes through `read-tasks.py`, which
opens the path with `O_NOFOLLOW | O_NONBLOCK` and checks the resulting file
descriptor (not the path, to dodge a check-then-open race) is a regular
file before reading a capped number of bytes. That means a symlink planted
at that path can't make the plugin read something else, a FIFO can't hang
the shell waiting on `open()`, and an oversized file can't be parsed into
unbounded memory. Writes go through Quickshell's `FileView.setText()` with
`atomicWrites` on, so a reader never sees a half-written file either.

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
