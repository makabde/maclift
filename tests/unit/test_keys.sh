#!/usr/bin/env bash
#
# Unit tests for the Keys & signing group and scripts/items/keys/ssh-key.sh
# (all external tools are stubs; nothing touches the real ~/.ssh)
#

# shellcheck disable=SC2088 # literal ~/ paths are the values under test
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=tests/lib/test-framework.sh
source "$SCRIPT_DIR/../lib/test-framework.sh"
# shellcheck source=lib/core.sh
source "$PROJECT_ROOT/lib/core.sh"
# shellcheck source=lib/conf.sh
source "$PROJECT_ROOT/lib/conf.sh"
# shellcheck source=lib/catalog.sh
source "$PROJECT_ROOT/lib/catalog.sh"
# shellcheck source=lib/install.sh
source "$PROJECT_ROOT/lib/install.sh"

export MACLIFT_DIR="$PROJECT_ROOT"
TMP_DIR="$(mktemp -d)"

# fresh_env: new temp MACLIFT_HOME/HOME/stub dir, stubs wired in, user.conf written.
fresh_env() {
  MACLIFT_HOME="$(mktemp -d "$TMP_DIR/home.XXXXXX")"
  export MACLIFT_HOME HOME="$MACLIFT_HOME"
  MACLIFT_STUB_DIR="$(mktemp -d "$TMP_DIR/stub.XXXXXX")"
  export MACLIFT_STUB_DIR
  export MACLIFT_SSH_KEYGEN="$PROJECT_ROOT/tests/stubs/ssh-keygen"
  export MACLIFT_SSH_ADD="$PROJECT_ROOT/tests/stubs/ssh-add"
  export MACLIFT_GH="$PROJECT_ROOT/tests/stubs/gh"
  export MACLIFT_HAS_TTY=1
  export MACLIFT_GPG="$PROJECT_ROOT/tests/stubs/gpg"
  export MACLIFT_GPGCONF="$PROJECT_ROOT/tests/stubs/gpgconf"
  export MACLIFT_BREW="$PROJECT_ROOT/tests/stubs/brew"
  export GNUPGHOME="$MACLIFT_HOME/.gnupg"
  unset MACLIFT_NOTES
  maclift_init_paths
  mkdir -p "$MACLIFT_CONFIG_DIR"
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_EMAIL "test@example.com"
  conf_set "$MACLIFT_CONFIG_DIR/user.conf" MACLIFT_NAME "Test User"
  mkdir -p "$MACLIFT_STUB_DIR/prefix/bin"
  echo "$MACLIFT_STUB_DIR/prefix" >"$MACLIFT_STUB_DIR/brew.prefix"
  : >"$MACLIFT_STUB_DIR/gpg.secret"
  SSH_KEY_SH="$PROJECT_ROOT/scripts/items/keys/ssh-key.sh"
  GPG_SH="$PROJECT_ROOT/scripts/items/keys/gpg-signing.sh"
  UCONF="$MACLIFT_CONFIG_DIR/user.conf"
}

test_catalog() {
  test_suite "keys catalog"
  assert_contains "$(catalog_items keys)" "script:ssh-key" "keys lists script:ssh-key"
  assert_contains "$(catalog_items keys)" "brew:gh" "keys lists brew:gh"
  assert_equals "keys" "$(catalog_item_field brew:gh group)" "brew:gh is in keys"
  assert_equals "keys/ssh-key.sh" "$(catalog_item_field script:ssh-key args)" "ssh-key args"
  assert_equals "off" "$(catalog_group_field keys default)" "keys group is default off"
  assert_equals "" "$(catalog_items cli | grep -E 'brew:(gh|gnupg|pinentry-mac)$' || true)" "cli no longer lists gh, gnupg, pinentry-mac"
}

test_check() {
  test_suite "install_is_present script:ssh-key"
  fresh_env
  assert_command_fails "install_is_present script:ssh-key" "absent without a key"
  mkdir -p "$MACLIFT_HOME/.ssh"
  : >"$MACLIFT_HOME/.ssh/id_ed25519"
  assert_command_succeeds "install_is_present script:ssh-key" "present with a key"
  assert_command_fails "install_is_present script:not-in-catalog" "empty args is not present"
}

