#!/usr/bin/env bash
#
# maclift update: pulls the maclift clone (fast-forward only, never touching
# local changes), upgrades the outdated Homebrew packages maclift manages, and
# offers newer language versions for the asdf pins.
# bash 3.2 compatible.
# Meant to be sourced after lib/core.sh, selection.sh, ui.sh and install.sh.

# Set by update_pull (1 only when HEAD moved) and update_upgrade (failed ids,
# space separated).
UPDATE_PULLED=0
UPDATE_FAILED=""
UPDATE_PIN_FAILED=""
UPDATE_PIN_UPGRADED=0
UPDATE_PIN_LISTED=0
UPDATE_PIN_UPGRADED_NAMES=""

# _update_git <git args>...: git on the maclift clone.
_update_git() { "${MACLIFT_GIT:-git}" -C "$MACLIFT_DIR" "$@"; }

# update_pull <dry_run:0|1>
# Fast-forwards the maclift clone. Never stashes, resets or checks out. Prints
# one line saying what happened; returns 1 only when the pull itself failed.
update_pull() {
  local dry="$1" old new
  UPDATE_PULLED=0
  if ! _update_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "skip: $MACLIFT_DIR is not a git clone"
    return 0
  fi
  # --no-optional-locks: a read-only check must not take the index lock.
  if [ -n "$(_update_git --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    echo "skip pull: $MACLIFT_DIR has local changes"
    return 0
  fi
  if ! _update_git rev-parse '@{u}' >/dev/null 2>&1; then
    echo "skip pull: no upstream branch"
    return 0
  fi
  if [ "$dry" = "1" ]; then
    echo "would pull $MACLIFT_DIR"
    return 0
  fi
  old="$(_update_git rev-parse HEAD 2>/dev/null)"
  if ! _update_git pull --ff-only >>"${MACLIFT_LOG:-/dev/null}" 2>&1; then
    echo "✗ could not fast-forward $MACLIFT_DIR; resolve it by hand${MACLIFT_LOG:+ (see $MACLIFT_LOG)}"
    return 1
  fi
  new="$(_update_git rev-parse HEAD 2>/dev/null)"
  if [ "$old" = "$new" ]; then
    echo "✓ maclift is up to date"
    return 0
  fi
  UPDATE_PULLED=1
  echo "✓ pulled ${old:0:7}..${new:0:7}"
}

# update_managed
# Prints the brew:/cask: ids maclift manages (selection plus Brewfile.local
# extras) that are installed, one per line, without duplicates.
update_managed() {
  local id extras
  extras="$(install_brewfile_local 2>/dev/null)" || extras=""
  { selection_load; printf '%s\n' "$extras"; } | awk 'NF && !seen[$0]++' | while IFS= read -r id; do
    case "$id" in brew:* | cask:*) ;; *) continue ;; esac
    install_is_present "$id" && printf '%s\n' "$id"
  done
  return 0
}

# update_outdated <id>...
# Prints the ids that Homebrew reports as outdated. Tap names match by their
# last path part.
update_outdated() {
  local formulas casks id name list nl='
'
  formulas="$(_install_brew outdated --formula --quiet 2>/dev/null)" || formulas=""
  casks="$(_install_brew outdated --cask --quiet 2>/dev/null)" || casks=""
  for id in "$@"; do
    name="$(_install_name "$id")"
    case "$id" in
      brew:*) list="$formulas" ;;
      cask:*) list="$casks" ;;
      *) continue ;;
    esac
    # Compare base names; no `| grep -q` (SIGPIPE fails under pipefail).
    list="$(printf '%s\n' "$list" | sed 's|.*/||')"
    case "$nl$list$nl" in *"$nl${name##*/}$nl"*) printf '%s\n' "$id" ;; esac
  done
}

# update_upgrade <dry_run:0|1> <id>...
# Upgrades each id on its own; a failure never stops the rest. Sets
# UPDATE_FAILED (space separated ids).
update_upgrade() {
  local dry="$1" id name rc
  shift
  UPDATE_FAILED=""
  for id in "$@"; do
    name="$(_install_name "$id")"
    if [ "$dry" = "1" ]; then
      echo "would upgrade $id"
      continue
    fi
    ui_status run "upgrading $id"
    log_line "upgrading $id"
    rc=0
    case "$id" in
      cask:*) _install_brew upgrade --cask -- "$name" >>"${MACLIFT_LOG:-/dev/null}" 2>&1 || rc=$? ;;
      *) _install_brew upgrade -- "$name" >>"${MACLIFT_LOG:-/dev/null}" 2>&1 || rc=$? ;;
    esac
    if [ "$rc" = 0 ]; then
      ui_status ok "upgraded $id"
    else
      ui_status fail "could not upgrade $id"
      log_line "FAILED upgrading $id (exit $rc)"
      UPDATE_FAILED="${UPDATE_FAILED:+$UPDATE_FAILED }$id"
    fi
  done
}

