defmodule Apalachex.Plan do
  @moduledoc "A pure, shell-free Apalache invocation plan."

  alias Apalachex.Spec

  @enforce_keys [:spec, :mode, :working_directory, :run_directory, :options, :argv]
  defstruct [:spec, :mode, :working_directory, :run_directory, :options, :argv]

  @type t :: %__MODULE__{
          spec: Spec.t(),
          mode: :simulate | :check,
          working_directory: Path.t(),
          run_directory: Path.t(),
          options: map(),
          argv: [String.t()]
        }

  @doc "Builds a deterministic invocation plan without executing it."
  @spec new(Spec.t(), keyword()) :: t()
  def new(%Spec{} = spec, options) do
    validate_options!(options)

    mode = Keyword.fetch!(options, :mode)
    length = Keyword.fetch!(options, :length)
    run_directory = validate_run_directory!(Keyword.fetch!(options, :run_directory))

    if mode not in [:simulate, :check],
      do: raise(ArgumentError, "expected :mode to be :simulate or :check")

    if !(is_integer(length) and length >= 0),
      do: raise(ArgumentError, "expected :length to be a nonnegative integer")

    build(spec, mode, length, run_directory, options)
  end

  def new(_spec, _options), do: raise(ArgumentError, "expected an Apalachex.Spec")

  defp validate_options!(options) do
    if !Keyword.keyword?(options), do: raise(ArgumentError, "expected a keyword list")
    keys = Keyword.keys(options)
    if Enum.uniq(keys) != keys, do: raise(ArgumentError, "duplicate options are not allowed")

    unknown = keys -- [:mode, :length, :max_run, :run_directory]
    if unknown != [], do: raise(ArgumentError, "unknown options: #{inspect(unknown)}")

    for key <- [:mode, :length, :run_directory], key not in keys do
      raise ArgumentError, "missing required option #{inspect(key)}"
    end
  end

  defp validate_run_directory!(value) when is_binary(value) do
    if String.trim(value) == "",
      do: raise(ArgumentError, "expected :run_directory to be a non-blank string")

    Path.expand(value)
  end

  defp validate_run_directory!(_value), do: raise(ArgumentError, "expected :run_directory to be a non-blank string")

  defp build(spec, :simulate, length, run_directory, options) do
    max_run =
      case Keyword.fetch(options, :max_run) do
        {:ok, value} when is_integer(value) and value > 0 -> value
        {:ok, _value} -> raise ArgumentError, "expected :max_run to be a positive integer"
        :error -> raise ArgumentError, "missing required option :max_run for :simulate"
      end

    make_plan(spec, :simulate, run_directory, %{length: length, max_run: max_run}, [
      "simulate",
      config_argument(spec),
      "--length=#{length}",
      "--max-run=#{max_run}",
      "--output-traces",
      "--run-dir=#{run_directory}",
      spec.source
    ])
  end

  defp build(spec, :check, length, run_directory, options) do
    if Keyword.has_key?(options, :max_run),
      do: raise(ArgumentError, ":max_run is forbidden for :check")

    make_plan(spec, :check, run_directory, %{length: length}, [
      "check",
      config_argument(spec),
      "--length=#{length}",
      "--output-traces",
      "--run-dir=#{run_directory}",
      spec.source
    ])
  end

  defp make_plan(spec, mode, run_directory, options, argv) do
    %__MODULE__{
      spec: spec,
      mode: mode,
      working_directory: Path.dirname(spec.source),
      run_directory: run_directory,
      options: options,
      argv: Enum.reject(argv, &is_nil/1)
    }
  end

  defp config_argument(%Spec{config: nil}), do: nil
  defp config_argument(%Spec{config: config}), do: "--config=#{config}"
end