test_no_tty() {
  test_suite "ssh-key.sh without a tty"
  fresh_env
  local out rc=0
  out="$(MACLIFT_HAS_TTY=0 bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_command_succeeds "[ '$rc' -ne 0 ]" "exits non-zero"
  assert_contains "$out" "needs a terminal to set the key's passphrase; run maclift from a terminal" "explains why"
  assert_command_fails "[ -e '$MACLIFT_HOME/.ssh/id_ed25519' ]" "no key created"
}

test_ssh_no_email() {
  test_suite "ssh-key.sh without an email"
  fresh_env
  conf_set "$UCONF" MACLIFT_EMAIL ""
  local out rc=0
  out="$(bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exits 1"
  assert_contains "$out" "email missing in $UCONF" "explains"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/ssh-keygen.calls' ]" "ssh-keygen not called"
}

test_logged_in() {
  test_suite "ssh-key.sh with a tty and gh logged in"
  fresh_env
  : >"$MACLIFT_STUB_DIR/gh.loggedin"
  bash "$SSH_KEY_SH" >/dev/null 2>&1
  assert_file_exists "$MACLIFT_HOME/.ssh/id_ed25519" "key created"
  assert_file_exists "$MACLIFT_HOME/.ssh/id_ed25519.pub" "public key created"
  assert_contains "$(cat "$MACLIFT_STUB_DIR/ssh-keygen.calls")" "-t ed25519 -C test@example.com -f $MACLIFT_HOME/.ssh/id_ed25519" "email used as comment"
  assert_command_succeeds "grep -qF -- '--apple-use-keychain $MACLIFT_HOME/.ssh/id_ed25519' '$MACLIFT_STUB_DIR/ssh-add.calls'" "added to the keychain"
  assert_command_fails "grep -F -- ' -N' '$MACLIFT_STUB_DIR/ssh-keygen.calls'" "keygen never given -N (passphrase asked)"
  assert_command_succeeds "grep -qE '^ssh-key add $MACLIFT_HOME/.ssh/id_ed25519.pub --title maclift .+' '$MACLIFT_STUB_DIR/gh.calls'" "uploaded the .pub with a title"
  assert_equals "600" "$(stat -f '%Lp' "$MACLIFT_HOME/.ssh/config" 2>/dev/null || stat -c '%a' "$MACLIFT_HOME/.ssh/config")" "new config mode 600"
  assert_equals "700" "$(stat -f '%Lp' "$MACLIFT_HOME/.ssh" 2>/dev/null || stat -c '%a' "$MACLIFT_HOME/.ssh")" ".ssh mode 700"
  assert_contains "$(cat "$MACLIFT_HOME/.ssh/config")" "# added by maclift" "config block marked"
  rm -f "$MACLIFT_HOME/.ssh/id_ed25519" "$MACLIFT_HOME/.ssh/id_ed25519.pub"
  bash "$SSH_KEY_SH" >/dev/null 2>&1
  assert_equals "1" "$(grep -c 'UseKeychain yes' "$MACLIFT_HOME/.ssh/config")" "UseKeychain once after two runs"
}

test_logged_out() {
  test_suite "ssh-key.sh with gh logged out"
  fresh_env
  local out rc=0
  out="$(bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exits 0"
  assert_contains "$out" "gh ssh-key add" "prints the later command"
  assert_file_exists "$MACLIFT_STUB_DIR/gh.calls" "gh was consulted"
  assert_command_fails "grep -q 'ssh-key add' '$MACLIFT_STUB_DIR/gh.calls'" "no upload attempted"
}

test_upload_fails() {
  test_suite "ssh-key.sh with a failing upload"
  fresh_env
  : >"$MACLIFT_STUB_DIR/gh.loggedin"
  : >"$MACLIFT_STUB_DIR/gh.addfail"
  local rc=0 out
  out="$(bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "a failed upload is a note, not a failure"
  assert_contains "$out" "Could not upload the SSH key" "note printed"
}

