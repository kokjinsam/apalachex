default: help

help:
    @just --list

setup:
    #!/usr/bin/env bash
    set -euo pipefail
    fail() { printf 'setup: %s\n' "$*" >&2; exit 1; }
    command -v make >/dev/null || fail 'make is required to build native dependencies'
    if [[ "${CC+x}" == x ]]; then
      [[ -n "$CC" ]] || fail 'CC must not be empty'
      compiler="$CC"
    else
      compiler=cc
    fi
    command -v "$compiler" >/dev/null || fail "POSIX C compiler $compiler is required to build native dependencies"
    command -v asdf >/dev/null || fail 'asdf 0.16.5 is required'
    [[ "$(asdf --version)" == 'asdf version 0.16.5' ]] || fail "asdf 0.16.5 is required; found $(asdf --version)"

    plugins=(
      'erlang|https://github.com/asdf-vm/asdf-erlang.git'
      'elixir|https://github.com/asdf-vm/asdf-elixir.git'
      'java|https://github.com/halcyon/asdf-java.git'
      'just|https://github.com/olofvndrhr/asdf-just.git'
      'apalache|https://github.com/kokjinsam/asdf-apalache.git'
      'github-cli|https://github.com/bartlomiejdanek/asdf-github-cli.git'
    )

    for entry in "${plugins[@]}"; do
      name="${entry%%|*}"
      expected_url="${entry#*|}"
      actual_url="$(asdf plugin list --urls | awk -v name="$name" '$1 == name { print $2 }')"
      if [[ -n "$actual_url" ]]; then
        [[ "$actual_url" == "$expected_url" ]] || fail "$name plugin URL mismatch: expected $expected_url, found $actual_url"
      else
        asdf plugin add "$name" "$expected_url"
      fi
    done

    while IFS=' ' read -r name version; do
      [[ -n "$name" && -n "$version" ]] || continue
      asdf install "$name" "$version"
    done < .tool-versions
    asdf exec mix local.hex 2.4.2 --force
    asdf exec mix deps.get

deps:
    mix local.hex 2.4.2 --force
    mix deps.get

test:
    mix test

check:
    mix check

docs:
    mix docs --warnings-as-errors

package-audit:
    scripts/audit_package.sh

consumer-smoke:
    scripts/consumer_smoke.sh

test-apalache:
    mix test --include apalache test/apalachex/real_apalache_test.exs

# Locally publish the prepared version to Hex and create its GitHub tag/release.
release:
    scripts/release.sh
