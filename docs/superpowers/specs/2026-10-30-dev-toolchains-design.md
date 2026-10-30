# Ready-to-code toolchains for Elixir, JS and Python

Date: 2026-10-30
Status: draft, awaiting approval

## Intent

Today maclift installs bare runtimes (Erlang, Elixir, Node, Python via asdf)
and stops. A developer then spends the first hour installing package managers
and project generators by hand, and loses some of them again on the next
runtime upgrade.

The bar: **open a new terminal after `maclift install` and these work with no
other step:**

```sh
mix phx.new my_app        # Elixir / Phoenix
pnpm create vite my_app   # JS
uv init my_app            # Python
```

And they **keep working** after `maclift update` moves a runtime version.

## Goals

1. Each language gets its package manager and project generator, installed in
   dependency order, as normal catalog items (visible in the picker, can be
   switched off, skipped when already present, one failure never stops the run).
2. Upgrading a runtime with `maclift update` reinstalls whatever was tied to
   the old version (Mix archives live inside each Elixir install).
3. `maclift doctor` proves each layer works, not only that a binary exists.
4. Python is owned by one tool: uv.

## Non-goals

- Installing Postgres or any database. Phoenix's default needs one; maclift
  only points to it (see "Closing notes").
- Global linters, formatters, test runners or frameworks (ruff, eslint,
  prettier, typescript…). They belong in each project, pinned there. `uvx`
  and `pnpm dlx` run them on demand.
- Managing Node versions with pnpm, or Python versions per project. uv and
  project files already do the latter.
- Bun, Deno, Yarn, Poetry, pipx. Can be added later as off-by-default items.

## Anti-goals (would make this a failure even if it works)

- A runtime upgrade silently breaks `mix phx.new` or `pnpm`.
- One failed Erlang build shows up as four unrelated red failures.
- Two copies of a tool fighting on PATH with no warning.
- A re-run removes or downgrades something the user already had (no
  regressions: an existing asdf Python is never removed).

## Decisions, as questions and answers

**Q1. In what order must things install?**
Each layer needs the one before it. The real chains are:

```
brew build libs ─► erlang ─► elixir ─► hex ─► rebar ─► phx_new
brew uv ─► uv-managed Python (default `python`)
brew pnpm            (standalone, needs nothing)
nodejs (asdf)        (independent; pnpm uses whichever node is on PATH)
```

The runner already runs kinds in the order brew → cask → mas → asdf →
dotfiles → script, and writes `~/.tool-versions` before any item runs
(`lib/install.sh` `install_run`). The new items are `script` items, so they
run after every runtime. Within the `script` kind they run in catalog order,
so the catalog lists them in chain order. Node is not needed by Phoenix
(esbuild and tailwind ship as standalone binaries), so no chain crosses
between languages.

**Q2. What does "rebar" mean here?**
The rebar3 that Mix uses to build Erlang deps: `mix local.rebar --force`,
on by default. A standalone `rebar3` command for pure Erlang projects is an
extra brew item, off by default.

**Q3. Where do hex, rebar and phx_new live, and why does it matter?**
asdf-elixir's `exec-env` sets `MIX_HOME=$ASDF_INSTALL_PATH/.mix` (checked on
this machine). So all three live inside one Elixir version and vanish when the
Elixir pin moves. Consequence: `maclift update`, after a successful elixir (or
erlang, which drags elixir) pin upgrade, reruns the Elixir tool items for the
new version. Their `--check` is version-aware for free, because it runs under
the new pin.

**Q4. Who owns Python: asdf or uv?**
uv. It downloads prebuilt Pythons in seconds; asdf compiles from source,
needs `xz`, and is the step that already failed on the work Mac
("python: no version found"), and is absent from this Mac's `~/.tool-versions`.
- New script item `python` (uv): `uv python install --default` (latest stable,
  exposes `python`/`python3` in `~/.local/bin`), then
  `uv python pin --global <version>`. Both flags verified on uv 0.11.6.
