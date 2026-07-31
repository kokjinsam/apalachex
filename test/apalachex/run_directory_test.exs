defmodule Apalachex.RunDirectoryTest do
  use ExUnit.Case, async: true

  alias Apalachex.RunDirectory
  alias Apalachex.Spec

  @generated_at ~U[2026-07-31 05:06:07.999999Z]

  test "builds a deterministic absolute path without filesystem mutation" do
    root = Path.expand("tmp/tests/run-directory-absent")
    spec = %Spec{source: "/formal/My  HTTP___Spec-2.tla", config: nil}

    path =
      RunDirectory.build(spec,
        generated_at: @generated_at,
        suffix: "0a1b2c",
        root: root
      )

    assert path == Path.join(root, "20260731T050607Z-my-http-spec-2-0a1b2c")
    refute File.exists?(root)
    refute File.exists?(path)
  end

  test "uses tmp/apalachex and a spec fallback slug" do
    spec = %Spec{source: "/formal/ÅÄ!!!.tla", config: nil}

    assert RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef") ==
             Path.expand("tmp/apalachex/20260731T050607Z-spec-abcdef")
  end

  test "strictly validates arguments" do
    spec = %Spec{source: "/formal/Counter.tla", config: nil}

    invalid = [
      fn -> RunDirectory.build(%{}, generated_at: @generated_at, suffix: "abcdef") end,
      fn -> build(spec, :not_keyword) end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at) end,
      fn -> RunDirectory.build(spec, suffix: "abcdef") end,
      fn ->
        RunDirectory.build(spec,
          generated_at: @generated_at,
          generated_at: @generated_at,
          suffix: "abcdef"
        )
      end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "ABCDEF") end,
      fn -> RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcde") end,
      fn ->
        RunDirectory.build(spec,
          generated_at: %{@generated_at | utc_offset: 3600},
          suffix: "abcdef"
        )
      end,
      fn ->
        RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef", root: " ")
      end,
      fn ->
        RunDirectory.build(spec, generated_at: @generated_at, suffix: "abcdef", extra: true)
      end
    ]

    for call <- invalid, do: assert_raise(ArgumentError, call)
  end

  defp build(spec, options), do: RunDirectory.build(spec, options)
end
