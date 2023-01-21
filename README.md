# ExWaiter

[![CI Status](https://github.com/baldwindavid/ex_waiter/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/baldwindavid/ex_waiter/actions/workflows/build-and-test.yml)

Handy functions for polling and receiving.

- Polling: `poll/2` and `poll!/2` periodically check that a given condition has been met.
- Receiving: `receive/2` and `receive!/2` return the next message/s from the mailbox within a timeout.

Hexdocs found at
[https://hexdocs.pm/ex_waiter](https://hexdocs.pm/ex_waiter).

## Installation

Add the latest release to your `mix.exs` file:

```elixir
defp deps do
  [
    {:ex_waiter, "~> 0.7.0"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

## Warning

This library was recently released and the API has not yet fully
stabilized. Breaking changes will occur between minor versions prior to 1.0.

## Thanks

Thanks to [@itsgreggreg](https://github.com/itsgreggreg) and [@s3cur3](https://github.com/s3cur3), for providing helpful feedback. 
