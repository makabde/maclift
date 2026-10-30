# Ready-to-code Toolchains Implementation Plan

> **Superseded in part:** a follow-up removed `asdf:python` and `brew:xz` from the catalog (uv owns Python outright) and made "asdf chosen" mean only a python pin in the maclift pins file or `~/.tool-versions`; the off-by-default wording below is historical.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After `maclift install`, `mix phx.new`, `pnpm create vite` and `uv init` work in a new terminal, and keep working after `maclift update`.

**Architecture:** New `script` catalog items (hex, rebar, phx_new, python) run after all runtimes because the runner already orders kinds brew → cask → mas → asdf → dotfiles → script. A shared `lib/toolchain.sh` gives those scripts a PATH that finds asdf shims on a fresh Mac and a way to report "skipped: needs X" (exit 3) instead of failing. A "seen" list adds new default-on items to existing saved selections once. `update` reruns the Elixir tools after an erlang/elixir pin upgrade; `doctor` gets a non-failing note state and a toolchains check.

**Tech Stack:** bash 3.2, asdf, Homebrew, Mix, uv, pnpm; repo test framework `tests/lib/test-framework.sh` with stubs in `tests/stubs/`.

**Spec:** `docs/superpowers/specs/2026-10-30-dev-toolchains-design.md`

## Global Constraints

- bash 3.2 compatible everywhere (no `declare -A`, no `${x,,}`, no `mapfile`).
- Never `source` user files; parse with string ops / `conf_get` (house rule, `lib/asdf.sh` header).
- Every external tool is reached through an override variable so tests use stubs: existing `MACLIFT_ASDF`, `MACLIFT_BREW`; new `MACLIFT_MIX`, `MACLIFT_ELIXIR`, `MACLIFT_UV`, `MACLIFT_PNPM`, `MACLIFT_NODE`.
- Sandbox (`maclift_is_sandbox`, i.e. `MACLIFT_HOME` ≠ `HOME`): scripts write only under `$MACLIFT_HOME`, apart from what brew/asdf already do system-wide.
- A failing item never stops the run. A "needs X" skip is not a failure (not in `MACLIFT_FAILED`, no ✗ line).
- No global linters/formatters/frameworks are added (spec non-goal).
- Never remove anything from a saved selection; existing asdf Python is never touched.
- `shellcheck -x --severity=warning` clean (CI runs it on all shell files).
- Script items support `--check` (exit 0 = present). Dry run is handled by the runner (`install_run` prints "would install" and never calls the script).

## Review Focus

1. **Fresh Mac, no asdf shims on PATH yet:** `script:hex` must still find `mix` (Task 2 test `test_path_setup_prepends_shims`).
2. **Erlang build failed:** hex, rebar, phx_new each show "skipped (needs elixir)", the run summary counts them as skipped, exit code reflects only the erlang failure (Task 1 `test_needs_skip_not_failed`, Task 3 `test_hex_needs_elixir`).
3. **Selection saved order puts phx_new before hex** (hand-edited or appended): runner still runs hex first (Task 1 `test_script_catalog_order`).
4. **Existing Mac on 1.0.0 with a saved selection** runs `maclift -y`: new items are added and announced once, a second run adds nothing, `asdf:python` stays ticked (Task 5 `test_seen_migration_once`).
5. **User has asdf Python pinned:** `script:python` never runs `--default` or `pin --global` (Task 4 `test_python_asdf_mode`).

---

### Task 1: Runner supports "needs X" skips and catalog order for scripts

**Files:**
- Modify: `lib/install.sh` (`install_item`, `_install_item_body` script branch, `install_run` ordering and status)
- Modify: `lib/ui.sh:160-172` (`ui_status`)
- Modify: `maclift:600-620` (summary box)
- Test: `tests/unit/test_install.sh`, `tests/unit/test_ui.sh`

