# ExWaiter

[![CI Status](https://github.com/baldwindavid/ex_waiter/actions/workflows/ci.yml/badge.svg)](https://github.com/baldwindavid/ex_waiter/actions/workflows/ci.yml)

Handy functions for rate limiting, polling, and receiving.

- Rate Limiting: `limit_rate/2` enforces a configurable token bucket rate limit.
- Polling: `poll/1`, `poll!/1`, and `poll_once/1` periodically check that a given condition has been met.
- Receiving: `receive_next/2` and `receive_next!/2` return the next message/s from the mailbox within a timeout.

Hexdocs found at
[https://hexdocs.pm/ex_waiter](https://hexdocs.pm/ex_waiter).

## Installation

Add the latest release to your `mix.exs` file:

```elixir
defp deps do
  [
    {:ex_waiter, "~> 1.3.1"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

## Warning

The API for this library has not yet fully stabilized.

## Thanks

Thanks to [@itsgreggreg](https://github.com/itsgreggreg) and [@s3cur3](https://github.com/s3cur3), for providing helpful feedback. 
