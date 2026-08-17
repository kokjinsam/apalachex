defmodule Apalachex.PublicContractTest do
  use ExUnit.Case, async: true

  alias Apalachex.Error
  alias Apalachex.Plan
  alias Apalachex.Result
  alias Apalachex.Spec

  test "freezes the public struct fields" do
    assert Spec.__struct__() |> Map.keys() |> Enum.sort() == [:__struct__, :config, :source]

    assert Spec.Error.__struct__() |> Map.keys() |> Enum.sort() ==
             [:__exception__, :__struct__, :field, :path, :reason]

    assert Plan.__struct__() |> Map.keys() |> Enum.sort() ==
             [:__struct__, :argv, :mode, :options, :run_directory, :spec, :working_directory]

    assert Result.__struct__() |> Map.keys() |> Enum.sort() ==
             [:__struct__, :executable, :exit_status, :itf_paths, :output, :plan, :version]

    assert Error.__struct__() |> Map.keys() |> Enum.sort() ==
             [
               :__exception__,
               :__struct__,
               :executable,
               :exit_status,
               :itf_paths,
               :manifest_failure,
               :output,
               :phase,
               :plan,
               :reason,
               :version
             ]
  end

  test "freezes specification artifact reasons" do
    reasons = [
      :not_found,
      :not_a_regular_file,
      {:invalid_extension, ".TLA"},
      {:filesystem, :eacces}
    ]

    for reason <- reasons do
      assert %Spec.Error{field: :source, path: "/tmp/A.tla", reason: reason}.reason == reason
    end
  end

  test "freezes execution phases and reasons" do
    contracts = [
      executable_discovery: [
        {:not_found, "apalache-mc"},
        {:not_a_regular_file, "/tmp/tool"},
        {:not_executable, "/tmp/tool"},
        {:filesystem, :eacces}
      ],
      version_probe: [
        {:process_failed, 2},
        {:timeout, 5_000},
        {:unparseable_version, "unknown"}
      ],
      version_compatibility: [
        {:unsupported_version, Version.parse!("0.58.2"), Version.parse!("0.58.3")}
      ],
      run_directory: [
        :run_directory_already_exists,
        {:parent_creation_failed, :eacces},
        {:creation_failed, :eacces}
      ],
      execution: [
        {:timeout, 250},
        {:process_failed_without_itf, 9}
      ],
      itf_discovery: [
        :no_itf_artifacts,
        {:directory_listing_failed, :eacces},
        {:artifact_stat_failed, "/tmp/a.itf.json", :eacces}
      ],
      manifest: [
        {:manifest_encoding_failed, :initial, :badarg},
        {:manifest_write_failed, :final, "/tmp/apalachex-run.json", :eacces}
      ]
    ]

    for {phase, reasons} <- contracts, reason <- reasons do
      error = %Error{phase: phase, reason: reason}
      assert error.phase == phase
      assert error.reason == reason
    end
  end

  test "exports only run/1 and run/2 at the package boundary" do
    Code.ensure_loaded!(Apalachex)
    assert function_exported?(Apalachex, :run, 1)
    assert function_exported?(Apalachex, :run, 2)
  end

  test "setup rejects missing native prerequisites before it calls asdf" do
    root =
      Path.join(System.tmp_dir!(), "apalachex-setup-#{System.os_time(:nanosecond)}")

    bin = Path.join(root, "bin")
    sentinel = Path.join(root, "asdf-called")
    File.mkdir_p!(bin)
    "bash" |> System.find_executable() |> File.ln_s!(Path.join(bin, "bash"))
    write_executable(Path.join(bin, "asdf"), "#!/bin/sh\n: > \"$SETUP_SENTINEL\"\n")

    assert_setup_failure(bin, sentinel, "make is required to build native dependencies", [])

    write_executable(Path.join(bin, "make"), "#!/bin/sh\nexit 0\n")

    assert_setup_failure(bin, sentinel, "POSIX C compiler cc is required to build native dependencies", [])
  end

  test "setup rejects an explicitly empty CC before it calls asdf" do
    root =
      Path.join(System.tmp_dir!(), "apalachex-setup-empty-cc-#{System.os_time(:nanosecond)}")

    bin = Path.join(root, "bin")
    sentinel = Path.join(root, "asdf-called")
    File.mkdir_p!(bin)
    "bash" |> System.find_executable() |> File.ln_s!(Path.join(bin, "bash"))
    write_executable(Path.join(bin, "make"), "#!/bin/sh\nexit 0\n")
    write_executable(Path.join(bin, "cc"), "#!/bin/sh\nexit 0\n")
    write_executable(Path.join(bin, "asdf"), "#!/bin/sh\n: > \"$SETUP_SENTINEL\"\n")

    assert_setup_failure(bin, sentinel, "CC must not be empty", [{"CC", ""}])
  end

  defp assert_setup_failure(bin, sentinel, message, environment) do
    just = resolve_just()

    assignments =
      ["PATH=#{bin}", "SETUP_SENTINEL=#{sentinel}"] ++
        for {name, value} <- environment, value != nil, do: "#{name}=#{value}"

    {output, status} =
      System.cmd("/usr/bin/env", ["-i" | assignments] ++ [just, "setup"],
        cd: Path.expand("..", __DIR__),
        env: [{"GITHUB_TOKEN", nil}, {"HEX_API_KEY", nil}],
        stderr_to_stdout: true
      )

    assert status != 0
    assert output =~ "setup: #{message}"
    refute File.exists?(sentinel)
  end

  defp resolve_just do
    just = System.find_executable("just") || flunk("just is not available")

    if just |> Path.dirname() |> Path.basename() == "shims" do
      asdf = System.find_executable("asdf") || flunk("asdf is not available for the just shim")

      case System.cmd(asdf, ["which", "just"], env: [{"GITHUB_TOKEN", nil}, {"HEX_API_KEY", nil}]) do
        {output, 0} -> String.trim(output)
        {output, status} -> flunk("asdf could not resolve just (#{status}): #{output}")
      end
    else
      just
    end
  end

  defp write_executable(path, contents) do
    File.write!(path, contents)
    File.chmod!(path, 0o755)
  end
end
