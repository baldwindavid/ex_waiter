defmodule ExWaiter.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_waiter,
      version: "0.1.0",
      description: "Helper for waiting on asynchronous conditions to be met.",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
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
