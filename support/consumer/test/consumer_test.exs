defmodule ApalachexConsumerTest do
  use ExUnit.Case, async: true

  test "constructs the public pipeline from the unpacked package" do
    root = Path.join(System.tmp_dir!(), "apalachex-clean-consumer")
    source = Path.join(root, "Counter.tla")
    File.mkdir_p!(root)
    File.write!(source, "---- MODULE Counter ----\n====\n")

    assert {:ok, spec} = Apalachex.Spec.new(source: source)

    run_directory =
      Apalachex.RunDirectory.build(spec,
        generated_at: ~U[2026-07-31 00:00:00Z],
        suffix: "a1b2c3",
        root: root
      )

    plan =
      Apalachex.Plan.new(spec,
        mode: :check,
        length: 0,
        run_directory: run_directory
      )

    assert plan.argv == [
             "check",
             "--length=0",
             "--output-traces",
             "--run-dir=#{run_directory}",
             source
           ]
  end
end
