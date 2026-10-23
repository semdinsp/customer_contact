defmodule CustomerContact.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/semdinsp/customer_contact"

  def project do
    [
      app: :customer_contact,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Campaign email for Phoenix apps: paste HTML, test, approve, send to tagged " <>
          "recipients, and track delivery, opens, clicks and unsubscribes.",
      package: package(),
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md", "INTEGRATION_PROMPT.md"]],
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto, :public_key]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.1"},
      {:ecto_sql, "~> 3.12"},
      {:phoenix_ecto, "~> 4.5"},
      {:postgrex, ">= 0.0.0"},
      {:swoosh, "~> 1.16"},
      {:oban, "~> 2.19"},
      {:req, "~> 0.5"},
      {:jason, "~> 1.2"},
      {:plug, "~> 1.16"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md CHANGELOG.md INTEGRATION_PROMPT.md LICENSE .formatter.exs)
    ]
  end
end
