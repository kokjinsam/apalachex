defmodule ApalachexConsumer.MixProject do
  use Mix.Project

  def project do
    [
      app: :apalachex_consumer,
      version: "0.0.0",
      elixir: "~> 1.18",
      deps: [{:apalachex, path: System.fetch_env!("APALACHEX_PACKAGE_PATH")}]
    ]
  end

  def application, do: []
end
