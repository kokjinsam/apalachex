defmodule Apalachex.PublicContractTest do
  use ExUnit.Case, async: true

  alias Apalachex.{Error, Plan, Result, Spec}

  test "freezes the public struct fields" do
    assert Map.keys(Spec.__struct__()) |> Enum.sort() == [:__struct__, :config, :source]

    assert Map.keys(Spec.Error.__struct__()) |> Enum.sort() ==
             [:__exception__, :__struct__, :field, :path, :reason]

    assert Map.keys(Plan.__struct__()) |> Enum.sort() ==
             [:__struct__, :argv, :mode, :options, :run_directory, :spec, :working_directory]

    assert Map.keys(Result.__struct__()) |> Enum.sort() ==
             [:__struct__, :executable, :exit_status, :itf_paths, :output, :plan, :version]

    assert Map.keys(Error.__struct__()) |> Enum.sort() ==
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
        {:process_start_failed, :enoexec},
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
        {:unsupported_platform, :win32},
        {:process_start_failed, :enoexec},
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
end
