#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
smoke_root=$(mktemp -d "${TMPDIR:-/tmp}/apalachex-consumer.XXXXXX")
package="$smoke_root/package"
consumer="$smoke_root/consumer"

cd "$repository"
mix hex.build --unpack --output "$package"
mkdir "$consumer"
cp test/support/consumer/mix.exs "$consumer/mix.exs"
cp -R test/support/consumer/test "$consumer/test"

cd "$consumer"
APALACHEX_PACKAGE_PATH="$package" mix deps.get
APALACHEX_PACKAGE_PATH="$package" mix compile --warnings-as-errors
APALACHEX_PACKAGE_PATH="$package" mix test

printf 'clean consumer smoke passed: %s\n' "$consumer"
