defmodule Apalachex do
  @moduledoc """
  Runs deterministic Apalache plans on POSIX systems and returns retained ITF
  artifact paths.

  Windows execution is unsupported in 0.1.0 and is rejected before executable
  discovery, version probing, or run-directory allocation.
  """

  import Bitwise

  alias Apalachex.{Error, Manifest, Plan, Result}

  @supported_version Version.parse!("0.58.3")

  @doc "Runs an Apalache plan with the default executable on a POSIX system."
  @spec run(Plan.t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(plan), do: run(plan, [])

  @doc """
  Runs an Apalache plan on a POSIX system; the only option is `:executable`.

  On Windows, returns an `:execution` error with
  `{:unsupported_platform, :win32}` after validating options and before
  executable discovery, version probing, or run-directory allocation.
  """
  @spec run(Plan.t(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(%Plan{} = plan, options) do
    requested = validate_options!(options)

    with :ok <- validate_platform(plan),
         {:ok, executable} <- resolve_executable(plan, requested),
         {:ok, version} <- probe_version(plan, executable),
         :ok <- reserve(plan, executable, version) do
      run_reserved(plan, executable, version)
    end
  end

  def run(_plan, _options), do: raise(ArgumentError, "expected an Apalachex.Plan")

  defp validate_options!(options) do
    unless Keyword.keyword?(options), do: raise(ArgumentError, "expected a keyword list")
    keys = Keyword.keys(options)
    if Enum.uniq(keys) != keys, do: raise(ArgumentError, "duplicate options are not allowed")

    unknown = keys -- [:executable]
    if unknown != [], do: raise(ArgumentError, "unknown options: #{inspect(unknown)}")

    case Keyword.get(options, :executable, "apalache-mc") do
      executable when is_binary(executable) ->
        if String.trim(executable) == "",
          do: raise(ArgumentError, "expected :executable to be a non-blank string")

        executable

      _value ->
        raise ArgumentError, "expected :executable to be a non-blank string"
    end
  end

  defp validate_platform(plan) do
    case Process.get({__MODULE__, :os_type}, :os.type()) do
      {:unix, _name} -> :ok
      {:win32, _name} -> error(plan, :execution, {:unsupported_platform, :win32})
    end
  end

  defp resolve_executable(plan, requested) do
    if String.contains?(requested, ["/", "\\"]) do
      requested |> Path.expand() |> validate_executable(plan)
    else
      case System.find_executable(requested) do
        nil -> error(plan, :executable_discovery, {:not_found, requested})
        path -> path |> Path.expand() |> validate_executable(plan)
      end
    end
  end

  defp validate_executable(path, plan) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} when band(mode, 0o111) != 0 ->
        {:ok, path}

      {:ok, %File.Stat{type: :regular}} ->
        error(plan, :executable_discovery, {:not_executable, path})

      {:ok, %File.Stat{}} ->
        error(plan, :executable_discovery, {:not_a_regular_file, path})

      {:error, :enoent} ->
        error(plan, :executable_discovery, {:not_found, path})

      {:error, reason} ->
        error(plan, :executable_discovery, {:filesystem, reason})
    end
  end

  defp probe_version(plan, executable) do
    case command(executable, ["version"], stderr_to_stdout: true) do
      {:ok, output, 0} ->
        parse_version(plan, executable, output)

      {:ok, output, status} ->
        error(plan, :version_probe, {:process_failed, status},
          executable: executable,
          exit_status: status,
          output: output
        )

      {:error, :eacces} ->
        error(plan, :executable_discovery, {:not_executable, executable})

      {:error, reason} ->
        error(plan, :version_probe, {:process_start_failed, reason}, executable: executable)
    end
  end

  defp parse_version(plan, executable, output) do
    lines =
      if String.valid?(output) do
        output
        |> String.split(~r/\R/u)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
      else
        []
      end

    case lines do
      [line] when line in ["0.58.3", "v0.58.3"] ->
        {:ok, @supported_version}

      [line] ->
        parse_other_version(plan, executable, output, line)

      _lines ->
        unparseable_version(plan, executable, output)
    end
  end

  defp parse_other_version(plan, executable, output, line) do
    normalized = String.replace_prefix(line, "v", "")

    case Version.parse(normalized) do
      {:ok, %Version{pre: [], build: nil} = version} ->
        error(
          plan,
          :version_compatibility,
          {:unsupported_version, version, @supported_version},
          executable: executable,
          version: version,
          output: output
        )

      _other ->
        unparseable_version(plan, executable, output)
    end
  end

  defp unparseable_version(plan, executable, output) do
    error(plan, :version_probe, {:unparseable_version, output},
      executable: executable,
      output: output
    )
  end

  defp reserve(plan, executable, version) do
    case File.mkdir_p(Path.dirname(plan.run_directory)) do
      :ok ->
        case File.mkdir(plan.run_directory) do
          :ok ->
            :ok

          {:error, :eexist} ->
            error(plan, :run_directory, :run_directory_already_exists,
              executable: executable,
              version: version
            )

          {:error, reason} ->
            error(plan, :run_directory, {:creation_failed, reason},
              executable: executable,
              version: version
            )
        end

      {:error, reason} ->
        error(plan, :run_directory, {:parent_creation_failed, reason},
          executable: executable,
          version: version
        )
    end
  end

  defp run_reserved(plan, executable, version) do
    started_at = DateTime.utc_now()
    path = Manifest.path(plan)
    running = Manifest.running(plan, executable, version, started_at)

    case Manifest.write(:initial, path, running) do
      :ok ->
        result = execute_and_discover(plan, executable, version)

        completed =
          Manifest.completed(
            plan,
            executable,
            version,
            started_at,
            DateTime.utc_now(),
            result
          )

        finish(result, path, completed)

      {:error, failure} ->
        manifest_error(plan, executable, version, :initial, path, failure)
    end
  end

  defp execute_and_discover(plan, executable, version) do
    case command(executable, plan.argv,
           cd: plan.working_directory,
           stderr_to_stdout: true
         ) do
      {:ok, output, status} ->
        discover_itfs(plan, executable, version, output, status)

      {:error, reason} ->
        error(plan, :execution, {:process_start_failed, reason},
          executable: executable,
          version: version
        )
    end
  end

  defp discover_itfs(plan, executable, version, output, status) do
    with {:ok, names} <- list_directory(plan, executable, version, output, status),
         {:ok, paths} <- regular_itfs(plan, executable, version, output, status, names) do
      classify_artifacts(plan, executable, version, output, status, Enum.sort(paths))
    end
  end

  defp list_directory(plan, executable, version, output, status) do
    case File.ls(plan.run_directory) do
      {:ok, names} ->
        {:ok, names}

      {:error, reason} ->
        error(plan, :itf_discovery, {:directory_listing_failed, reason},
          executable: executable,
          version: version,
          exit_status: status,
          output: output
        )
    end
  end

  defp regular_itfs(plan, executable, version, output, status, names) do
    names
    |> Enum.filter(&String.ends_with?(&1, ".itf.json"))
    |> Enum.reduce_while({:ok, []}, fn name, {:ok, paths} ->
      path = Path.join(plan.run_directory, name) |> Path.expand()

      case File.lstat(path) do
        {:ok, %File.Stat{type: :regular}} ->
          {:cont, {:ok, [path | paths]}}

        {:ok, %File.Stat{}} ->
          {:cont, {:ok, paths}}

        {:error, reason} ->
          result =
            error(plan, :itf_discovery, {:artifact_stat_failed, path, reason},
              executable: executable,
              version: version,
              exit_status: status,
              output: output
            )

          {:halt, result}
      end
    end)
  end

  defp classify_artifacts(plan, executable, version, output, status, []) when status == 0 do
    error(plan, :itf_discovery, :no_itf_artifacts,
      executable: executable,
      version: version,
      exit_status: status,
      output: output
    )
  end

  defp classify_artifacts(plan, executable, version, output, status, []) do
    error(plan, :execution, {:process_failed_without_itf, status},
      executable: executable,
      version: version,
      exit_status: status,
      output: output
    )
  end

  defp classify_artifacts(plan, executable, version, output, status, paths) do
    {:ok,
     %Result{
       plan: plan,
       executable: executable,
       version: version,
       exit_status: status,
       output: output,
       itf_paths: paths
     }}
  end

  defp finish(result, path, completed) do
    case Manifest.write(:final, path, completed) do
      :ok ->
        result

      {:error, failure} ->
        final_manifest_failure(result, path, failure)
    end
  end

  defp final_manifest_failure({:ok, %Result{} = result}, path, failure) do
    manifest_error(result.plan, result.executable, result.version, :final, path, failure,
      exit_status: result.exit_status,
      output: result.output,
      itf_paths: result.itf_paths
    )
  end

  defp final_manifest_failure({:error, %Error{} = error}, path, failure) do
    {:error, %{error | manifest_failure: manifest_reason(:final, path, failure)}}
  end

  defp manifest_error(plan, executable, version, stage, path, failure, fields \\ []) do
    error(
      plan,
      :manifest,
      manifest_reason(stage, path, failure),
      Keyword.merge([executable: executable, version: version], fields)
    )
  end

  defp manifest_reason(stage, _path, {:encoding, reason}),
    do: {:manifest_encoding_failed, stage, reason}

  defp manifest_reason(stage, path, {:write, reason}),
    do: {:manifest_write_failed, stage, path, reason}

  defp manifest_reason(stage, path, reason),
    do: {:manifest_write_failed, stage, path, reason}

  defp command(executable, argv, options) do
    {output, status} = System.cmd(executable, argv, options)
    {:ok, output, status}
  rescue
    exception in [ErlangError, ArgumentError] ->
      reason =
        if match?(%ErlangError{}, exception),
          do: exception.original,
          else: Exception.message(exception)

      {:error, reason}
  end

  defp error(plan, phase, reason, fields \\ []) do
    {:error, struct!(Error, Keyword.merge([plan: plan, phase: phase, reason: reason], fields))}
  end
end
