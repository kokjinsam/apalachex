defmodule Apalachex.RunTest do
  use ExUnit.Case, async: false

  alias Apalachex.Error
  alias Apalachex.Plan
  alias Apalachex.Result
  alias Apalachex.Spec

  @fake Path.expand("../fixtures/apalache/fake-apalache", __DIR__)
  @source Path.expand("../fixtures/specs/Counter.tla", __DIR__)
  @config Path.expand("../fixtures/specs/Counter.cfg", __DIR__)

  setup do
    root = "tmp/tests" |> Path.join("run-#{System.unique_integer([:positive])}") |> Path.expand()
    File.mkdir_p!(root)
    %{root: root}
  end

  test "raises for strict public API misuse", %{root: root} do
    plan = plan(Path.join(root, "run"))
    module = Module.safe_concat(["Apalachex"])

    invalid = [
      fn -> module.run(%{}) end,
      fn -> module.run(plan, %{executable: "tool"}) end,
      fn -> Apalachex.run(plan, executable: "a", executable: "b") end,
      fn -> Apalachex.run(plan, executable: "") end,
      fn -> Apalachex.run(plan, executable: 1) end,
      fn -> Apalachex.run(plan, unknown: true) end
    ]

    for call <- invalid, do: assert_raise(ArgumentError, call)
  end

  test "rejects Windows before executable discovery or run allocation", %{root: root} do
    Process.put({Apalachex, :os_type}, {:win32, :nt})
    run_directory = Path.join(root, "windows-run")
    plan = plan(run_directory)

    assert_raise ArgumentError, fn -> Apalachex.run(plan, unknown: true) end

    assert {:error,
            %Error{
              phase: :execution,
              reason: {:unsupported_platform, :win32},
              plan: ^plan,
              executable: nil,
              version: nil,
              exit_status: nil,
              output: nil,
              itf_paths: [],
              manifest_failure: nil
            }} = Apalachex.run(plan, executable: "nonexistent-apalachex-candidate")

    refute File.exists?(run_directory)
    refute run_directory |> Path.join("apalachex-run.json") |> File.exists?()
  end

  test "resolves the default and bare executable through PATH", %{root: root} do
    executable = install_fake(root, "apalache-mc")
    previous_path = System.get_env("PATH")

    try do
      System.put_env("PATH", root <> ":" <> (previous_path || ""))

      assert {:ok, %Result{executable: ^executable}} =
               root |> Path.join("default") |> plan() |> Apalachex.run()

      assert {:ok, %Result{executable: ^executable}} =
               root |> Path.join("bare") |> plan() |> Apalachex.run(executable: "apalache-mc")
    after
      restore_path(previous_path)
    end
  end

  test "expands and validates path-like executables directly", %{root: root} do
    executable = install_fake(Path.join(root, "tools with spaces"), "fake apalache")

    assert {:ok, %Result{executable: ^executable}} =
             root |> Path.join("run") |> plan() |> Apalachex.run(executable: executable)

    missing = Path.join(root, "missing/tool")

    assert {:error, %Error{phase: :executable_discovery, reason: {:not_found, ^missing}}} =
             root |> Path.join("missing-run") |> plan() |> Apalachex.run(executable: missing)

    assert {:error, %Error{phase: :executable_discovery, reason: {:not_a_regular_file, ^root}}} =
             root |> Path.join("directory-run") |> plan() |> Apalachex.run(executable: root)
  end

  test "classifies effective execute denial as executable discovery", %{root: root} do
    executable = install_fake(root, "permission-denied-#{System.os_time(:nanosecond)}")
    File.chmod!(executable, 0o001)
    run_directory = Path.join(root, "permission-denied-run")

    assert {:error,
            %Error{
              phase: :executable_discovery,
              reason: {:not_executable, ^executable},
              executable: nil
            }} = run_directory |> plan() |> Apalachex.run(executable: executable)

    refute File.exists?(run_directory)
  end

  test "rejects more than one leading version prefix as unparseable", %{root: root} do
    executable = install_fake(root, "version-double-prefixed")
    run_directory = Path.join(root, "version-double-prefixed-run")
    output = "vv0.58.3\n"

    assert {:error,
            %Error{
              phase: :version_probe,
              reason: {:unparseable_version, ^output},
              executable: ^executable,
              output: ^output
            }} = run_directory |> plan() |> Apalachex.run(executable: executable)

    refute File.exists?(run_directory)
  end

  test "enforces a single exact supported version line before reservation", %{root: root} do
    prefixed = install_fake(root, "version-prefixed")

    assert {:ok, %Result{version: %Version{major: 0, minor: 58, patch: 3}}} =
             root |> Path.join("prefixed-run") |> plan() |> Apalachex.run(executable: prefixed)

    cases = [
      {"unsupported", :version_compatibility, :unsupported_version},
      {"banner", :version_probe, :unparseable_version},
      {"invalid-version", :version_probe, :unparseable_version},
      {"version-fail", :version_probe, :process_failed}
    ]

    for {name, phase, reason_code} <- cases do
      executable = install_fake(Path.join(root, name), name)
      run_directory = Path.join(root, "#{name}-run")

      assert {:error, %Error{phase: ^phase, reason: reason, output: output}} =
               run_directory |> plan() |> Apalachex.run(executable: executable)

      assert elem(reason, 0) == reason_code
      assert is_binary(output)
      refute File.exists?(run_directory)
    end
  end

  test "reserves the exact directory exclusively and never reuses content", %{root: root} do
    executable = install_fake(root, "supported")
    run_directory = Path.join([root, "parent", "exact"])

    assert {:ok, %Result{}} =
             run_directory |> plan() |> Apalachex.run(executable: executable)

    sentinel = Path.join(run_directory, "keep.txt")
    File.write!(sentinel, "keep")

    assert {:error, %Error{phase: :run_directory, reason: :run_directory_already_exists}} =
             run_directory |> plan() |> Apalachex.run(executable: executable)

    assert File.read!(sentinel) == "keep"
  end

  test "executes shell-free with exact argv, cwd, merged binary output, and ordered ITFs", %{
    root: root
  } do
    executable = install_fake(root, "binary-output")
    working_directory = Path.join(root, "formal models")
    File.mkdir!(working_directory)
    source = Path.join(working_directory, "$(touch forbidden).tla")
    config = Path.join(working_directory, "Counter.cfg")
    File.write!(source, "---- MODULE Counter ----")
    File.cp!(@config, config)
    run_directory = Path.join(root, "run")

    custom_plan =
      Plan.new(%Spec{source: source, config: config},
        mode: :simulate,
        length: 2,
        max_run: 1,
        run_directory: run_directory
      )

    assert {:ok, %Result{output: output, exit_status: 0, itf_paths: [itf]}} =
             Apalachex.run(custom_plan, executable: executable)

    assert output == <<"stdout", 255, "bytes\nstderr", 254, "bytes\n">>
    assert itf == Path.join(run_directory, "binary.itf.json")

    assert run_directory |> Path.join("working-directory.txt") |> File.read!() |> String.trim() ==
             Path.dirname(source)

    assert run_directory |> Path.join("argv.txt") |> File.read!() |> String.split("\n", trim: true) ==
             custom_plan.argv

    refute working_directory |> Path.join("forbidden") |> File.exists?()
  end

  test "discovers only top-level regular ITFs in lexical order", %{root: root} do
    executable = install_fake(root, "supported")
    run_directory = Path.join(root, "run")

    assert {:ok, %Result{itf_paths: paths}} =
             run_directory |> plan() |> Apalachex.run(executable: executable)

    assert Enum.map(paths, &Path.basename/1) == ["a.itf.json", "z.itf.json"]
    assert Enum.all?(paths, &(Path.type(&1) == :absolute and File.regular?(&1)))
  end

  test "classifies zero and nonzero no-artifact outcomes and retains reservations", %{root: root} do
    zero = install_fake(root, "no-itf")
    nonzero = install_fake(root, "no-itf-nonzero")
    zero_run = Path.join(root, "zero-run")
    nonzero_run = Path.join(root, "nonzero-run")

    assert {:error, %Error{phase: :itf_discovery, reason: :no_itf_artifacts, exit_status: 0}} =
             zero_run |> plan() |> Apalachex.run(executable: zero)

    assert {:error,
            %Error{
              phase: :execution,
              reason: {:process_failed_without_itf, 9},
              exit_status: 9
            }} = nonzero_run |> plan() |> Apalachex.run(executable: nonzero)

    assert File.dir?(zero_run)
    assert File.dir?(nonzero_run)
  end

  test "succeeds with retained artifacts despite status 12", %{root: root} do
    executable = install_fake(root, "status12")

    assert {:ok, %Result{exit_status: 12, itf_paths: [path]}} =
             root |> Path.join("run") |> plan() |> Apalachex.run(executable: executable)

    assert File.regular?(path)
  end

  defp install_fake(directory, name) do
    File.mkdir_p!(directory)
    executable = Path.join(directory, name)
    File.cp!(@fake, executable)
    File.chmod!(executable, 0o755)
    executable
  end

  defp plan(run_directory) do
    Plan.new(%Spec{source: @source, config: @config},
      mode: :simulate,
      length: 2,
      max_run: 1,
      run_directory: run_directory
    )
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)
end
