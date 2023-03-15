defmodule ExWaiter.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_waiter,
      version: "1.3.0",
      description: "Handy functions for polling, rate limiting, and receiving.",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def docs do
    [
      main: "ExWaiter",
      source_url_pattern: "https://github.com/baldwindavid/ex_waiter/blob/main/%{path}#L%{line}"
    ]
  end

  def package do
    [
      maintainers: ["David Baldwin"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/baldwindavid/ex_waiter"},
      files: ~w(mix.exs README.md lib)
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end
end
