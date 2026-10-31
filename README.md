# maclift

**liftoff for your new Mac**

maclift sets up a fresh Mac in one run. You pick what you want from a catalog
of command-line tools, apps, fonts, languages and dotfiles, and maclift
installs it. It pins your language versions in a small file, like a lockfile
for your Mac's toolchain, so the next Mac gets the same versions. Every run is
safe to repeat, and every file it replaces is backed up first.

![maclift demo](docs/demo.gif)

## Install

Run this in Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/makabde/maclift/v1.1.1/install | bash
```

Want to read the script first? It is short:
[install](https://github.com/makabde/maclift/blob/v1.1.1/install).

The installer downloads that tagged release to `~/maclift` and starts it.
After that, `maclift update` follows the `main` branch. To skip all
questions and reuse your saved answers, add `-y`:

```sh
curl -fsSL https://raw.githubusercontent.com/makabde/maclift/v1.1.1/install | bash -s -- -y
```

To use another folder, set `MACLIFT_DIR` for `bash`, after the pipe:

```sh
curl -fsSL https://raw.githubusercontent.com/makabde/maclift/v1.1.1/install | MACLIFT_DIR=~/somewhere bash
```

Or clone it yourself:

```sh
git clone https://github.com/makabde/maclift.git ~/maclift
cd ~/maclift && ./maclift
```

## What you get

You choose groups, then items inside each group.

- **Core**: shell, git, asdf and build dependencies (always on).
- **Command-line tools**: modern replacements for everyday tools.
- **Languages**: runtimes via asdf, plus build extras. Elixir comes with hex,
  rebar and the Phoenix generator (`mix phx.new`); JavaScript with pnpm;
  Python is managed by uv. If a tool needs a runtime that is not installed,
  it shows as "skipped (needs X)" instead of failing. `maclift update` keeps
  the Elixir tools working after an Elixir or Erlang upgrade.
- **Developer apps**: terminal, editor and design tools.
- **Productivity**: window management, launchers and chat.
- **Browsers**: web browsers.
- **Fonts**: programming fonts.
- **tmux**: terminal multiplexer and its config.
- **Dotfiles**: link config files into your home folder.
- **Keys & signing**: SSH key, signed commits and a second git identity
  (off by default).

## Commands

maclift is not added to your `PATH`. Run it from its folder:
`~/maclift/maclift <command>`, or `./maclift <command>` inside that folder.
Below, `maclift <command>` is short for that.

- `maclift` : pick what you want and install it.
- `maclift doctor` : check this Mac and say how to fix what is wrong.
- `maclift add <name>...` : install packages and remember them.
- `maclift update` : pull maclift, upgrade packages, offer newer languages.
- `maclift snapshot` : save installed packages maclift doesn't know yet.
- `maclift restore` : put back dotfiles from a backup (`--run <id>`).
- `maclift migrate` : move links from an old dotfiles folder (`--from`,
  `--rollback`).

Most commands take `--dry-run` (show what would happen) and `-y` (ask
nothing). Run `maclift --help` for the full list.

## Make it yours

Your own settings live in `~/.config/maclift/`, outside the repo, so updates
never touch them.

- `user.conf`: your name, email and GitHub user. See
  `templates/user.conf.example`.
- `selection.conf`: the groups and items you chose. Edit it or let maclift
  write it.
- `Brewfile.local`: extra `brew`, `cask` and `mas` lines that are only yours.
- `dotfiles/`: files here replace the ones maclift ships.
- `hooks/pre-install.sh` and `hooks/post-install.sh`: your own scripts, run
  before and after the install. A failing pre-install hook stops the run.

To start from someone else's choices, give maclift their selection file or
URL:

```sh
./maclift --from https://example.com/ada/selection.conf
```

## Safety

- Backups: before maclift replaces a file, it copies it to
  `~/.config/maclift/backups/<run-id>/`. `maclift restore` puts it back.
- `--dry-run` shows what would happen and changes nothing outside
  `~/.config/maclift`.
- Config files are parsed, never sourced. A bad line cannot run code.
- No telemetry. Besides Homebrew, asdf, the sources of the packages you
  picked and `gh` on your own GitHub account (key uploads), maclift only
  downloads the release tarball once (the installer), git-fetches the maclift
  repo (first run and `maclift update`), and fetches a `--from <url>`
  selection file if you give one. Nothing else.

## Contributing

Adding a package is one line in a catalog file. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

maclift began as a rewrite of [alrra/dotfiles](https://github.com/alrra/dotfiles)
by Cătălin Mariș. Thank you. Both are under the MIT License.