# _update_pin_plugins: prints the pinned plugin names in pin-file order.
_update_pin_plugins() {
  local file line
  file="$(_pins_file)"
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '#'* | '') continue ;; esac
    printf '%s\n' "${line%% *}"
  done <"$file"
}

# _update_pin_candidate <plugin>: prints "old<TAB>new" when a newer version
# exists, else nothing.
_update_pin_candidate() {
  local old new
  old="$(pins_get "$1" 2>/dev/null)" || return 0
  new="$(pins_latest "$1" 2>/dev/null || true)"
  [ -n "$new" ] || return 0
  pins_is_newer "$old" "$new" && printf '%s\t%s\n' "$old" "$new"
  return 0
}

# update_pin_candidates
# Prints plugin<TAB>old<TAB>new for each pin with a newer version, in
# pin-file order (erlang before elixir).
update_pin_candidates() {
  local plugin cand
  while IFS= read -r plugin; do
    [ -n "$plugin" ] || continue
    cand="$(_update_pin_candidate "$plugin")"
    [ -z "$cand" ] || printf '%s\t%s\n' "$plugin" "$cand"
  done <<EOT
$(_update_pin_plugins)
EOT
}

# update_toolchains_refresh <dry_run:0|1>
# asdf-elixir keeps MIX_HOME per install, so a new Elixir (or Erlang) pin has
# no hex, rebar or phx_new. After such an upgrade, reinstalls the selected ones
# (install_run skips any whose --check already passes). A failure is added to
# UPDATE_PIN_FAILED and returns 1; it never reverts the pin.
update_toolchains_refresh() {
  local dry="$1" id ids=() sel nl='
'
  case " $UPDATE_PIN_UPGRADED_NAMES " in
    *" erlang "* | *" elixir "*) ;;
    *) return 0 ;;
  esac
  sel="$nl$(selection_load)$nl"
  for id in script:hex script:rebar script:phx_new; do
    case "$sel" in *"$nl$id$nl"*) ids+=("$id") ;; esac
  done
  [ "${#ids[@]}" -gt 0 ] || return 0
  if install_run "$dry" "${ids[@]}"; then
    return 0
  fi
  for id in $MACLIFT_FAILED; do
    UPDATE_PIN_FAILED="${UPDATE_PIN_FAILED:+$UPDATE_PIN_FAILED }$id"
  done
  return 1
}

