# tmux

Classic tmux 3.8 with the prefix on **Ctrl+s**. `~/.tmux.conf` links to
`dotfiles/shell/tmux.conf`, which loads the files in this folder through
`~/.maclift`, a link maclift makes to wherever you cloned it:

| File | What's in it |
|------|--------------|
| `options.conf` | Terminal features, timing, copy mode, mouse, bell |
| `status.conf` | Status bar layout, titles, pane borders |
| `keys.conf` | Key bindings |
| `plugins.conf` | Plugin list and plugin options |

Each setting has a one-line comment saying why it's there.

## Reload and plugins

- **Reload the config:** `prefix r`, or `tmux source ~/.tmux.conf` from a shell.
- **Edit the config:** `prefix e` opens these files in nvim and reloads when you quit.
- **Install plugins:** `prefix I` (capital i). Run it after adding a plugin or on a new Mac.
  From a shell: `~/.tmux/plugins/tpm/bin/install_plugins`.
- **Update plugins:** `prefix U`.
- **Remove unlisted plugins:** `prefix M-u` (Alt+u).

## Keys

"prefix x" means: press Ctrl+s, let go, then press x.

### Panes and windows

| Keys | Action |
|------|--------|
| `prefix \|` / `prefix -` | Split side by side / top and bottom (same folder) |
| `prefix h j k l` | Move to the pane left / down / up / right |
| `Alt+arrows` | Move between panes (no prefix) |
| `Shift+Left/Right` | Previous / next window (no prefix) |
| `prefix C-h` / `prefix C-l` | Move the window one place left / right (repeat without the prefix) |
| `prefix Enter` | Zoom the pane to full window and back |
| `prefix D` | Shrink the pane by 8 lines |
| `prefix Tab` | Floating pane (built into tmux 3.8) |
| `prefix M-1` | Layout: main + terminal (70/30) |
| `prefix M-2` | Layout: main + terminal + logs |
| `prefix M-3` | Layout: main + server + tests + logs |
| `prefix a` | Type into all panes at once (toggle) |
| `prefix m` | Mouse on/off |
| `prefix y` | Clear the pane's screen and scrollback (types nothing into the pane) |

### Sessions

| Keys | Action |
|------|--------|
| `prefix C-p` | New session for a project, in the current folder |
| `prefix S` | Pick a session with fzf |
| `prefix s` | Session and window tree (tmux default) |
| `prefix C-s` | Save all sessions (tmux-resurrect; replaces "send Ctrl+s") |
| `prefix C-r` | Restore saved sessions (tmux-resurrect) |

### Copy mode (vi keys)

| Keys | Action |
|------|--------|
| `prefix [` | Enter copy mode |
| `prefix /` | Enter copy mode and search up |
| `v` / `V` / `r` | Start selection / select lines / block selection |
| `y` | Copy the selection to the clipboard (tmux-yank) |
| `/` / `?` | Search down / up as you type |
| `o` / `C-o` / `S` | Open the selection / open in $EDITOR / search the web (tmux-open) |

### Plugins

| Keys | Action |
|------|--------|
| `prefix u` | Hints on paths, hashes, URLs, IPs; type a hint to copy it (tmux-fingers) |
| `prefix J` | Same hints, but jump copy mode to the match (tmux-fingers) |
| `prefix X` | fzf over the pane's scrollback; Tab inserts, Enter copies (extrakto) |
| `prefix F` | fzf menu for sessions, windows, panes, commands, keys (tmux-fzf) |
| `prefix C-y` | Copy the shell's current command line (tmux-yank) |
| `prefix Y` | Copy the pane's folder (tmux-yank) |
| `prefix I` / `U` / `M-u` | Install / update / clean plugins (tpm) |

## Plugins

| Plugin | Purpose |
|--------|---------|
| tpm | Plugin manager |
| tmux-sensible | Sane defaults |
| tmux-resurrect | Save and restore sessions |
| tmux-continuum | Auto-save sessions every 15 minutes |
| catppuccin/tmux | Theme and status bar modules (latte when macOS is light, mocha when dark) |
| tmux-prefix-highlight | Shows PREFIX / COPY / SYNC in the status bar |
| tmux-yank | Copy to the macOS clipboard |
| tmux-open | Open files and URLs from copy mode |
| tmux-fzf | fzf menus for tmux |
| tmux-fingers | Copy hints for paths, hashes and URLs |
| extrakto | fzf over the pane's scrollback |

extrakto, tmux-fzf and `prefix S` need `fzf` (in `config/brew/Brewfile.cli`).
tmux-fingers needs its binary (`brew "tmux-fingers"` in `config/brew/Brewfile.core`).

Floating scratch panes are built into tmux 3.8 (`prefix Tab`), so there's
no floating-pane plugin.

## Claude Code

- **Shift+Enter** for a new line: `extended-keys` is on, so tmux passes
  modified keys through. If Shift+Enter still sends the message, turn on
  iTerm2 > Settings > Profiles > Keys > "Report keys using CSI u".
- **Bell:** set Claude Code's notification channel to the terminal bell. When
  Claude finishes or waits in another window, that window is highlighted in
  the status bar until you visit it.
- **`prefix y`** clears without typing Ctrl+C, so it never interrupts Claude.

## Numbering

Windows and panes start at 1, to match the keyboard.

- **Panes:** always numbered by position, so there are never gaps.
- **Windows:** gaps close automatically when a window is closed or moved away
  (`renumber-windows`). `prefix C-h` / `prefix C-l` move a window left or right.
- **Sessions:** unnamed sessions are renumbered to 1, 2, 3... (oldest first)
  whenever a session is created or closed (`renumber-sessions.sh`). Named
  sessions keep their name. Name any session a script targets, because a
  number can change.

## Session restore

Type `tmux` with no tmux server running and it restores the last save, then
attaches to the session you were in (the zsh function in
`zsh/functions/tmux`), so no empty session gets created. With a server already
running, or with any arguments, it's plain tmux. Restore by hand with
`prefix C-r`.

Continuum's own `@continuum-restore` stays off because it caused a
"Restoring" loop on server start. Its auto-save hook is written into
`status-right` in `status.conf`, because continuum skips adding it when it
wrongly thinks another tmux server is running.

## Scripted control

A script or agent can drive the dev server with
`tmux send-keys -t mysession:server ...` and reads it with
`tmux capture-pane -t mysession:server -p`. Keep the server in a window named
`server` in the `mysession` session. Windows renamed by hand keep their
name (automatic renaming stops for them), and nothing in this config
renames sessions or windows, so the target stays stable.

## Light and dark

catppuccin follows macOS: latte in Light mode, mocha in Dark mode.
`theme.sh` picks the flavor when tmux starts. iTerm2 tells tmux when the
appearance changes, and the `client-light-theme` / `client-dark-theme` hooks
in `plugins.conf` run `theme.sh light` or `theme.sh dark`. It reloads
catppuccin with the new flavor and colours the pane borders, copy selection
and bell to match. Run `~/.maclift/dotfiles/shell/tmux/theme.sh dark` to
switch by hand.