test_existing_config() {
  test_suite "ssh-key.sh keeps an existing UseKeychain setting"
  fresh_env
  mkdir -p "$MACLIFT_HOME/.ssh"
  printf 'Host *\n  UseKeychain no\n' >"$MACLIFT_HOME/.ssh/config"
  bash "$SSH_KEY_SH" >/dev/null 2>&1
  assert_equals "Host *
  UseKeychain no" "$(cat "$MACLIFT_HOME/.ssh/config")" "config untouched"
}

test_orphan_pub() {
  test_suite "ssh-key.sh with an orphan public key"
  fresh_env
  mkdir -p "$MACLIFT_HOME/.ssh"
  printf 'my precious pub\n' >"$MACLIFT_HOME/.ssh/id_ed25519.pub"
  local rc=0 out
  out="$(bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exits 1"
  assert_contains "$out" "without its private key" "explains"
  assert_equals "my precious pub" "$(cat "$MACLIFT_HOME/.ssh/id_ed25519.pub")" ".pub unchanged"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/ssh-keygen.calls' ]" "keygen not run"
}

test_existing_key() {
  test_suite "ssh-key.sh with an existing private key"
  fresh_env
  mkdir -p "$MACLIFT_HOME/.ssh"
  printf 'my private key\n' >"$MACLIFT_HOME/.ssh/id_ed25519"
  local rc=0 out
  out="$(bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exits 0"
  assert_contains "$out" "already exists" "says nothing to do"
  assert_equals "my private key" "$(cat "$MACLIFT_HOME/.ssh/id_ed25519")" "key unchanged"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/ssh-keygen.calls' ]" "keygen not run"
}

test_commented_config() {
  test_suite "ssh-key.sh ignores a commented UseKeychain"
  fresh_env
  mkdir -p "$MACLIFT_HOME/.ssh"
  printf '# UseKeychain yes\n' >"$MACLIFT_HOME/.ssh/config"
  bash "$SSH_KEY_SH" >/dev/null 2>&1
  assert_contains "$(cat "$MACLIFT_HOME/.ssh/config")" "  UseKeychain yes" "block appended"
}

test_gpg_catalog() {
  test_suite "gpg-signing catalog"
  assert_contains "$(catalog_items keys)" "script:gpg-signing" "keys lists script:gpg-signing"
  assert_equals "keys/gpg-signing.sh" "$(catalog_item_field script:gpg-signing args)" "gpg-signing args"
}

test_gpg_reuse() {
  test_suite "gpg-signing.sh reuses an existing key"
  fresh_env
  printf 'AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555 other@example.com\nFFFF1111BBBB2222CCCC3333DDDD4444EEEE5555 test@example.com\n' >"$MACLIFT_STUB_DIR/gpg.secret"
  assert_command_fails "bash '$GPG_SH' --check" "check fails before the run"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_command_fails "grep -q quick-generate-key '$MACLIFT_STUB_DIR/gpg.calls'" "no key generated"
  assert_equals "FFFF1111BBBB2222CCCC3333DDDD4444EEEE5555" "$(conf_get "$UCONF" MACLIFT_SIGNING_KEY)" "fingerprint saved"
  assert_command_succeeds "bash '$GPG_SH' --check" "check passes after the run"
  assert_equals "700" "$(stat -f '%Lp' "$MACLIFT_HOME/.gnupg" 2>/dev/null || stat -c '%a' "$MACLIFT_HOME/.gnupg")" ".gnupg mode 700"
}

