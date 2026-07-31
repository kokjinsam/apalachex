defmodule Apalachex.Error do
  @moduledoc "A structured Apalache execution, artifact, or manifest failure."

  alias Apalachex.Output

  defexception [
    :phase,
    :reason,
    :plan,
    :executable,
    :version,
    :exit_status,
    :output,
    itf_paths: [],
    manifest_failure: nil
  ]

  @type phase ::
          :executable_discovery
          | :version_probe
          | :version_compatibility
          | :run_directory
          | :execution
          | :itf_discovery
          | :manifest

  @type t :: %__MODULE__{
          phase: phase(),
          reason: term(),
          plan: Apalachex.Plan.t() | nil,
          executable: Path.t() | nil,
          version: Version.t() | nil,
          exit_status: non_neg_integer() | nil,
          output: binary() | nil,
          itf_paths: [Path.t()],
          manifest_failure: term() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    message =
      [
        "Apalachex #{error.phase} error: #{render(error.reason)}",
        plan_context(error.plan),
        optional("executable", error.executable),
        optional("version", error.version),
        optional("exit status", error.exit_status),
        paths(error.itf_paths),
        output(error.output),
        manifest_failure(error.manifest_failure)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    message |> Output.tail() |> elem(0)
  end

  defp plan_context(%Apalachex.Plan{} = plan) do
    "mode: #{plan.mode}; source: #{inspect(plan.spec.source)}; run directory: #{inspect(plan.run_directory)}"
  end

  defp plan_context(_plan), do: nil
  defp optional(_label, nil), do: nil
  defp optional(label, value), do: "#{label}: #{value}"
  defp paths([]), do: nil
  defp paths(paths), do: "ITF paths: #{inspect(paths)}"
  defp output(nil), do: nil
  defp output(""), do: nil
  defp output(output), do: "output tail:\n#{output |> Output.tail() |> elem(0)}"
  defp manifest_failure(nil), do: nil
  defp manifest_failure(reason), do: "secondary manifest failure: #{render(reason)}"
  defp render(term), do: term |> inspect() |> Output.tail() |> elem(0)
end
