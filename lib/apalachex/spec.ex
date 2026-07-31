defmodule Apalachex.Spec do
  @moduledoc """
  Identifies validated TLA+ source and optional configuration files.
  """

  @enforce_keys [:source]
  defstruct [:source, :config]

  @type t :: %__MODULE__{source: Path.t(), config: Path.t() | nil}

  alias Apalachex.Spec.Error

  @doc "Validates source and optional config artifacts."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(options) do
    validate_options!(options)

    with {:ok, source} <- validate_artifact(:source, Keyword.fetch!(options, :source), ".tla"),
         {:ok, config} <- validate_config(options) do
      {:ok, %__MODULE__{source: source, config: config}}
    end
  end

  defp validate_options!(options) do
    unless Keyword.keyword?(options), do: raise(ArgumentError, "expected a keyword list")

    keys = Keyword.keys(options)
    if Enum.uniq(keys) != keys, do: raise(ArgumentError, "duplicate options are not allowed")

    unknown = keys -- [:source, :config]
    if unknown != [], do: raise(ArgumentError, "unknown options: #{inspect(unknown)}")
    unless :source in keys, do: raise(ArgumentError, "missing required option :source")

    validate_path_option!(:source, Keyword.fetch!(options, :source))

    if :config in keys do
      validate_path_option!(:config, Keyword.fetch!(options, :config))
    end
  end

  defp validate_path_option!(name, value) when is_binary(value) do
    if String.trim(value) == "" do
      raise ArgumentError, "expected #{inspect(name)} to be a non-blank string"
    end
  end

  defp validate_path_option!(name, _value) do
    raise ArgumentError, "expected #{inspect(name)} to be a non-blank string"
  end

  defp validate_config(options) do
    case Keyword.fetch(options, :config) do
      {:ok, config} -> validate_artifact(:config, config, ".cfg")
      :error -> {:ok, nil}
    end
  end

  defp validate_artifact(field, path, extension) do
    expanded = Path.expand(path)
    actual = Path.extname(expanded)

    if actual == extension do
      validate_regular_file(field, expanded)
    else
      {:error, %Error{field: field, path: expanded, reason: {:invalid_extension, actual}}}
    end
  end

  defp validate_regular_file(field, path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        {:ok, path}

      {:ok, %File.Stat{}} ->
        {:error, %Error{field: field, path: path, reason: :not_a_regular_file}}

      {:error, :enoent} ->
        {:error, %Error{field: field, path: path, reason: :not_found}}

      {:error, reason} ->
        {:error, %Error{field: field, path: path, reason: {:filesystem, reason}}}
    end
  end
end