test_gpg_dead_keys() {
  test_suite "gpg-signing.sh skips expired, revoked and look-alike keys"
  fresh_env
  printf 'EXPIRED000000000000000000000000000000AA test@example.com e\nGOODKEY000000000000000000000000000000BB test@example.com u\n' >"$MACLIFT_STUB_DIR/gpg.secret"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_equals "GOODKEY000000000000000000000000000000BB" "$(conf_get "$UCONF" MACLIFT_SIGNING_KEY)" "valid second key reused"
  assert_command_fails "grep -q quick-generate-key '$MACLIFT_STUB_DIR/gpg.calls'" "nothing generated"

  fresh_env
  printf 'REVOKED000000000000000000000000000000CC test@example.com r\n' >"$MACLIFT_STUB_DIR/gpg.secret"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_command_succeeds "grep -q quick-generate-key '$MACLIFT_STUB_DIR/gpg.calls'" "revoked-only: new key generated"
  assert_equals "FAKEFPR0000000000000000000000000000NEW" "$(conf_get "$UCONF" MACLIFT_SIGNING_KEY)" "new key saved"

  fresh_env
  printf 'UIDREVK000000000000000000000000000000EE test@example.com u r\n' >"$MACLIFT_STUB_DIR/gpg.secret"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_command_succeeds "grep -q quick-generate-key '$MACLIFT_STUB_DIR/gpg.calls'" "valid key with a revoked uid: new key generated"
  assert_equals "FAKEFPR0000000000000000000000000000NEW" "$(conf_get "$UCONF" MACLIFT_SIGNING_KEY)" "revoked-uid key not reused"

  fresh_env
  conf_set "$UCONF" MACLIFT_EMAIL "ada@example.com"
  printf 'NADAKEY000000000000000000000000000000DD nada@example.com u\n' >"$MACLIFT_STUB_DIR/gpg.secret"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_command_succeeds "grep -q quick-generate-key '$MACLIFT_STUB_DIR/gpg.calls'" "look-alike email not reused"
}

test_gpg_agent_kill_fails() {
  test_suite "gpg-signing.sh keeps the key when gpgconf fails"
  fresh_env
  printf '#!/bin/sh\nexit 1\n' >"$MACLIFT_STUB_DIR/gpgconf-fail"
  chmod +x "$MACLIFT_STUB_DIR/gpgconf-fail"
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  local rc=0 out
  out="$(MACLIFT_GPGCONF="$MACLIFT_STUB_DIR/gpgconf-fail" bash "$GPG_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "exits 0"
  assert_equals "FAKEFPR0000000000000000000000000000NEW" "$(conf_get "$UCONF" MACLIFT_SIGNING_KEY)" "key saved"
  assert_contains "$out" "Could not restart gpg-agent" "note printed"
}

test_gpg_generate() {
  test_suite "gpg-signing.sh generates a key when none exists"
  fresh_env
  bash "$GPG_SH" >/dev/null 2>&1
  assert_contains "$(cat "$MACLIFT_STUB_DIR/gpg.calls")" "--quick-generate-key Test User <test@example.com> ed25519 sign 2y" "key generated for the identity"
  assert_equals "FAKEFPR0000000000000000000000000000NEW" "$(conf_get "$UCONF" MACLIFT_SIGNING_KEY)" "new fingerprint saved"
  assert_command_succeeds "bash '$GPG_SH' --check" "check passes"
}

test_gpg_missing_identity() {
  test_suite "gpg-signing.sh without name or email"
  fresh_env
  conf_set "$UCONF" MACLIFT_NAME ""
  local rc=0 out
  out="$(bash "$GPG_SH" 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exits 1"
  assert_contains "$out" "name or email missing" "explains"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/gpg.calls' ]" "gpg not called"
}

test_gpg_missing_binary() {
  test_suite "gpg-signing.sh without gpg"
  fresh_env
  local rc=0 out
  out="$(MACLIFT_GPG="$TMP_DIR/no-such-gpg" bash "$GPG_SH" 2>&1)" || rc=$?
  assert_equals "1" "$rc" "exits 1"
  assert_contains "$out" "needs gnupg" "explains"
}

test_gpg_pinentry() {
  test_suite "gpg-signing.sh pinentry-program"
  fresh_env
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  bash "$GPG_SH" >/dev/null 2>&1
  local ac="$MACLIFT_HOME/.gnupg/gpg-agent.conf"
  assert_equals "pinentry-program $MACLIFT_STUB_DIR/prefix/bin/pinentry-mac" "$(cat "$ac")" "line added"
  assert_equals "--kill gpg-agent" "$(cat "$MACLIFT_STUB_DIR/gpgconf.calls")" "agent restarted via the stub"

  fresh_env
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  mkdir -p "$MACLIFT_HOME/.gnupg"
  ac="$MACLIFT_HOME/.gnupg/gpg-agent.conf"
  printf 'default-cache-ttl 600\npinentry-program /opt/mine/pinentry\n' >"$ac"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_equals "default-cache-ttl 600
pinentry-program /opt/mine/pinentry" "$(cat "$ac")" "existing pinentry-program kept, file untouched"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/gpgconf.calls' ]" "agent not restarted"

  fresh_env
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  mkdir -p "$MACLIFT_HOME/.gnupg"
  ac="$MACLIFT_HOME/.gnupg/gpg-agent.conf"
  printf '# pinentry-program /old\nmax-cache-ttl 5\n' >"$ac"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_equals "# pinentry-program /old
max-cache-ttl 5

pinentry-program $MACLIFT_STUB_DIR/prefix/bin/pinentry-mac" "$(cat "$ac")" "commented line ignored, appended"
}

