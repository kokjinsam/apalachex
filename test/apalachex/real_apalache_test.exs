defmodule Apalachex.RealApalacheTest do
  use ExUnit.Case, async: false

  alias Apalachex.Error
  alias Apalachex.Plan
  alias Apalachex.Result
  alias Apalachex.Spec

  @moduletag :apalache

  @fixtures Path.expand("../fixtures/specs", __DIR__)

  setup do
    executable =
      System.find_executable("apalache-mc") ||
        flunk("Apalache 0.58.3 must be installed on PATH")

    root =
      "tmp/tests"
      |> Path.join("real-apalache-#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.mkdir_p!(root)
    %{executable: Path.expand(executable), root: root}
  end

  test "simulate returns ordered status-0 artifacts and a retained manifest", context do
    spec = spec!(context.root, "Counter")
    run_directory = Path.join(context.root, "simulate")

    plan =
      Plan.new(spec,
        mode: :simulate,
        length: 3,
        max_run: 2,
        run_directory: run_directory
      )

    assert {:ok,
            %Result{
              executable: executable,
              version: %Version{major: 0, minor: 58, patch: 3},
              exit_status: 0,
              itf_paths: [_first | _rest] = paths
            }} = Apalachex.run(plan)

    assert executable == context.executable
    assert paths == Enum.sort(paths)
    assert Enum.all?(paths, &File.regular?/1)

    manifest = manifest(run_directory)
    assert manifest["status"] == "completed"
    assert manifest["outcome"] == "materialized"
    assert manifest["execution"]["exit_status"] == 0
    assert manifest["artifacts"]["itf_paths"] == Enum.map(paths, &Path.basename/1)
  end

  test "check returns status 12 as success when the counterexample is materialized", context do
    spec = spec!(context.root, "Violation")
    run_directory = Path.join(context.root, "check")
    plan = Plan.new(spec, mode: :check, length: 3, run_directory: run_directory)

    assert {:ok, %Result{exit_status: 12, itf_paths: [_first | _rest]}} =
             Apalachex.run(plan)

    assert File.dir?(run_directory)
    assert manifest(run_directory)["outcome"] == "materialized"
  end

  test "malformed input without artifacts is an execution failure with retained evidence",
       context do
    spec = spec!(context.root, "Malformed")
    run_directory = Path.join(context.root, "malformed-run")
    plan = Plan.new(spec, mode: :check, length: 3, run_directory: run_directory)

    assert {:error,
            %Error{
              phase: :execution,
              reason: {:process_failed_without_itf, status},
              exit_status: status,
              itf_paths: []
            }} = Apalachex.run(plan)

    assert status != 0
    assert File.dir?(run_directory)
    assert run_directory |> Path.join("apalachex-run.json") |> File.regular?()
    assert manifest(run_directory)["outcome"] == "failed"
  end

  defp spec!(root, name) do
    directory = Path.join(root, String.downcase(name))
    File.mkdir!(directory)
    source = Path.join(directory, "#{name}.tla")
    config = Path.join(directory, "#{name}.cfg")
    @fixtures |> Path.join("#{name}.tla") |> File.cp!(source)
    @fixtures |> Path.join("#{name}.cfg") |> File.cp!(config)

    assert {:ok, spec} =
             Spec.new(
               source: source,
               config: config
             )

    spec
  end

  defp manifest(run_directory) do
    run_directory
    |> Path.join("apalachex-run.json")
    |> File.read!()
    |> JSON.decode!()
  end
end