**Interfaces:**
- Produces:
  - Script exit code `3` = "skipped: needs a runtime". The script writes the missing thing's name (one word, e.g. `elixir`) to the file in `$MACLIFT_NEED_FILE` when set.
  - `install_item <id>` returns `0` ok, `1` failed, `3` needs-skip; on 3 sets global `MACLIFT_NEED_REASON` to the file's content.
  - Global `MACLIFT_NEEDS` (space-separated `id:reason` pairs) reset by `install_run`, like `MACLIFT_FAILED`.
  - `ui_status need "<label>" "<reason>"` prints `– skipped <label> (needs <reason>)` in the dim/yellow colour used by `run`.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_install.sh`:
  - `test_needs_skip_not_failed`: a temp script item (via a temp catalog file in a temp `MACLIFT_DIR` copy, following existing test patterns) that writes `elixir` to `$MACLIFT_NEED_FILE` and exits 3. Assert `install_run 0 script:x` returns 0, output contains `skipped script:x (needs elixir)`, `MACLIFT_FAILED` is empty, `MACLIFT_NEEDS` equals `script:x:elixir`.
  - `test_script_catalog_order`: two script items `a` (listed first in catalog) and `b`, each appending its name to a file. `install_run 0 script:b script:a` → file reads `a` then `b`.
  - In `tests/unit/test_ui.sh`: `ui_status need "script:hex" elixir` output contains `skipped script:hex (needs elixir)`.
- [ ] **Step 2: Run** `bash tests/unit/test_install.sh; bash tests/unit/test_ui.sh` → the new tests FAIL.
- [ ] **Step 3: Implement.**
  - `_install_item_body` script branch: create a temp file, export `MACLIFT_NEED_FILE` to it for the script call only, propagate the script's exit code.
  - `install_item`: keep rc; on 3 read the file into `MACLIFT_NEED_REASON`, `log_line "SKIPPED $1 (needs …)"`, return 3. Remove the temp file in all cases.
  - `install_run`: when building `ordered`, for kind `script` emit ids in `catalog_table` order (ids not in the catalog keep their given order after them). On rc 3: `ui_status need`, append to `MACLIFT_NEEDS`; not to `MACLIFT_FAILED`.
  - `maclift` summary: after the "Installed / skipped / failed" line, add one line per entry: `– <id> skipped (needs <reason>)`.
- [ ] **Step 4: Run** `bash tests/run_unit_tests.sh` → all PASS.
- [ ] **Step 5: Commit** `git commit -m "install: let script items skip when a runtime is missing; run scripts in catalog order"`

---

### Task 2: `lib/toolchain.sh` helper and stubs

**Files:**
- Create: `lib/toolchain.sh`
- Create: `tests/stubs/mix`, `tests/stubs/elixir`, `tests/stubs/uv`, `tests/stubs/pnpm`, `tests/stubs/node` (executable)
- Modify: `maclift:17` (add `toolchain` to the sourced lib list, after `asdf`)
- Test: `tests/unit/test_toolchain.sh` (new)

**Interfaces:**
- Produces (all in `lib/toolchain.sh`, sourced by item scripts after `lib/core.sh`):
  - `toolchain_path_setup`: prepends `${ASDF_DATA_DIR:-$HOME/.asdf}/shims` and `$MACLIFT_HOME/.local/bin` to `PATH` (no duplicates), exports it, `cd "$MACLIFT_HOME"` so `~/.tool-versions` pins resolve.
  - `toolchain_mix`, `toolchain_elixir`, `toolchain_uv`, `toolchain_pnpm`, `toolchain_node`: run `${MACLIFT_MIX:-mix}` etc. with `"$@"`.
  - `toolchain_needs <label> <cmd...>`: runs `<cmd...> >/dev/null 2>&1`; if it fails, writes `<label>` to `$MACLIFT_NEED_FILE` (when set), prints `needs <label>` and `exit 3`.
  - `toolchain_archives`: prints `toolchain_mix archive` output (lines like `* hex-2.2.1`).
- Stub contract (state in `$MACLIFT_STUB_DIR`, every call appended to `<tool>.calls`):
  - `elixir --version`: exit 0, or exit 1 when `$MACLIFT_STUB_DIR/no-elixir` exists. `elixir -e <code>` prints `$MACLIFT_STUB_DIR/mixhome`.
  - `mix archive`: prints `* <name>` per line of `mix.archives`. `mix local.hex --force` appends `hex-2.2.1`; `mix archive.install hex phx_new --force` appends `phx_new-1.8.1` (exits 1 if no `hex-` line); `mix local.rebar --force` creates executable `$MACLIFT_STUB_DIR/mixhome/elixir/1.20/rebar3`; `mix phx.new --version` prints `Phoenix installer v1.8.1` if `phx_new-` present else exit 1; `mix rebar.path` is not used.
  - `uv --version` prints `uv 0.11.6`; `uv python install [--default]` records the call and, with `--default`, creates executable `$UV_PYTHON_BIN_DIR/python` (default `$HOME/.local/bin`) that prints `Python 3.14.0` for `--version` and `3.14.0` for `-c …`; `uv python list --only-installed` prints `cpython-3.14.0-macos-aarch64-none` once any install ran; `uv python pin --global V` writes `V` to `${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version`.
  - `pnpm --version` → `12.16.1`; `node --version` → `v26.12.1`.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_toolchain.sh` (same header style as `test_asdf.sh`):
  - `test_path_setup_prepends_shims`: with `PATH=/usr/bin:/bin`, `ASDF_DATA_DIR=$T/asdf`, after `toolchain_path_setup` the PATH starts with `$T/asdf/shims:$MACLIFT_HOME/.local/bin:` and calling it twice does not duplicate them; `pwd` is `$MACLIFT_HOME`.
  - `test_needs_writes_reason`: in a subshell with `MACLIFT_NEED_FILE=$T/need`, `toolchain_needs elixir false` exits 3 and the file contains `elixir`; `toolchain_needs elixir true` returns 0.
- [ ] **Step 2: Run** `bash tests/unit/test_toolchain.sh` → FAIL (file missing).
- [ ] **Step 3: Implement** `lib/toolchain.sh` and the five stubs per the contracts above.
- [ ] **Step 4: Run** `bash tests/unit/test_toolchain.sh` → PASS.
- [ ] **Step 5: Commit** `git commit -m "toolchain: PATH and needs helpers for language tool items, with stubs"`

---

### Task 3: Elixir tools — hex, rebar, phx_new

**Files:**
- Create: `scripts/items/toolchains/hex.sh`, `rebar.sh`, `phx_new.sh`
- Modify: `catalog/30-languages.tsv` (append, in this order, after the brew lines):
  ```
  brew	rebar3	off	Standalone rebar3 for pure Erlang projects
  script	hex	on	Hex package manager for Elixir	toolchains/hex.sh
  script	rebar	on	rebar3 for Mix to build Erlang deps	toolchains/rebar.sh
  script	phx_new	on	Phoenix project generator (mix phx.new)	toolchains/phx_new.sh
  ```
- Test: `tests/unit/test_toolchains_elixir.sh` (new)

**Interfaces:**
- Consumes: `toolchain_path_setup`, `toolchain_needs`, `toolchain_mix`, `toolchain_archives` (Task 2); exit-3 contract (Task 1); `maclift_note` (`lib/core.sh`).
- Produces: script items `script:hex`, `script:rebar`, `script:phx_new`.

Behaviour (each script: `set -eo pipefail`, source `lib/core.sh` + `lib/toolchain.sh`, `maclift_init_paths`, `toolchain_path_setup`, same header comment style as `scripts/items/keys/*.sh`):

| Script | `--check` passes when | needs (in order) | install |
|---|---|---|---|
| hex | `toolchain_archives` has a `hex-` line | `elixir` → `toolchain_elixir --version` | `mix local.hex --force` |
| rebar | `elixir -e 'IO.puts(Mix.Utils.mix_home())'` gives `D`, and some `D/elixir/*/rebar3` is executable | `elixir` | `mix local.rebar --force` |
| phx_new | `toolchain_archives` has a `phx_new-` line | `elixir`, then `hex` → archives has `hex-` | `mix archive.install hex phx_new --force`; then if neither `docker` nor `psql` is on PATH, `maclift_note "Phoenix needs Postgres: turn on Docker Desktop and use the phoenix-docker template, or brew install postgresql@17"` |

The `--check` runs `toolchain_needs`-free: if elixir is missing, `--check` simply exits 1.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_toolchains_elixir.sh` (env: stubs via `MACLIFT_MIX`/`MACLIFT_ELIXIR`, fresh `MACLIFT_HOME`/`MACLIFT_STUB_DIR` per test like `test_keys.sh`):
  - `test_hex_installs_then_checks`: `--check` exits 1; run → exit 0, `mix.calls` contains `local.hex --force`; `--check` exits 0.
  - `test_hex_needs_elixir`: touch `no-elixir`; with `MACLIFT_NEED_FILE` set, run → exit 3, file contains `elixir`, `mix.calls` has no `local.hex`.
  - `test_rebar_installs_then_checks`: same shape with `local.rebar --force`.
  - `test_phx_new_needs_hex`: no hex archive → exit 3, reason `hex`.
  - `test_phx_new_installs_and_notes_postgres`: hex present, `PATH` without docker/psql, `MACLIFT_NOTES=$T/notes` → exit 0, `mix.calls` contains `archive.install hex phx_new --force`, notes contain `Phoenix needs Postgres`.
  - `test_phx_new_no_note_with_docker`: a fake `docker` on PATH → notes file empty.
  - `test_elixir_chain_through_runner`: `install_run 0 script:phx_new script:rebar script:hex` with all stubs → `mix.calls` order is `local.hex`, `local.rebar`, `archive.install`.
  - In `tests/unit/test_catalog.sh` nothing new is needed (it already validates kinds and fields); run it.
- [ ] **Step 2: Run** `bash tests/unit/test_toolchains_elixir.sh` → FAIL.
- [ ] **Step 3: Implement** the three scripts and catalog lines.
- [ ] **Step 4: Run** `bash tests/run_unit_tests.sh` → all PASS.
- [ ] **Step 5: Commit** `git commit -m "languages: install hex, rebar and phx_new after Elixir"`

---

### Task 4: Python through uv, pnpm, new defaults

**Files:**
- Create: `scripts/items/toolchains/python.sh`
- Modify: `catalog/30-languages.tsv`:
  - `asdf	python` default `on` → `off`
  - `brew	xz` default `on` → `off`, description `Compression library, only needed to build Python with asdf`
  - add after `brew	uv`: `brew	pnpm	on	Fast JavaScript package manager`
  - append last: `script	python	on	Default Python managed by uv	toolchains/python.sh`
- Modify: `lib/toolchain.sh` (add `toolchain_python_asdf_chosen`; it sources nothing new — the caller has sourced `lib/conf.sh`, `lib/catalog.sh`, `lib/asdf.sh`)
- Modify: `tests/unit/test_install.sh` / `test_selection.sh` only where they assert the old defaults (run them to find out).
- Test: `tests/unit/test_toolchains_python.sh` (new)

**Interfaces:**
- Consumes: Task 2 helpers (`toolchain_uv`, `toolchain_needs`), `_pins_read` and `_pins_file` from `lib/asdf.sh` (source `lib/catalog.sh` and `lib/asdf.sh`), `conf_get` from `lib/conf.sh`.
- Produces: `script:python`; function `toolchain_python_asdf_chosen` added to `lib/toolchain.sh` (doctor reuses it in Task 7) — true when `$MACLIFT_CONFIG_DIR/selection.conf` `MACLIFT_ITEMS` contains the word `asdf:python`, or `_pins_read "$(_pins_file)" python` succeeds.

Behaviour:
- Paths: in a sandbox export `UV_PYTHON_INSTALL_DIR=$MACLIFT_HOME/.local/share/uv/python`, `UV_PYTHON_BIN_DIR=$MACLIFT_HOME/.local/bin`, `XDG_CONFIG_HOME=$MACLIFT_HOME/.config`. Otherwise leave uv's defaults. `bin=${UV_PYTHON_BIN_DIR:-$HOME/.local/bin}`, `pinfile=${XDG_CONFIG_HOME:-$HOME/.config}/uv/.python-version`.
- needs: `uv` → `toolchain_uv --version`.
- **asdf mode** (`toolchain_python_asdf_chosen`): `--check` passes when `uv python list --only-installed` prints at least one line. Install: `uv python install` (no `--default`, no pin).
- **uv mode**: `--check` passes when `"$bin/python" --version` succeeds **and** `$pinfile` exists. Install: `uv python install --default`; `v="$("$bin/python" -c 'import platform; print(platform.python_version())')"`; validate `v` with `_pins_version_ok`; `uv python pin --global "$v"`. If `$bin/python` is missing after install, fail with `uv did not create $bin/python; check uv python install --default on this uv version` (spec: detect, don't guess).

- [ ] **Step 1: Write failing tests** in `tests/unit/test_toolchains_python.sh`:
  - `test_python_uv_mode`: no selection, no pins → run exit 0; `uv.calls` contains `python install --default` and `python pin --global 3.14.0`; pinfile content `3.14.0`; `--check` exit 0.
  - `test_python_asdf_mode`: `conf_set selection.conf MACLIFT_ITEMS "asdf:python script:python"` → run exit 0; `uv.calls` contains `python install` but not `--default` and not `pin`.
  - `test_python_asdf_mode_by_pin`: no selection, pins file has `python 3.13.5` → same assertions as above.
  - `test_python_needs_uv`: `MACLIFT_UV=/nonexistent` → exit 3, reason `uv`.
  - `test_python_sandbox_paths`: `HOME` ≠ `MACLIFT_HOME` → `$MACLIFT_HOME/.local/bin/python` exists, nothing created under the test's `HOME`.
  - `test_new_defaults` (in `tests/unit/test_selection.sh`): `selection_defaults` contains `brew:pnpm`, `script:hex`, `script:rebar`, `script:phx_new`, `script:python` and does not contain `asdf:python` or `brew:xz`.
- [ ] **Step 2: Run** the two test files → FAIL.
- [ ] **Step 3: Implement** the script and catalog changes; fix any older test that asserted `asdf:python`/`brew:xz` as defaults (change the expectation, keep the test's intent).
- [ ] **Step 4: Run** `bash tests/run_unit_tests.sh && bash tests/run_integration_tests.sh` → all PASS.
- [ ] **Step 5: Commit** `git commit -m "languages: uv owns Python, add pnpm; asdf python and xz off by default"`

---

### Task 5: Offer new default-on items to saved selections once

**Files:**
- Modify: `lib/selection.sh`
- Modify: `maclift` (right after the `SELECTED` load loop, ~line 341)
- Test: `tests/unit/test_selection.sh`, `tests/integration/test_flow.sh`

**Interfaces:**
- Produces (in `lib/selection.sh`):
  - Seen list stored in `$MACLIFT_CONFIG_DIR/selection.conf` key `MACLIFT_SEEN` (space-separated ids) via `conf_set` / `conf_get`.
  - `SELECTION_ADDED_SINCE_1_0="brew:pnpm brew:rebar3 script:hex script:rebar script:phx_new script:python"` — used only when a saved selection has no `MACLIFT_SEEN` yet: the baseline seen list is then every catalog id except these.
  - `selection_new_defaults`: prints ids that are in `selection_defaults`, not in the seen list (or baseline), and not already saved. Prints nothing when there is no saved `MACLIFT_ITEMS`.
  - `selection_mark_seen`: sets `MACLIFT_SEEN` to all current catalog ids.
  - `selection_save` calls `selection_mark_seen` at the end.

Wiring in `maclift`: after `SELECTED` is built, `_new="$(selection_new_defaults)"`. If not empty: append each to `SELECTED`, print `New in maclift: <ids joined by ", ">. Untick them in the picker if you don't want them.` If `ASSUME_YES=1` and not a dry run, `selection_save $SELECTED` right away (the interactive path saves after the picker as today). A dry run announces but saves nothing.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_selection.sh`:
  - `test_seen_migration_once`: save `MACLIFT_ITEMS="brew:git asdf:python brew:xz"` with no `MACLIFT_SEEN` → `selection_new_defaults` prints exactly the default-on ids from `SELECTION_ADDED_SINCE_1_0` (`brew:pnpm script:hex script:rebar script:phx_new script:python`, not `brew:rebar3`) and nothing older (e.g. not `brew:bat` even though it is default-on). After `selection_save brew:git asdf:python brew:xz $(selection_new_defaults)` → `selection_new_defaults` prints nothing, saved items still contain `asdf:python` and `brew:xz`.
  - `test_no_offer_on_fresh_mac`: no `selection.conf` → prints nothing.
  - `test_unticked_stays_unticked`: after marking seen, save without `script:hex` → `selection_new_defaults` prints nothing.
  - In `tests/integration/test_flow.sh`, `test_existing_selection_gets_new_items`: write a 1.0.0-style `selection.conf`, run `maclift -y --dry-run` → output contains `New in maclift:` and `selection.conf` is unchanged; run `maclift -y` (with the flow's existing stubs) → `selection.conf` contains `script:hex`; a second run's output has no `New in maclift:`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash tests/run_unit_tests.sh && bash tests/run_integration_tests.sh` → PASS.
- [ ] **Step 5: Commit** `git commit -m "selection: add new default-on items to saved selections once"`

---

### Task 6: `update` reinstalls Elixir tools after a runtime upgrade

**Files:**
- Modify: `lib/update.sh` (`update_pins`)
- Test: `tests/unit/test_update.sh`

**Interfaces:**
- Consumes: `install_run` (Task 1 return semantics), `selection_load`.
- Produces: global `UPDATE_PIN_UPGRADED_NAMES` (space-separated plugins whose new pin installed), set by `update_pins`; `update_toolchains_refresh <dry>`: if `UPDATE_PIN_UPGRADED_NAMES` contains `erlang` or `elixir`, runs `install_run "$dry"` on the ids from `script:hex script:rebar script:phx_new` that are in `selection_load`; on failure appends them to `UPDATE_PIN_FAILED` and returns 1. Called at the end of `update_pins`, after `pins_apply`.

Note: `install_run` will skip items whose `--check` passes — correct, because under the new pin `MIX_HOME` is the new install's, so the check fails exactly when a reinstall is needed. A failed tool reinstall does **not** revert the pin.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_update.sh` (reuse its existing stub setup):
  - `test_elixir_upgrade_reinstalls_tools`: selection contains `asdf:elixir script:hex script:phx_new`; newer elixir available; accept → `mix.calls` contains `local.hex --force` then `archive.install hex phx_new --force`, and no `local.rebar` (not selected).
  - `test_node_upgrade_leaves_tools`: only nodejs upgrades → no `mix.calls`.
  - `test_tool_failure_keeps_pin`: make the mix stub fail `local.hex` (`$MACLIFT_STUB_DIR/mix.fail-hex`) → pin is the new version, return code 1, `UPDATE_PIN_FAILED` contains `script:hex`.
- [ ] **Step 2: Run** `bash tests/unit/test_update.sh` → FAIL.
- [ ] **Step 3: Implement** (add `mix.fail-hex` support to the mix stub).
- [ ] **Step 4: Run** `bash tests/run_unit_tests.sh` → PASS.
- [ ] **Step 5: Commit** `git commit -m "update: reinstall hex, rebar and phx_new after an Elixir or Erlang upgrade"`

---

### Task 7: Doctor note state and toolchains check

**Files:**
- Modify: `lib/doctor.sh` (`_doctor_note`, `doctor_check_toolchains`, `DOCTOR_CHECKS`)
- Modify: `lib/ui.sh` (`ui_status note`)
- Test: `tests/unit/test_doctor.sh`

**Interfaces:**
- Consumes: Task 2 helpers (run inside a subshell so doctor's own PATH/cwd are untouched), `selection_load`, `toolchain_python_asdf_chosen` (Task 4).
- Produces:
  - `ui_status note "<label>"` → `• <label>` in a blue colour.
  - `_doctor_note <label> [hint]`: prints the note and, when given, `  hint: <hint>`; never touches `DOCTOR_FAILS`.
  - `DOCTOR_CHECKS="brew path shell repo_link links asdf toolchains git ssh"`.
  - `doctor_check_toolchains`: for each chain enabled in `selection_load`:
    - Elixir (`script:phx_new` or `script:hex` selected): fail `"Elixir tools: <what> missing"` fix `maclift -y` unless `mix archive` lists `hex-` (if hex selected) and `mix phx.new --version` succeeds (if phx_new selected).
    - JS (`brew:pnpm` selected): fail unless `pnpm --version` and `node --version` both succeed.
    - Python (`script:python` selected): fail unless `python --version` succeeds. Then note `python is <path> (uv)` or `(asdf)` based on whether the resolved path is under the asdf shims dir.
    - Two uv: walk the PATH (use `MACLIFT_DOCTOR_PATH` when set, as other checks do) and collect distinct real paths of executable `uv`; if more than one, `_doctor_note "two uv binaries on PATH: <a>, <b>" "rm ~/.local/bin/uv ~/.local/bin/uvx, or brew uninstall uv — keep one"`.
    - All good → `_doctor_ok "Language tools ready"`. No chain selected → `_doctor_ok "No language tools selected"`.

- [ ] **Step 1: Write failing tests** in `tests/unit/test_doctor.sh`:
  - `test_toolchains_all_ready`: stubs with hex + phx_new archives, pnpm/node stubs, a stub `python` on PATH → output contains `Language tools ready`, `DOCTOR_FAILS` 0.
  - `test_toolchains_phx_missing`: no phx_new archive → `✗` line contains `phx_new`, fix `maclift -y`, `DOCTOR_FAILS` 1.
  - `test_two_uv_is_note_not_fail`: two dirs each with an executable `uv` in `MACLIFT_DOCTOR_PATH` → output contains `two uv binaries`, `DOCTOR_FAILS` 0.
  - `test_note_does_not_count`: `_doctor_note x` leaves `DOCTOR_FAILS` unchanged.
- [ ] **Step 2: Run** `bash tests/unit/test_doctor.sh` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bash tests/run_unit_tests.sh` → PASS.
- [ ] **Step 5: Commit** `git commit -m "doctor: non-failing notes and a language tools check"`

---

### Task 8: Docs, lint, full verification

**Files:**
- Modify: `README.md` (the section listing what maclift installs: add "Elixir comes with hex, rebar and the Phoenix generator; JavaScript with pnpm; Python is managed by uv"; mention `maclift update` keeps Elixir tools working after an upgrade)
- Modify: `CONTRIBUTING.md` (where item scripts are described: the exit-3 "needs" contract, `lib/toolchain.sh`, and the new stub overrides)

- [ ] **Step 1:** Edit both docs.
- [ ] **Step 2: Run** `bash tests/run_unit_tests.sh && bash tests/run_integration_tests.sh` → all PASS (includes `test_docs.sh`).
- [ ] **Step 3: Run** `git ls-files -z '*.sh' maclift install 'tests/stubs/*' | xargs -0 shellcheck -x --severity=warning` → no output.
- [ ] **Step 4: Manual smoke (real Mac, optional, user-run):** `./maclift --dry-run -y` shows `New in maclift:` and `would install script:hex` etc.; `./maclift doctor` shows the toolchains line and the two-uv note on this Mac.
- [ ] **Step 5: Commit** `git commit -m "docs: language toolchains"`

---

## Deferred (spec "left to the builder")

- Refreshing uv's default Python from `maclift update` — lowest value; follow-up.
- Faster Erlang installs — separate project (spec Follow-ups).
