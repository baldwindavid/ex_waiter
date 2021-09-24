# ExWaiter

[![CI Status](https://github.com/baldwindavid/ex_waiter/actions/workflows/build-and-test.yml/badge.svg)](https://github.com/baldwindavid/ex_waiter/actions/workflows/build-and-test.yml)

Helper for waiting on asynchronous conditions to be met.

Hexdocs found at
[https://hexdocs.pm/ex_waiter](https://hexdocs.pm/ex_waiter).

## Installation

Add the latest release to your `mix.exs` file:

```elixir
defp deps do
  [
    {:ex_waiter, "~> 0.5.0"}
  ]
end
```

Then run `mix deps.get` in your shell to fetch the dependencies.

## Why This Exists?

In some testing scenarios there is no obvious way to ensure that asynchronous
side effects have taken place without continuously checking for successful
completion. For example, perhaps an assertion is needed on click data being
asynchronously persisted to the database. It is not difficult to write a
recursive function to handle this one-off, but there is a bit of ceremony
involved.

Additionally, perhaps it is desirable to configure the amount of delay prior
to each check, the total number of attempts, a convention for handling
exhausted retries, an easy way to inject callbacks, and a record of the
history of each attempt.

This simple package provides all that and more! Well, actually just that.

## A Walkthrough

The package provides `await/2` and `await!/2` functions. Each requires an
anonymous function that may return `{:ok, value}`, `:ok`, or `true` for a
successful attempt or `{:error, value}`, `:error`, or `false` for a failed
attempt. The tagged tuples must be used if you need a return value or want
to track the history of value changes. Additional options are available for
setting the desired number of attempts and custom delay between attempts.

Let's use `await!/2` to check the database for the most recently persisted
click.

```elixir
click = ExWaiter.await!(fn ->
  case Clicks.most_recent() do
    %Click{} = click -> {:ok, click}
    _ -> :error
  end
end)
```

By default, this will check the database up to 5 times spaced out over 150ms.
If, at some point, the condition is met, the `%Click{}` will be returned. If
retries are exhausted, an exception will be raised that looks something like:

```
 ** (ExWaiter.Exceptions.RetriesExhausted) Tried 5 times over 150ms, but condition was never met.

 %ExWaiter.Waiter{
   attempt_num: 5,
   attempts: [
     %ExWaiter.Attempt{attempt_num: 1, delay: 10, fulfilled?: false, value: nil},
     %ExWaiter.Attempt{attempt_num: 2, delay: 20, fulfilled?: false, value: nil},
     %ExWaiter.Attempt{attempt_num: 3, delay: 30, fulfilled?: false, value: nil},
     %ExWaiter.Attempt{attempt_num: 4, delay: 40, fulfilled?: false, value: nil},
     %ExWaiter.Attempt{attempt_num: 5, delay: 50, fulfilled?: false, value: nil},
   ],
   attempts_left: 0,
   delay: #Function<...>,
   returning: #Function<...>,
   fulfilled?: false,
   checker_fn: #Function<...>,
   num_attempts: 5,
   total_delay: 150,
   value: nil
 }
```

This displays a `Waiter` struct, which includes a recording of everything
that happened during attempts.

The `await/2` function would return either `{:ok, %Click{}}` or
`{:error, %Waiter}`. It can be helpful to inspect this `Waiter`
struct for debugging and optics into timing. The anonymous function to
check if the condition has been met can take 0 or 1 arguments, with the
argument being the `%Waiter{}`.

### Additional Options

* `:delay` - Takes either an integer or a function that receives the
  `%Waiter{}` struct at that moment and returns a number of milliseconds to
  delay prior to performing the next attempt. The default is
  `fn waiter -> waiter.attempt_num * 10 end`.
* `:num_attempts` - The number of attempts before retries are exhausted. Takes
  either an integer or :infinite. (default: 5)
* `:returning` - Configures the return value when the condition is met. Takes
  a function that receives the `%Waiter{}` struct. The default is
  `fn waiter -> waiter.value end`.

## Warning

This library was recently released and the API has not yet fully
stabilized. Breaking changes may happen between minor versions prior to 1.0.

## Thanks

Thanks to my friends at [Enbala](https://www.enbala.com/), especially
[@itsgreggreg](https://github.com/itsgreggreg) and [@s3cur3](https://github.com/s3cur3), for providing helpful feedback to polish the API. 
