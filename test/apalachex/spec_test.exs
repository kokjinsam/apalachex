defmodule Apalachex.SpecTest do
  use ExUnit.Case, async: true

  alias Apalachex.Spec
  alias Apalachex.Spec.Error

  setup do
    root = "tmp/tests" |> Path.join("spec-#{System.unique_integer([:positive])}") |> Path.expand()
    File.mkdir_p!(root)
    %{root: root}
  end

  test "constructs absolute source and optional config paths", %{root: root} do
    source = Path.join(root, "Counter.tla")
    config = Path.join(root, "Counter.cfg")
    File.write!(source, "---- MODULE Counter ----")
    File.write!(config, "INIT Init")

    assert {:ok, %Spec{source: ^source, config: nil}} = Spec.new(source: source)

    assert {:ok, %Spec{source: ^source, config: ^config}} =
             Spec.new(source: source, config: config)
  end

  test "expands lexically without resolving a symlink", %{root: root} do
    target = Path.join(root, "Target.tla")
    source = Path.join(root, "Linked.tla")
    File.write!(target, "---- MODULE Target ----")
    File.ln_s!(target, source)

    assert {:ok, %Spec{source: ^source}} = Spec.new(source: source)
  end

  test "raises for strict option misuse", %{root: root} do
    source = Path.join(root, "Counter.tla")
    File.write!(source, "---- MODULE Counter ----")

    invalid = [
      :not_keyword,
      [],
      [source: source, source: source],
      [source: source, extra: true],
      [source: nil],
      [source: " "],
      [source: source, config: nil],
      [source: source, config: "\t"]
    ]

    for options <- invalid do
      assert_raise ArgumentError, fn -> Spec.new(options) end
    end
  end

  test "requires exact case-sensitive extensions before file lookup", %{root: root} do
    uppercase = Path.join(root, "Missing.TLA")
    extensionless = Path.join(root, "Missing")

    assert {:error, %Error{field: :source, path: ^uppercase, reason: {:invalid_extension, ".TLA"}}} =
             Spec.new(source: uppercase)

    assert {:error, %Error{reason: {:invalid_extension, ""}}} =
             Spec.new(source: extensionless)
  end

  test "returns structured missing and non-regular artifact failures", %{root: root} do
    source = Path.join(root, "Missing.tla")
    directory_config = Path.join(root, "Directory.cfg")
    File.mkdir!(directory_config)

    assert {:error, %Error{field: :source, path: ^source, reason: :not_found}} =
             Spec.new(source: source)

    valid_source = Path.join(root, "Valid.tla")
    File.write!(valid_source, "---- MODULE Valid ----")

    assert {:error, %Error{field: :config, path: ^directory_config, reason: :not_a_regular_file}} =
             Spec.new(source: valid_source, config: directory_config)
  end

  test "renders its frozen structured reasons" do
    assert Exception.message(%Error{
             field: :source,
             path: "/tmp/Missing.tla",
             reason: :not_found
           }) ==
             "Apalachex specification error for source at \"/tmp/Missing.tla\": file not found"
  end
end