test_gpg_pinentry_first() {
  test_suite "gpg-signing.sh sets pinentry-mac before making a key"
  fresh_env
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  # A gpg that notes whether gpg-agent.conf names pinentry-mac when a key is made.
  cat >"$MACLIFT_STUB_DIR/gpg-order" <<EOF_GPG
#!/usr/bin/env bash
case "\$*" in *--quick-generate-key*)
  grep -q pinentry-mac "\$GNUPGHOME/gpg-agent.conf" 2>/dev/null && echo yes >"$MACLIFT_STUB_DIR/pinentry-first" ;;
esac
exec "$PROJECT_ROOT/tests/stubs/gpg" "\$@"
EOF_GPG
  chmod +x "$MACLIFT_STUB_DIR/gpg-order"
  MACLIFT_GPG="$MACLIFT_STUB_DIR/gpg-order" bash "$GPG_SH" >/dev/null 2>&1
  assert_command_succeeds "grep -q quick-generate-key '$MACLIFT_STUB_DIR/gpg.calls'" "a key was made"
  assert_file_exists "$MACLIFT_STUB_DIR/pinentry-first" "pinentry-mac was set up before key generation"
}

test_gpg_no_pinentry_binary() {
  test_suite "gpg-signing.sh without pinentry-mac"
  fresh_env
  bash "$GPG_SH" >/dev/null 2>&1
  assert_command_fails "[ -e '$MACLIFT_HOME/.gnupg/gpg-agent.conf' ]" "no agent conf written"
  assert_command_fails "[ -e '$MACLIFT_STUB_DIR/gpgconf.calls' ]" "agent not restarted"
}

test_gpg_upload() {
  test_suite "gpg-signing.sh uploads to GitHub"
  fresh_env
  : >"$MACLIFT_STUB_DIR/gh.loggedin"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_contains "$(cat "$MACLIFT_STUB_DIR/gh.calls")" "gpg-key add -" "gpg-key added"
  assert_contains "$(cat "$MACLIFT_STUB_DIR/gh.gpgkey")" "BEGIN PGP PUBLIC KEY BLOCK" "armored key piped in"

  fresh_env
  : >"$MACLIFT_STUB_DIR/gh.loggedin"
  : >"$MACLIFT_STUB_DIR/gh.addfail"
  local rc=0 out
  out="$(bash "$GPG_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "a failed upload is a note, not a failure"
  assert_contains "$out" "gh auth refresh -s write:gpg_key" "note printed"
  assert_contains "$out" "gh gpg-key add -" "runnable command in note"

  fresh_env
  rc=0
  out="$(bash "$GPG_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "logged out exits 0"
  assert_command_fails "grep -q 'gpg-key add' '$MACLIFT_STUB_DIR/gh.calls'" "no upload when logged out"
}

# sandbox_env: like fresh_env, but HOME is a different temp folder, so
# MACLIFT_HOME is a sandbox. gh is logged in, so only the sandbox rule can
# stop an upload.
sandbox_env() {
  fresh_env
  HOME="$(mktemp -d "$TMP_DIR/realhome.XXXXXX")"
  export HOME GNUPGHOME="$HOME/.gnupg"
  : >"$MACLIFT_STUB_DIR/gh.loggedin"
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
}

