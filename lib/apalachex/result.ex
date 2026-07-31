defmodule Apalachex.Result do
  @moduledoc "A completed Apalache run with retained ITF artifacts."

  alias Apalachex.Plan

  @enforce_keys [:plan, :executable, :version, :exit_status, :output, :itf_paths]
  defstruct [:plan, :executable, :version, :exit_status, :output, :itf_paths]

  @type t :: %__MODULE__{
          plan: Plan.t(),
          executable: Path.t(),
          version: Version.t(),
          exit_status: non_neg_integer(),
          output: binary(),
          itf_paths: [Path.t(), ...]
        }
end
