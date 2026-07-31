defmodule Apalachex.Manifest do
  @moduledoc false

  alias Apalachex.Error
  alias Apalachex.Output
  alias Apalachex.Plan
  alias Apalachex.Result

  @filename "apalachex-run.json"
  @writer_key {__MODULE__, :writer}

  @spec path(Plan.t()) :: Path.t()
  def path(%Plan{run_directory: directory}), do: Path.join(directory, @filename)

  @spec running(Plan.t(), Path.t(), Version.t(), DateTime.t()) :: map()
  def running(plan, executable, version, started_at) do
    base(plan, executable, version, started_at)
  end

  @spec completed(
          Plan.t(),
          Path.t(),
          Version.t(),
          DateTime.t(),
          DateTime.t(),
          {:ok, Result.t()} | {:error, Error.t()}
        ) :: map()
  def completed(plan, executable, version, started_at, completed_at, result) do
    plan
    |> base(executable, version, started_at)
    |> Map.merge(completed_fields(result, max_datetime(started_at, completed_at)))
  end

  @spec write(:initial | :final, Path.t(), map()) :: :ok | {:error, term()}
  def write(stage, path, document) when stage in [:initial, :final] do
    writer = Process.get(@writer_key, &write_atomic/2)

    try do
      writer.(path, document)
    rescue
      exception -> {:error, {:write, exception}}
    catch
      kind, reason -> {:error, {:write, {kind, reason}}}
    end
  end

  @doc "Runs a function with a process-local manifest writer."
  def with_writer(writer, function) when is_function(writer, 2) and is_function(function, 0) do
    previous = Process.put(@writer_key, writer)

    try do
      function.()
    after
      if previous == nil,
        do: Process.delete(@writer_key),
        else: Process.put(@writer_key, previous)
    end
  end

  @doc "Atomically writes a manifest document."
  @spec write_atomic(Path.t(), map()) :: :ok | {:error, term()}
  def write_atomic(path, document) do
    with {:ok, encoded} <- encode(document) do
      persist(path, encoded <> "\n")
    end
  end

  defp base(plan, executable, version, started_at) do
    %{
      "schema" => "apalachex.run",
      "schema_version" => 1,
      "status" => "running",
      "outcome" => nil,
      "producer" => %{"name" => "apalachex", "version" => producer_version()},
      "started_at" => DateTime.to_iso8601(started_at),
      "completed_at" => nil,
      "spec" => %{"source" => plan.spec.source, "config" => plan.spec.config},
      "plan" => %{
        "mode" => Atom.to_string(plan.mode),
        "working_directory" => plan.working_directory,
        "run_directory" => plan.run_directory,
        "options" => Map.new(plan.options, fn {key, value} -> {Atom.to_string(key), value} end),
        "argv" => plan.argv
      },
      "execution" => %{
        "executable" => executable,
        "apalache_version" => Version.to_string(version),
        "exit_status" => nil,
        "output" => nil
      },
      "artifacts" => %{"itf_paths" => []},
      "failure" => nil
    }
  end

  defp completed_fields({:ok, %Result{} = result}, completed_at) do
    %{
      "status" => "completed",
      "outcome" => "materialized",
      "completed_at" => DateTime.to_iso8601(completed_at),
      "execution" => execution(result),
      "artifacts" => %{"itf_paths" => relative_paths(result.plan, result.itf_paths)},
      "failure" => nil
    }
  end

  defp completed_fields({:error, %Error{} = error}, completed_at) do
    %{
      "status" => "completed",
      "outcome" => "failed",
      "completed_at" => DateTime.to_iso8601(completed_at),
      "execution" => execution(error),
      "artifacts" => %{"itf_paths" => relative_paths(error.plan, error.itf_paths)},
      "failure" => %{
        "phase" => Atom.to_string(error.phase),
        "reason" => reason_code(error.reason),
        "message" => error |> Exception.message() |> Output.tail() |> elem(0)
      }
    }
  end

  defp execution(result) do
    %{
      "executable" => result.executable,
      "apalache_version" => result.version && Version.to_string(result.version),
      "exit_status" => result.exit_status,
      "output" => result.output && Output.summary(result.output)
    }
  end

  defp relative_paths(plan, paths) do
    Enum.map(paths, &Path.relative_to(&1, plan.run_directory))
  end

  defp reason_code(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp reason_code(reason) when is_tuple(reason) and tuple_size(reason) > 0 do
    case elem(reason, 0) do
      atom when is_atom(atom) -> Atom.to_string(atom)
      _value -> "unknown"
    end
  end

  defp reason_code(_reason), do: "unknown"

  defp producer_version do
    case Application.spec(:apalachex, :vsn) do
      version when is_list(version) -> List.to_string(version)
      version when version != nil -> to_string(version)
      nil -> "0.1.0"
    end
  end

  defp max_datetime(first, second) do
    if DateTime.before?(second, first), do: first, else: second
  end

  defp encode(document) do
    {:ok, JSON.encode!(document)}
  rescue
    exception -> {:error, {:encoding, exception}}
  catch
    kind, reason -> {:error, {:encoding, {kind, reason}}}
  end

  defp persist(path, contents) do
    basename = Path.basename(path)

    temporary =
      path
      |> Path.dirname()
      |> Path.join(".#{basename}.tmp-#{System.unique_integer([:positive, :monotonic])}")

    result =
      with :ok <- File.write(temporary, contents, [:binary, :exclusive]),
           :ok <- File.rename(temporary, path) do
        :ok
      else
        {:error, reason} -> {:error, {:write, reason}}
      end

    if result != :ok, do: File.rm(temporary)
    result
  end
end
