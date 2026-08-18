defmodule Apalachex.ManifestTest do
  use ExUnit.Case, async: false

  alias Apalachex.Error
  alias Apalachex.Manifest
  alias Apalachex.Plan
  alias Apalachex.Result
  alias Apalachex.Spec

  @fake Path.expand("../fixtures/apalache/fake-apalache", __DIR__)
  @source Path.expand("../fixtures/specs/Counter.tla", __DIR__)

  setup_all do
    observer = System.find_executable("kill") || flunk("POSIX kill observer is not available")
    assert File.regular?(observer), "POSIX kill observer is not a regular file: #{observer}"

    {control_pid, ""} = System.pid() |> to_string() |> Integer.parse()
    assert :alive == observe_pid(observer, control_pid, control_pid)

    %{observer: observer, control_pid: control_pid}
  end

  setup do
    root =
      "tmp/tests"
      |> Path.join("manifest-#{System.os_time(:nanosecond)}-#{System.pid()}-#{System.unique_integer([:positive])}")
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
    assert running["producer"] == %{"name" => "apalachex", "version" => "0.2.0"}
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

  test "retains partial timeout evidence in the existing completed failed manifest", %{
    root: root,
    observer: observer,
    control_pid: control_pid
  } do
    executable = install_fake(root, "execution-timeout")
    plan = plan(Path.join(root, "run"))
    output = <<"partial output", 255, "\npartial error", 254, "\n">>
    caller = Task.async(fn -> Apalachex.run(plan, executable: executable, timeout: 250) end)
    pid = await_pid(plan.run_directory, 2_000)

    assert :alive == observe_pid(observer, pid, control_pid)

    assert {:error,
            %Error{
              phase: :execution,
              reason: {:timeout, 250},
              executable: ^executable,
              version: %Version{major: 0, minor: 58, patch: 3},
              exit_status: nil,
              output: ^output,
              itf_paths: []
            }} = Task.await(caller, 2_000)

    assert plan.run_directory |> Path.join("partial.itf.json") |> File.regular?()

    completed = decode(Path.join(plan.run_directory, "apalachex-run.json"))
    assert completed["status"] == "completed"
    assert completed["outcome"] == "failed"
    assert completed["execution"]["exit_status"] == nil
    assert completed["execution"]["output"]["byte_size"] == byte_size(output)
    assert completed["artifacts"]["itf_paths"] == []
    assert completed["failure"]["phase"] == "execution"
    assert completed["failure"]["reason"] == "timeout"
    assert_pid_gone(observer, pid, control_pid, 5_000)
  end

  test "caller death stops the direct process and can leave a running manifest", %{
    root: root,
    observer: observer,
    control_pid: control_pid
  } do
    executable = install_fake(root, "execution-timeout")
    plan = plan(Path.join(root, "run"))
    caller = spawn(fn -> Apalachex.run(plan, executable: executable) end)

    pid = await_pid(plan.run_directory, 2_000)
    assert :alive == observe_pid(observer, pid, control_pid)
    manifest_path = Path.join(plan.run_directory, "apalachex-run.json")
    await_file(manifest_path, 2_000)
    assert decode(manifest_path)["status"] == "running"

    Process.exit(caller, :kill)

    assert_pid_gone(observer, pid, control_pid, 5_000)
    refute Process.alive?(caller)
    assert decode(manifest_path)["status"] == "running"
  end

  test "an unexpected target observer result does not prove PID absence", %{
    root: root,
    observer: observer,
    control_pid: control_pid
  } do
    executable = install_fake(root, "execution-timeout")
    plan = plan(Path.join(root, "run"))
    caller = spawn(fn -> Apalachex.run(plan, executable: executable) end)
    pid = await_pid(plan.run_directory, 2_000)

    try do
      assert :alive == observe_pid(observer, pid, control_pid)

      unexpected_observer = Path.join(root, "unexpected-observer")

      File.write!(
        unexpected_observer,
        "#!/bin/sh\n" <>
          "if [ \"$2\" = \"#{pid}\" ]; then\n" <>
          "  echo \"unexpected observer result for PID $2\" >&2\n" <>
          "  exit 42\n" <>
          "fi\n" <>
          "exec \"#{observer}\" \"$@\"\n"
      )

      File.chmod!(unexpected_observer, 0o755)

      assert {:observer_error, _reason} =
               observe_pid(unexpected_observer, pid, control_pid)

      assert :alive == observe_pid(observer, pid, control_pid)
    after
      Process.exit(caller, :kill)
      assert_pid_gone(observer, pid, control_pid, 5_000)
    end
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

  defp await_pid(run_directory, timeout) do
    pid_path = Path.join(run_directory, "process.pid")
    deadline = System.monotonic_time(:millisecond) + timeout

    await(deadline, fn ->
      with {:ok, pid_text} <- File.read(pid_path),
           {pid, ""} when pid > 0 <- pid_text |> String.trim() |> Integer.parse() do
        {:ok, pid}
      else
        _other -> :retry
      end
    end)
  end

  defp await_file(path, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    await(deadline, fn -> if File.regular?(path), do: {:ok, :ok}, else: :retry end)
  end

  defp assert_pid_gone(observer, pid, control_pid, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    assert :ok ==
             await(deadline, fn ->
               case observe_pid(observer, pid, control_pid) do
                 :alive -> :retry
                 :gone -> {:ok, :ok}
                 {:observer_error, reason} -> flunk("PID observer failed: #{inspect(reason)}")
               end
             end)
  end

  defp observe_pid(observer, pid, control_pid) do
    case observer_status(observer, pid) do
      {:ok, 0, _output} ->
        :alive

      {:ok, target_status, target_output} ->
        confirm_pid_absence(observer, pid, target_status, target_output, control_pid)

      {:error, reason} ->
        {:observer_error, {:target_observation_failed, reason}}
    end
  end

  defp confirm_pid_absence(observer, pid, target_status, target_output, control_pid) do
    case record_exited_pid() do
      {:ok, exited_pid} ->
        confirm_pid_absence(
          observer,
          {target_status, target_output, pid},
          exited_pid,
          control_pid
        )

      {:error, reason} ->
        failure = {:known_exited_pid_failed, reason}
        {:observer_error, {:target_absence_unconfirmed, target_status, target_output, failure}}
    end
  end

  defp confirm_pid_absence(observer, target_result, exited_pid, control_pid) do
    exited_result = observer_status(observer, exited_pid)
    control_result = observer_status(observer, control_pid)

    if confirmed_absence?(target_result, exited_result, exited_pid, control_result) do
      :gone
    else
      {target_status, target_output, _pid} = target_result
      observer_error(target_status, target_output, exited_result, control_result)
    end
  end

  defp confirmed_absence?(
         {target_status, target_output, pid},
         {:ok, exited_status, exited_output},
         exited_pid,
         {:ok, 0, _control_output}
       )
       when exited_status != 0 do
    normalize_pid_result(target_status, target_output, pid) ==
      normalize_pid_result(exited_status, exited_output, exited_pid)
  end

  defp confirmed_absence?(_target_result, _exited_result, _exited_pid, _control_result), do: false

  defp normalize_pid_result(status, output, pid) do
    {status, String.replace(output, Integer.to_string(pid), "<pid>")}
  end

  defp observer_error(target_status, target_output, exited_result, control_result) do
    {:observer_error, {:target_absence_unconfirmed, target_status, target_output, exited_result, control_result}}
  end

  defp record_exited_pid do
    sleep = System.find_executable("sleep") || raise "sleep executable is not available"
    port = Port.open({:spawn_executable, sleep}, [{:args, ["1"]}, :exit_status])
    {:os_pid, pid} = Port.info(port, :os_pid)

    receive do
      {^port, {:exit_status, 0}} -> {:ok, pid}
      {^port, {:exit_status, status}} -> {:error, {:exit_status, status}}
    after
      2_000 ->
        if Port.info(port), do: Port.close(port)
        {:error, :timeout}
    end
  rescue
    exception in [ErlangError, ArgumentError, RuntimeError] ->
      {:error, Exception.message(exception)}
  end

  defp observer_status(observer, pid) do
    {output, status} =
      System.cmd(observer, ["-0", Integer.to_string(pid)],
        env: [{"GITHUB_TOKEN", nil}, {"HEX_API_KEY", nil}],
        stderr_to_stdout: true
      )

    {:ok, status, output}
  rescue
    exception in [ErlangError, ArgumentError] -> {:error, Exception.message(exception)}
  end

  defp await(deadline, function) do
    case function.() do
      {:ok, value} ->
        value

      :retry ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("condition did not become true before the timeout")
        else
          Process.sleep(25)
          await(deadline, function)
        end
    end
  end
end