test_sandbox() {
  test_suite "sandbox runs leave the keyring, keychain and GitHub alone"
  sandbox_env
  local out rc=0
  out="$(bash "$SSH_KEY_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "ssh-key exits 0"
  assert_file_exists "$MACLIFT_HOME/.ssh/id_ed25519" "key made in the sandbox"
  assert_command_fails "[ -s '$MACLIFT_STUB_DIR/ssh-add.calls' ]" "no ssh-add"
  assert_command_fails "[ -s '$MACLIFT_STUB_DIR/gh.calls' ]" "ssh-key: no gh"
  assert_contains "$out" "sandbox run: skipped" "ssh-key says it skipped"
  rc=0
  out="$(bash "$GPG_SH" 2>&1)" || rc=$?
  assert_equals "0" "$rc" "gpg-signing exits 0"
  assert_command_fails "[ -s '$MACLIFT_STUB_DIR/gh.calls' ]" "gpg-signing: no gh"
  assert_command_fails "[ -s '$MACLIFT_STUB_DIR/gpgconf.calls' ]" "no gpgconf"
  assert_equals "$MACLIFT_HOME/.gnupg" "$(sort -u "$MACLIFT_STUB_DIR/gpg.gnupghome")" "every gpg call saw the sandbox GNUPGHOME"
  assert_file_exists "$MACLIFT_HOME/.gnupg/gpg-agent.conf" "agent conf in the sandbox"
  assert_command_fails "[ -e '$HOME/.gnupg' ]" "the other HOME's .gnupg untouched"
  assert_contains "$out" "sandbox run: skipped GitHub upload" "gpg says it skipped the upload"
  assert_contains "$out" "sandbox run: skipped restarting gpg-agent" "gpg says it skipped the agent restart"
  : >"$MACLIFT_STUB_DIR/gpg.gnupghome"
  bash "$GPG_SH" --check >/dev/null 2>&1 || true
  assert_equals "$MACLIFT_HOME/.gnupg" "$(sort -u "$MACLIFT_STUB_DIR/gpg.gnupghome")" "--check uses the sandbox GNUPGHOME"
}

test_gpg_gnupghome() {
  test_suite "gpg-signing.sh outside a sandbox keeps GNUPGHOME"
  fresh_env
  export GNUPGHOME="$MACLIFT_HOME/custom-gnupg"
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  bash "$GPG_SH" >/dev/null 2>&1
  assert_equals "$MACLIFT_HOME/custom-gnupg" "$(sort -u "$MACLIFT_STUB_DIR/gpg.gnupghome")" "gpg saw the given GNUPGHOME"
  assert_file_exists "$MACLIFT_HOME/custom-gnupg/gpg-agent.conf" "agent conf lives there"
  fresh_env
  unset GNUPGHOME
  bash "$GPG_SH" >/dev/null 2>&1
  assert_equals "$HOME/.gnupg" "$(sort -u "$MACLIFT_STUB_DIR/gpg.gnupghome")" "default is HOME/.gnupg"
}

test_notes_file() {
  test_suite "notes go to MACLIFT_NOTES when it is set"
  fresh_env
  local out notes="$TMP_DIR/run.notes"
  rm -f "$notes"
  out="$(MACLIFT_NOTES="$notes" bash "$SSH_KEY_SH" 2>&1)"
  assert_contains "$(cat "$notes" 2>/dev/null)" "Add the SSH key to GitHub later: gh auth login && gh ssh-key add" "ssh note in the notes file"
  assert_command_fails "grep -q 'Add the SSH key to GitHub later' <<<'$out'" "ssh note not on stdout"
  out="$(MACLIFT_NOTES="$notes" bash "$GPG_SH" 2>&1)"
  assert_contains "$(cat "$notes")" "gh auth refresh -s write:gpg_key" "gpg note in the notes file"
  assert_command_fails "grep -q 'Add the GPG key to GitHub later' <<<'$out'" "gpg note not on stdout"

  fresh_env
  rm -f "$notes"
  : >"$MACLIFT_STUB_DIR/gh.loggedin"
  : >"$MACLIFT_STUB_DIR/gh.addfail"
  MACLIFT_NOTES="$notes" bash "$SSH_KEY_SH" >/dev/null 2>&1
  assert_contains "$(cat "$notes" 2>/dev/null)" "Could not upload the SSH key" "ssh upload failure is a note"
  rm -f "$notes"
  MACLIFT_NOTES="$notes" bash "$GPG_SH" >/dev/null 2>&1
  assert_contains "$(cat "$notes" 2>/dev/null)" "Could not upload the GPG key" "gpg upload failure is a note"
  rm -f "$notes"
  echo "test@example.com  0000000000000NEW  xsBNBGF...  2026-01-01  2028-01-01" >"$MACLIFT_STUB_DIR/gh.gpgkeys"
  MACLIFT_NOTES="$notes" bash "$GPG_SH" >/dev/null 2>&1
  assert_command_fails "[ -s '$notes' ]" "upload fails but GitHub already has the key: no note"

  fresh_env
  rm -f "$notes"
  : >"$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  chmod +x "$MACLIFT_STUB_DIR/prefix/bin/pinentry-mac"
  printf '#!/bin/sh\nexit 1\n' >"$MACLIFT_STUB_DIR/gpgconf-fail"
  chmod +x "$MACLIFT_STUB_DIR/gpgconf-fail"
  MACLIFT_NOTES="$notes" MACLIFT_GPGCONF="$MACLIFT_STUB_DIR/gpgconf-fail" bash "$GPG_SH" >/dev/null 2>&1
  assert_contains "$(cat "$notes" 2>/dev/null)" "Could not restart gpg-agent" "agent restart note"
  rm -f "$notes"
}

