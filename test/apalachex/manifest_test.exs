defmodule Apalachex.ManifestTest do
  use ExUnit.Case, async: false

  alias Apalachex.Error
  alias Apalachex.Manifest
  alias Apalachex.Plan
  alias Apalachex.Result
  alias Apalachex.Spec

  @fake Path.expand("../fixtures/apalache/fake-apalache", __DIR__)
  @source Path.expand("../fixtures/specs/Counter.tla", __DIR__)

  setup do
    root =
      "tmp/tests"
      |> Path.join("manifest-#{System.unique_integer([:positive])}")
      |> Path.expand()

    File.mkdir_p!(root)
    %{root: root}
  end

  test "retains exact running then completed materialized manifests", %{root: root} do
    executable = install_fake(root, "supported")
    plan = plan(Path.join(root, "run"))

    assert {:ok, %Result{itf_paths: paths}} = Apalachex.run(plan, executable: executable)

    running = plan.run_directory |> Path.join("running-manifest-snapshot.json") |> decode()
    completed_path = Path.join(plan.run_directory, "apalachex-run.json")
    completed = decode(completed_path)

    assert running["schema"] == "apalachex.run"
    assert running["schema_version"] == 1
    assert running["status"] == "running"
    assert running["outcome"] == nil
    assert running["producer"] == %{"name" => "apalachex", "version" => "0.1.0"}
    assert running["spec"] == %{"source" => @source, "config" => nil}
    assert running["plan"]["argv"] == plan.argv
    assert running["execution"]["apalache_version"] == "0.58.3"

    assert completed["status"] == "completed"
    assert completed["outcome"] == "materialized"
    assert completed["execution"]["exit_status"] == 0
    assert completed["artifacts"]["itf_paths"] == Enum.map(paths, &Path.basename/1)
    assert completed["failure"] == nil
    assert completed_path |> File.read!() |> String.ends_with?("\n")
    assert {:ok, _started, 0} = DateTime.from_iso8601(completed["started_at"])
    assert {:ok, _finished, 0} = DateTime.from_iso8601(completed["completed_at"])
  end

  test "renders bounded valid UTF-8 while preserving raw long binary output", %{root: root} do
    executable = install_fake(root, "long-output")
    plan = plan(Path.join(root, "run"))

    assert {:error, %Error{output: output} = error} =
             Apalachex.run(plan, executable: executable)

    assert byte_size(output) > 6000
    assert error |> Exception.message() |> String.valid?()
    assert error |> Exception.message() |> byte_size() <= 4096

    summary = decode(Path.join(plan.run_directory, "apalachex-run.json"))["execution"]["output"]
    assert summary["byte_size"] == byte_size(output)
    assert summary["tail_truncated"]
    assert String.valid?(summary["tail"])
    assert byte_size(summary["tail"]) <= 4096
  end

  test "an initial manifest failure prevents execution but retains the reservation", %{root: root} do
    executable = install_fake(root, "supported")
    plan = plan(Path.join(root, "run"))

    result =
      Manifest.with_writer(
        fn _path, _document -> {:error, {:write, :forced_initial_failure}} end,
        fn -> Apalachex.run(plan, executable: executable) end
      )

    assert {:error,
            %Error{
              phase: :manifest,
              reason: {:manifest_write_failed, :initial, manifest_path, :forced_initial_failure}
            }} = result

    assert manifest_path == Path.join(plan.run_directory, "apalachex-run.json")
    assert File.dir?(plan.run_directory)
    refute plan.run_directory |> Path.join("argv.txt") |> File.exists?()
  end

  test "a final manifest failure after success becomes the primary contextual error", %{
    root: root
  } do
    executable = install_fake(root, "status12")
    plan = plan(Path.join(root, "run"))

    assert {:error,
            %Error{
              phase: :manifest,
              reason: {:manifest_write_failed, :final, manifest_path, :forced_final_failure},
              exit_status: 12,
              output: "counterexample\n",
              itf_paths: [itf_path]
            }} =
             with_final_failure(fn -> Apalachex.run(plan, executable: executable) end)

    assert manifest_path == Path.join(plan.run_directory, "apalachex-run.json")
    assert File.regular?(itf_path)
    assert decode(manifest_path)["status"] == "running"
  end

  test "a final manifest failure after an operational error remains secondary", %{root: root} do
    executable = install_fake(root, "no-itf")
    plan = plan(Path.join(root, "run"))

    assert {:error,
            %Error{
              phase: :itf_discovery,
              reason: :no_itf_artifacts,
              manifest_failure: {:manifest_write_failed, :final, manifest_path, :forced_final_failure}
            }} = with_final_failure(fn -> Apalachex.run(plan, executable: executable) end)

    assert manifest_path == Path.join(plan.run_directory, "apalachex-run.json")
    assert decode(manifest_path)["status"] == "running"
  end

  defp with_final_failure(function) do
    writer = fn path, document ->
      if document["status"] == "running" do
        Manifest.write_atomic(path, document)
      else
        {:error, {:write, :forced_final_failure}}
      end
    end

    Manifest.with_writer(writer, function)
  end

  defp install_fake(directory, name) do
    File.mkdir_p!(directory)
    executable = Path.join(directory, name)
    File.cp!(@fake, executable)
    File.chmod!(executable, 0o755)
    executable
  end

  defp plan(run_directory) do
    Plan.new(%Spec{source: @source, config: nil},
      mode: :check,
      length: 2,
      run_directory: run_directory
    )
  end

  defp decode(path), do: path |> File.read!() |> JSON.decode!()
end