- `asdf:python` stays in the catalog, **off** by default. `brew:xz` goes off
  by default (only the asdf build needs it).
- Existing asdf Python installs and pins are left untouched. If both an asdf
  pin and the uv Python exist, doctor reports which one `python` resolves to.
- uv itself stays a brew item, so `brew upgrade` keeps it current.

**Q5. How is pnpm installed?**
Homebrew (`brew:pnpm`, on). Homebrew's pnpm 12 has no dependencies (verified:
`deps=[]`), so it does not pull a second Node, survives Node upgrades, and
updates with `brew upgrade`. Rejected: `npm i -g pnpm` (lives inside one asdf
Node and vanishes on upgrade, like hex); corepack (no longer shipped with
Node 25+, confirmed absent on Node 26); pnpm's own installer (a second update
channel next to brew).

**Q6. How do item scripts find `mix` on a fresh Mac?**
They run in plain bash, not the user's zsh, so asdf's shims may not be on
PATH during a first install. A shared helper (new, in `lib/`) puts
`${ASDF_DATA_DIR:-$HOME/.asdf}/shims` and `~/.local/bin` first on PATH and
runs from `$MACLIFT_HOME`, so `.tool-versions` resolves the pinned versions.
Every toolchain script sources it.

**Q7. What happens when a runtime failed?**
Each toolchain item declares the runtime it needs (`erlang`/`elixir` for the
Elixir tools, `uv` for python). If that runtime is not installed, the item is
reported as **skipped: needs elixir** (not failed), adds no extra red line, and
the run summary points at the real failure. Same when the user picked
`phx_new` but switched elixir off. Builder's call: how to declare the need
(a new catalog field or a header in the script).

**Q8. Global or per-project?**
Global only for package managers and project generators: hex, rebar,
phx_new, pnpm, uv's default Python. Nothing else.

**Q9. How does doctor prove it?**
New check "Toolchains", one line per enabled chain:
- Elixir: `mix hex.info` succeeds and `mix phx.new --version` prints a version.
- JS: `pnpm --version` and `node --version` both answer.
- Python: `python --version` answers and resolves to uv's Python (or to the
  asdf pin if the user chose that); warn when two `uv` binaries are on PATH
  (this Mac has brew uv plus `~/.local/bin/uv`).
Failures use the hint `maclift -y`; the Python and two-uv lines are
non-failing notes (Q15).

**Q10. What about Phoenix's database?**
Out of scope to install. When `phx_new` is installed and no `docker` or `psql`
is found, the closing notes say: Phoenix needs Postgres; turn on Docker Desktop
and use the `phoenix-docker` template, or install `postgresql@17` via brew.

**Q11. Dry run?**
Every new script supports the existing dry-run path (prints what it would run,
changes nothing) and `--check`, like `scripts/items/keys/*.sh`.

