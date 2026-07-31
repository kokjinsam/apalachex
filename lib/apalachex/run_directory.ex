defmodule Apalachex.RunDirectory do
  @moduledoc """
  Builds deterministic run-directory paths without touching the filesystem.
  """

  alias Apalachex.Spec

  @suffix ~r/\A[0-9a-f]{6}\z/

  @doc "Builds an absolute run-directory path."
  @spec build(Spec.t(), keyword()) :: Path.t()
  def build(%Spec{} = spec, options) do
    validate_options!(options)

    generated_at = Keyword.fetch!(options, :generated_at)
    suffix = Keyword.fetch!(options, :suffix)
    root = Keyword.get(options, :root, "tmp/apalachex")

    validate_timestamp!(generated_at)
    validate_suffix!(suffix)
    validate_root!(root)

    filename =
      Enum.join(
        [Calendar.strftime(generated_at, "%Y%m%dT%H%M%SZ"), slug(spec.source), suffix],
        "-"
      )

    root |> Path.expand() |> Path.join(filename)
  end

  def build(_spec, _options), do: raise(ArgumentError, "expected an Apalachex.Spec")

  defp validate_options!(options) do
    unless Keyword.keyword?(options), do: raise(ArgumentError, "expected a keyword list")
    keys = Keyword.keys(options)
    if Enum.uniq(keys) != keys, do: raise(ArgumentError, "duplicate options are not allowed")

    unknown = keys -- [:generated_at, :suffix, :root]
    if unknown != [], do: raise(ArgumentError, "unknown options: #{inspect(unknown)}")

    for key <- [:generated_at, :suffix], key not in keys do
      raise ArgumentError, "missing required option #{inspect(key)}"
    end
  end

  defp validate_timestamp!(%DateTime{utc_offset: 0, std_offset: 0}), do: :ok
  defp validate_timestamp!(_value), do: raise(ArgumentError, "expected a UTC DateTime")

  defp validate_suffix!(suffix) when is_binary(suffix) do
    unless Regex.match?(@suffix, suffix) do
      raise ArgumentError, "expected exactly six lowercase hexadecimal characters"
    end
  end

  defp validate_suffix!(_value),
    do: raise(ArgumentError, "expected exactly six lowercase hexadecimal characters")

  defp validate_root!(root) when is_binary(root) do
    if String.trim(root) == "", do: raise(ArgumentError, "expected a non-blank root")
  end

  defp validate_root!(_root), do: raise(ArgumentError, "expected a non-blank root")

  defp slug(source) do
    source
    |> Path.basename(".tla")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "spec"
      value -> value
    end
  end
end