test_second_identity() {
  test_suite "second identity script"
  fresh_env
  # shellcheck source=lib/ui.sh
  source "$PROJECT_ROOT/lib/ui.sh"
  # shellcheck source=lib/dotfiles.sh
  source "$PROJECT_ROOT/lib/dotfiles.sh"
  # shellcheck source=lib/identity.sh
  source "$PROJECT_ROOT/lib/identity.sh"
  local sh="$PROJECT_ROOT/scripts/items/keys/second-identity.sh" rc=0
  assert_equals "script:second-identity" "$(catalog_items keys | grep -x 'script:second-identity')" "listed in keys"
  MACLIFT_ASSUME_YES=1 identity_ask_alt >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "-y with missing values returns 1"
  rc=0
  bash "$sh" --check </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "check fails with nothing configured"
  conf_set "$UCONF" MACLIFT_ALT_NAME "Work User"
  conf_set "$UCONF" MACLIFT_ALT_EMAIL "work@example.com"
  conf_set "$UCONF" MACLIFT_ALT_DIR "~/Work"
  rc=0
  bash "$sh" --check </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "check fails before the run"
  rc=0
  bash "$sh" </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "run succeeds"
  rc=0
  bash "$sh" --check </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "check passes after the run"
  assert_command_succeeds "install_is_present script:second-identity" "install_is_present agrees"
  local g="$MACLIFT_HOME/.gitconfig.alt" before
  conf_set "$UCONF" MACLIFT_ALT_SIGNING_KEY "ABCDEF0123456789"
  before="$(cat "$g")"
  rc=0
  bash "$sh" --check </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "check fails once MACLIFT_ALT_SIGNING_KEY is added"
  assert_equals "$before" "$(cat "$g")" "check does not write the file"
  assert_equals "" "$(find "$MACLIFT_HOME" -maxdepth 1 -name '.gitconfig.alt.*')" "check leaves no temp file"
  rc=0
  bash "$sh" </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "second run succeeds"
  assert_equals "ABCDEF0123456789" "$(git config -f "$g" user.signingkey)" "signing key written"
  assert_equals "true" "$(git config -f "$g" commit.gpgsign)" "commit signing on"
  rc=0
  bash "$sh" --check </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "0" "$rc" "check passes again"
  conf_set "$UCONF" MACLIFT_ALT_NAME "Other Name"
  rc=0
  bash "$sh" --check </dev/null >/dev/null 2>&1 || rc=$?
  assert_equals "1" "$rc" "check fails after a name change"
}

test_catalog
test_sandbox
test_notes_file
test_gpg_gnupghome
test_second_identity
test_gpg_catalog
test_gpg_reuse
test_gpg_dead_keys
test_gpg_agent_kill_fails
test_gpg_generate
test_gpg_missing_identity
test_gpg_missing_binary
test_gpg_pinentry
test_gpg_pinentry_first
test_gpg_no_pinentry_binary
test_gpg_upload
test_check
test_orphan_pub
test_existing_key
test_commented_config
test_no_tty
test_ssh_no_email
test_logged_in
test_logged_out
test_upload_fails
test_existing_config
test_summary
