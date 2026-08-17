#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
audit_root=$(mktemp -d "${TMPDIR:-/tmp}/apalachex-package-audit.XXXXXX")
package="$audit_root/package"

cd "$repository"
mix hex.build --unpack --output "$package"

actual=$(cd "$package" && find . -mindepth 1 -maxdepth 1 -print | sed 's|^./||' | LC_ALL=C sort)
expected=$(printf '%s\n' .formatter.exs CHANGELOG.md LICENSE README.md hex_metadata.config lib mix.exs | LC_ALL=C sort)

if [ "$actual" != "$expected" ]; then
  printf '%s\n' "package top-level allowlist mismatch" >&2
  printf '%s\n' "$actual" >&2
  exit 1
fi

if find "$package" -type l -print | grep -q .; then
  printf '%s\n' "package contains a symbolic link" >&2
  exit 1
fi

if find "$package" \( -name test -o -name tmp -o -name _build -o -name deps -o -name doc \
  -o -name .github -o -name .git -o -name '*.beam' -o -name '*.itf.json' \
  -o -name apalachex-run.json -o -name apalache-mc \) -print | grep -q .; then
  printf '%s\n' "package contains a forbidden or generated path" >&2
  exit 1
fi

if LC_ALL=C grep -R -I -n -E '(/Users/|/home/|[A-Za-z]:\\\\Users\\\\)' "$package"; then
  printf '%s\n' "package contains a local absolute path" >&2
  exit 1
fi

(
  cd "$package"
  MIX_ENV=prod mix deps.get --only prod
  MIX_ENV=prod mix compile --warnings-as-errors
)

printf 'package audit and unpacked production build passed: %s\n' "$package"
