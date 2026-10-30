# Contributing

Thanks for helping. Small changes are welcome.

## Add a package: one line

The catalog is in `catalog/`. One file per group, named like
`20-cli.tsv`. The number sets the display order. A file starts with a few
`@key value` header lines (`@id`, `@title`, `@description`, `@default`,
`@required`), then one item per line, separated by tabs:

```
type	id	default	description	extra
```

- `type`: `brew`, `cask`, `asdf`, `dotfiles` or `script`.
- `id`: the package name (or the item name for `dotfiles` and `script`).
- `default`: `on` or `off`. Whether it is ticked at first.
- `description`: one short line shown in the picker.
- `extra`: only for some types. For `asdf` it is the plugin URL, for
  `dotfiles` the files to link, for `script` the script path under `scripts/items/`.

Example. To add ripgrep to the command-line tools, put this line in
`catalog/20-cli.tsv`, with real tabs between the columns:

```
brew	ripgrep	on	Better grep
```

That is all. The picker, `maclift add` and `maclift snapshot` read the catalog,
so there is no other place to edit.

## Run the tests

Run the unit files one at a time, under both shells:

```sh
bash tests/unit/test_catalog.sh
/bin/bash tests/unit/test_catalog.sh
```

Do this for every `tests/unit/test_*.sh` that your change touches. Then the
integration tests (about a minute or two):

```sh
bash tests/run_integration_tests.sh
```

Lint with shellcheck:

```sh
find maclift lib tests scripts -type f \( -name maclift -o -name '*.sh' \) -print0 \
  | xargs -0 shellcheck -x --severity=warning
shellcheck -x --severity=warning install
```

Tests never touch your real home or the network. They use a temporary
`MACLIFT_HOME` and the stubs in `tests/stubs`.

## The bash 3.2 rule

macOS ships bash 3.2, and maclift must run on it before anything else is
installed. So no associative arrays, no `mapfile`, no `sort -V`, no
`${var,,}`. Read config files with `conf_get`/`conf_set`; never `source` them.

## Personal data

Do not commit real names, emails or home paths. Use `Ada Lovelace` and
`ada@example.com` in examples. `tests/unit/test_no_personal_data.sh` checks
this. It rejects other email addresses, private key headers and
`/Users/<name>` paths.

Maintainers can also keep a private deny-list of words that must never appear.
Put one pattern per line in the `MACLIFT_PRIVATE_PATTERNS` environment variable
(CI keeps it as a secret) or in `~/.config/maclift/private-patterns`. The same
test checks every tracked file against it. Without a list, only the generic
checks run.

## Releases

`maclift update` pulls `main` with a fast-forward, not a tag. So `main` must
always be releasable, and it only ever moves by normal commits: never rebuild
it and never force-push it, or every install stops updating.

A new release is a tagged commit on `main`. Bump `VERSION` and the
`MACLIFT_TAG` default in `install` together, in the same commit, then tag it
(`v1.2.3`).

Publishing the GitHub release runs the `one-liner` CI job: the README
one-liner, from that tag, on a fresh macOS runner with an empty home, as a
dry run. You can also start it by hand (Actions → CI → Run workflow); it then
tests `v$(cat VERSION)`.

`scripts/release/build-public-tree.sh` was for the first public release
(v1.0.0) only. Don't use it again.

## Commits

Use conventional commits, for example `feat: add bat to cli tools` or
`fix(doctor): clearer fix text`.