**Q12. Do Macs with a saved selection get the new items? (author's call)**
Yes, once. Catalog defaults only apply without a saved `selection.conf`, so
without this both existing Macs would never get the toolchains and doctor's
`maclift -y` hint would fix nothing.
- New: maclift records the catalog ids it has already offered (a "seen" list
  next to `selection.conf`). On the next run, any **default-on** id not yet
  seen is added to the selection and announced once ("New in maclift: hex,
  rebar, phx_new, pnpm, python (uv). Untick them in the picker if you don't
  want them."). Then all current ids are marked seen. A first-ever save marks
  everything seen, so fresh Macs are unaffected.
- Default changes never remove anything from a saved selection: `asdf:python`
  and `brew:xz` stay ticked where they were ticked. Only fresh selections get
  the new off defaults. (No-regression rule.)
- This is a separate step from `lib/migrate.sh`, which handles dotfiles links.

**Q13. What does `script:python` do when asdf Python is already there? (author's call)**
"The user chose asdf" means: `asdf:python` is in the selection **or** a
python line exists in the pins file. In that case `script:python --check`
passes when `python --version` works through asdf, and the script installs a
uv Python for uv's own use (`uv python install`) but does **not** pass
`--default` and does **not** pin globally, so nothing competes for `python`.
Otherwise it does the full Q4 setup. Doctor reports which one `python`
resolves to as an info line, never a failure.

**Q14. Need-check: installed or switched on? (author's call)**
Probe the machine, not the selection. An item runs when its runtime actually
works under the pins (`elixir --version` via the PATH helper for the Elixir
tools; `uv --version` for python). If elixir is installed but unticked, hex and
phx_new still run because the user ticked them. This works the same inside
`maclift update`, which only passes script ids. phx_new additionally needs hex
to be present; if hex failed, phx_new is skipped with "needs hex".

**Q15. Can doctor warn without failing? (author's call)**
Add a third, non-failing state to doctor: **note** (shown with its own
symbol, not counted in `DOCTOR_FAILS`, exit code unchanged). Used for
"python resolves to asdf/uv" and "two uv binaries on PATH". The note
for two uvs has its own hint: remove the standalone copy
(`rm ~/.local/bin/uv ~/.local/bin/uvx`) or run `brew uninstall uv`, whichever
the user doesn't want. Real breakage (mix/pnpm/python not answering) stays a
failure with hint `maclift -y`.

## Catalog changes (`catalog/30-languages.tsv`)

| Kind | Id | Default | Note |
|---|---|---|---|
| asdf | erlang | on | unchanged |
| asdf | elixir | on | unchanged |
| asdf | nodejs | on | unchanged |
| asdf | python | **off** | was on; uv owns Python |
| brew | uv | on | unchanged |
| brew | pnpm | on | new |
| brew | rebar3 | off | new, standalone Erlang build tool |
| brew | xz | **off** | was on; only for asdf Python |
| script | hex | on | new: `mix local.hex --force` |
| script | rebar | on | new: `mix local.rebar --force` |
| script | phx_new | on | new: `mix archive.install hex phx_new --force` |
| script | python | on | new: uv default Python + global pin |

Other existing brew extras unchanged. Script order in the file is exactly
hex → rebar → phx_new → python.

## Upgrade flow (`lib/update.sh`)

After `update_pins` installs a new elixir or erlang pin and `pins_apply`
runs, rerun `install_run 0 script:hex script:rebar script:phx_new` for the
items the user has enabled. If any fail, report them like other update
failures; the pin itself stays (the runtime works; the tools can be retried
with `maclift -y`). The Python default is refreshed only when the user runs
`maclift update` and uv reports a newer stable Python, offered with the same
yes/no prompt as asdf pins.

## Constraints

- bash 3.2 compatible, like all of `lib/`.
- Never source user files; parse with string ops (house rule in `lib/asdf.sh`).
- Tests in `tests/unit` with the existing fake-binary overrides
  (`MACLIFT_ASDF`, `MACLIFT_BREW`, plus new `MACLIFT_MIX`, `MACLIFT_UV`).
- Sandbox mode (`MACLIFT_HOME` ≠ `HOME`) must not write outside the sandbox
  except what brew/asdf already do system-wide.
- README "what you get" section and CONTRIBUTING updated.

## Follow-ups (not in this change)

- **Faster Erlang installs.** Erlang, Elixir and Node stay on asdf: projects
  pin exact versions in `.tool-versions`, and `_pins_elixir` pairs Elixir with
  the Erlang OTP major. The slow, fragile step is asdf building Erlang from
  source. Investigate precompiled OTP builds or mise (reads the same
  `.tool-versions`) as a separate project.

## Left to the builder

- Name and exact location of the PATH helper; how items declare their needed
  runtime (Q7); the file name and format of the "seen" list (Q12).
- Sandbox mode for the uv script: skip or redirect uv's writes the way the
  keys scripts handle sandboxes.
- Exact uv command sequence if `--default` behaviour differs across uv
  versions; detect and fail with a clear message rather than guess.
- Wording of skip/notes lines, following existing `maclift_note` style.
- Whether the Python-default refresh in `update` ships in the same change or
  a follow-up (it is the lowest-value part).
