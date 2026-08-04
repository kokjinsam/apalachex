# Apalachex

Safe, deterministic Apalache execution and artifact management for Elixir.

Apalachex validates TLA+ inputs, constructs shell-free Apalache plans, runs
exactly Apalache 0.58.3, and returns ordered paths to retained ITF files. It
does not open, decode, or interpret ITF contents. Version 0.1.0 supports
execution on POSIX systems only.

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

{:ok, result} = Apalachex.run(plan)
result.itf_paths
```

Every reserved run directory is retained. Its `apalachex-run.json` manifest
records the running and completed lifecycle. A successful result always has at
least one absolute top-level regular `.itf.json` path, sorted lexically.

## Supported boundary

- Elixir `~> 1.18`
- Apalache exactly `0.58.3` or `v0.58.3`
- POSIX execution only; Windows is rejected after strict option validation and
  before executable discovery, version probing, run-directory allocation,
  manifest creation, or process execution
- synchronous execution without a shell
- no timeout, cancellation, supervision, cleanup, or ITF interpretation

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

`just setup` requires asdf 0.16.5 and installs the pinned tools from
`.tool-versions`. The consumer and real-Apalache checks require Apalache 0.58.3;
the latter is installed by the owned asdf plugin and selected by the repository
toolchain.

## License

MIT. See [LICENSE](LICENSE).
