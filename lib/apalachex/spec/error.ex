defmodule Apalachex.Spec.Error do
  @moduledoc "A specification artifact validation failure."

  @enforce_keys [:field, :path, :reason]
  defexception [:field, :path, :reason]

  @type reason ::
          :not_found
          | :not_a_regular_file
          | {:invalid_extension, String.t()}
          | {:filesystem, File.posix()}

  @type t :: %__MODULE__{
          field: :source | :config,
          path: Path.t(),
          reason: reason()
        }

  @impl Exception
  def message(%__MODULE__{field: field, path: path, reason: reason}) do
    "Apalachex specification error for #{field} at #{inspect(path)}: #{format_reason(reason)}"
  end

  defp format_reason(:not_found), do: "file not found"
  defp format_reason(:not_a_regular_file), do: "path is not a regular file"

  defp format_reason({:invalid_extension, extension}), do: "invalid extension #{inspect(extension)}"

  defp format_reason({:filesystem, reason}), do: "filesystem error #{inspect(reason)}"
end
