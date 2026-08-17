# Apalachex

Safe, deterministic Apalache execution and artifact management for Elixir.

Apalachex validates TLA+ inputs, constructs shell-free Apalache plans, runs
exactly Apalache 0.58.3, and returns ordered paths to retained ITF files. It
does not open, decode, or interpret ITF contents. Version 0.1.0 supports
building and execution on POSIX systems only.

## Installation

Add `apalachex` to the dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:apalachex, "~> 0.1.0"}
  ]
end
```

Apalache 0.58.3 must be available as `apalache-mc` on `PATH`, or supplied with
the `:executable` option.

## Usage

```elixir
{:ok, spec} =
  Apalachex.Spec.new(
    source: "Counter.tla",
    config: "Counter.cfg"
  )

run_directory =
  Apalachex.RunDirectory.build(
    spec,
    generated_at: DateTime.utc_now(),
    suffix: "a1b2c3"
  )

plan =
  Apalachex.Plan.new(
    spec,
    mode: :simulate,
    length: 10,
    max_run: 5,
    run_directory: run_directory
  )

{:ok, result} = Apalachex.run(plan, timeout: 30_000)
result.itf_paths
```

Every reserved run directory is retained. Its `apalachex-run.json` manifest
records the running and completed lifecycle. A successful result always has at
least one absolute top-level regular `.itf.json` path, sorted lexically.

Timeout values are milliseconds. The default is `:infinity`. A finite timeout
bounds only the wait for the main Apalache command, not the total duration of
`run/2`. Execution remains synchronous. The version probe has a fixed 5,000 ms
timeout and creates no run directory or manifest if it times out.

A timed-out run retains its run directory and partial files, does not classify
partial ITFs, and records the existing completed/failed manifest outcome.
Caller-death cleanup belongs to the internal process manager. A retained
`running` manifest means that no terminal Apalachex outcome was committed.

## Supported boundary

- Elixir `~> 1.18`
- Apalache exactly `0.58.3` or `v0.58.3`
- POSIX build and execution only
- synchronous execution without a shell
- no cancellation API, asynchronous API, recovery, or ITF interpretation

## Development

```sh
asdf plugin add just https://github.com/olofvndrhr/asdf-just.git
asdf install just 1.54.0
just setup
just test
just check
just docs
just package-audit
just consumer-smoke
just test-apalache
```

`just setup` requires asdf 0.16.5, system `make`, and a POSIX C compiler. Set
`CC` to select the compiler; when `CC` is unset, `cc` is used. These native host
prerequisites are not managed by `.tool-versions`. After it checks them,
`just setup` installs the pinned tools from `.tool-versions`. The consumer and
real-Apalache checks require Apalache 0.58.3; the latter is installed by the
owned asdf plugin and selected by the repository toolchain.

### Maintainer release

Update the version in `mix.exs` and add its dated changelog section. Commit and
push the prepared `main`, ensure CI is green, then run `just release`.

The command publishes the prepared version to Hex and creates its GitHub tag
and release. It does not prepare, edit, commit, or push `main`.

## License

MIT. See [LICENSE](LICENSE).
