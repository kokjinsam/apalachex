defmodule Apalachex.PlanTest do
  use ExUnit.Case, async: true

  alias Apalachex.{Plan, Spec}

  @source "/formal models/Counter.tla"
  @config "/formal config/Counter.cfg"
  @run_directory "/generated traces/run one"

  test "builds exact simulate argv with optional config" do
    spec = %Spec{source: @source, config: @config}

    assert Plan.new(spec,
             mode: :simulate,
             length: 10,
             max_run: 3,
             run_directory: @run_directory
           ) == %Plan{
             spec: spec,
             mode: :simulate,
             working_directory: "/formal models",
             run_directory: @run_directory,
             options: %{length: 10, max_run: 3},
             argv: [
               "simulate",
               "--config=#{@config}",
               "--length=10",
               "--max-run=3",
               "--output-traces",
               "--run-dir=#{@run_directory}",
               @source
             ]
           }
  end

  test "builds exact check argv without config" do
    spec = %Spec{source: @source, config: nil}

    assert %Plan{options: %{length: 0}, argv: argv} =
             Plan.new(spec, mode: :check, length: 0, run_directory: @run_directory)

    assert argv == [
             "check",
             "--length=0",
             "--output-traces",
             "--run-dir=#{@run_directory}",
             @source
           ]
  end

  test "is pure and expands its run directory once" do
    relative = "tmp/tests/plan-#{System.unique_integer([:positive])}"
    expected = Path.expand(relative)
    spec = %Spec{source: @source, config: nil}

    first = Plan.new(spec, mode: :check, length: 1, run_directory: relative)
    second = Plan.new(spec, mode: :check, length: 1, run_directory: relative)

    assert first == second
    assert first.run_directory == expected
    refute File.exists?(expected)
  end

  test "strictly validates mode-specific arguments" do
    spec = %Spec{source: @source, config: nil}

    invalid = [
      fn -> Plan.new(%{}, mode: :check, length: 1, run_directory: "/tmp/run") end,
      fn -> new(spec, :not_keyword) end,
      fn -> Plan.new(spec, mode: :check, length: -1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :other, length: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :simulate, length: 1, run_directory: "/tmp/run") end,
      fn ->
        Plan.new(spec, mode: :simulate, length: 1, max_run: 0, run_directory: "/tmp/run")
      end,
      fn -> Plan.new(spec, mode: :check, length: 1, max_run: 1, run_directory: "/tmp/run") end,
      fn -> Plan.new(spec, mode: :check, length: 1, run_directory: " ") end,
      fn -> Plan.new(spec, mode: :check, length: 1, run_directory: "/tmp/run", extra: true) end,
      fn ->
        Plan.new(spec,
          mode: :check,
          mode: :check,
          length: 1,
          run_directory: "/tmp/run"
        )
      end
    ]

    for call <- invalid, do: assert_raise(ArgumentError, call)
  end

  defp new(spec, options), do: Plan.new(spec, options)
end