# update_pins <dry_run:0|1>
# Offers each newer pin. A dry run or -y only lists them. An accepted pin is
# stored, installed, and reverted to the old version if the install fails.
# The elixir candidate is computed after erlang was decided. Returns 1 if any
# install failed (UPDATE_PIN_FAILED lists them); UPDATE_PIN_UPGRADED counts the
# pins that installed. pins_apply runs only if a pin was touched.
update_pins() {
  local dry="$1" plugin cand old new rc=0 listed=0 touched=0
  UPDATE_PIN_FAILED=""
  UPDATE_PIN_UPGRADED=0
  UPDATE_PIN_LISTED=0
  UPDATE_PIN_UPGRADED_NAMES=""
  # The loop reads plugin names on fd 3 so prompts and installs keep stdin.
  while IFS= read -r plugin <&3; do
    [ -n "$plugin" ] || continue
    cand="$(_update_pin_candidate "$plugin")"
    [ -n "$cand" ] || continue
    old="${cand%%$'\t'*}"
    new="${cand#*$'\t'}"
    echo "$plugin $old → $new"
    listed=$((listed + 1))
    UPDATE_PIN_LISTED="$listed"
    if [ "$dry" = "1" ] || [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; then
      continue
    fi
    ui_confirm "Upgrade $plugin to $new?" n || continue
    if ! _pins_store "$plugin" "$new"; then
      log_line "FAILED storing pin $plugin $new"
      echo "✗ $plugin $new could not be pinned; kept $old"
      UPDATE_PIN_FAILED="${UPDATE_PIN_FAILED:+$UPDATE_PIN_FAILED }$plugin"
      rc=1
      continue
    fi
    touched=1
    if install_run 0 "asdf:$plugin"; then
      UPDATE_PIN_UPGRADED=$((UPDATE_PIN_UPGRADED + 1))
      UPDATE_PIN_UPGRADED_NAMES="${UPDATE_PIN_UPGRADED_NAMES:+$UPDATE_PIN_UPGRADED_NAMES }$plugin"
    else
      _pins_store "$plugin" "$old"
      echo "✗ $plugin $new failed to install; kept $old"
      log_line "FAILED installing $plugin $new; kept $old"
      UPDATE_PIN_FAILED="${UPDATE_PIN_FAILED:+$UPDATE_PIN_FAILED }$plugin"
      rc=1
    fi
  done 3<<EOT
$(_update_pin_plugins)
EOT
  if [ "$listed" -gt 0 ] && { [ "$dry" = "1" ] || [ "${MACLIFT_ASSUME_YES:-}" = "1" ]; }; then
    echo "Run maclift update (without -y) to choose."
  elif [ "$listed" = 0 ]; then
    echo "Language versions are up to date"
  fi
  if [ "$touched" = "1" ]; then
    pins_apply 0 >>"${MACLIFT_LOG:-/dev/null}" 2>&1 || log_line "could not apply asdf pins"
  fi
  update_toolchains_refresh "$dry" || rc=1
  return "$rc"
}

# cmd_update <dry_run:0|1>
# Returns 1 if the pull or any upgrade failed.
cmd_update() {
  local dry="$1" rc=0 managed outdated n=0 id args=() stale="" failed=0
  local -a ids=()
  if [ "${NO_PULL:-0}" != "1" ]; then
    update_pull "$dry" || rc=1
    if [ "$UPDATE_PULLED" = "1" ]; then
      [ "${ASSUME_YES:-0}" != "1" ] || args+=(-y)
      [ "$dry" != "1" ] || args+=(--dry-run)
      [ "${FOR_REAL:-0}" != "1" ] || args+=(--for-real)
      if [ -x "$MACLIFT_DIR/maclift" ]; then
        log_line "re-running with the updated maclift"
        exec "$MACLIFT_DIR/maclift" update --no-pull ${args[@]+"${args[@]}"}
      fi
      # exec would fail (126) and end the run: finish with the code loaded.
      echo "note: $MACLIFT_DIR/maclift is not executable; finishing this update with the code already loaded"
      log_line "$MACLIFT_DIR/maclift not executable; not re-running"
    fi
  fi

  if [ "$dry" = "1" ]; then
    echo "package lists may be stale (dry run: brew update skipped)"
  else
    ui_status run "updating Homebrew"
    if _install_brew update >>"${MACLIFT_LOG:-/dev/null}" 2>&1; then
      ui_status ok "Homebrew updated"
    else
      ui_status fail "brew update failed; package lists may be stale"
      log_line "brew update failed"
      stale=" (package lists may be stale)"
    fi
  fi

  managed="$(update_managed)"
  # shellcheck disable=SC2046 # ids never contain spaces
  outdated="$(update_outdated $managed)"
  while IFS= read -r id; do
    [ -n "$id" ] && ids+=("$id")
  done <<EOT
$outdated
EOT
  n="${#ids[@]}"
  if [ "$n" = 0 ]; then
    echo "All packages are up to date$stale"
  else
    update_upgrade "$dry" ${ids[@]+"${ids[@]}"}
    [ -z "$UPDATE_FAILED" ] || rc=1
  fi

  update_pins "$dry" || rc=1

  local box=()
  if [ "$dry" = "1" ]; then
    box+=("Dry run: nothing was upgraded" "Would upgrade: $n" "Would upgrade pins: $UPDATE_PIN_LISTED")
  else
    for id in $UPDATE_FAILED; do failed=$((failed + 1)); done
    box+=("Upgraded: $((n - failed)) · failed: $failed")
  fi
  [ "$dry" = "1" ] || box+=("Language pins upgraded: $UPDATE_PIN_UPGRADED")
  for id in $UPDATE_FAILED; do box+=("✗ $id"); done
  for id in $UPDATE_PIN_FAILED; do box+=("✗ asdf:$id"); done
  [ "$rc" = 0 ] || box+=("Something failed; see the log: ${MACLIFT_LOG:-}")
  echo
  ui_box "${box[@]}"
  return "$rc"
}
