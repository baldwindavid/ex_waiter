defmodule ExWaiter do
  @moduledoc """
  Helper for waiting on asynchronous conditions to be met.

  ## Installation

  Add the latest release to your `mix.exs` file:

  ```elixir
  defp deps do
    [
      {:ex_waiter, "~> 0.2.1"}
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
      %Click{} = click ->
        {:ok, click}

      value ->
        # This is a good place for a callback you might want to run each
        # time the condition is unmet (e.g. flushing jobs).
        {:error, value}

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
       %ExWaiter.Attempt{attempt_num: 1, delay_before: 10, fulfilled?: false, value: nil},
       %ExWaiter.Attempt{attempt_num: 2, delay_before: 20, fulfilled?: false, value: nil},
       %ExWaiter.Attempt{attempt_num: 3, delay_before: 30, fulfilled?: false, value: nil},
       %ExWaiter.Attempt{attempt_num: 4, delay_before: 40, fulfilled?: false, value: nil},
       %ExWaiter.Attempt{attempt_num: 5, delay_before: 50, fulfilled?: false, value: nil},
     ],
     attempts_left: 0,
     delay_before_fn: #Function<...>,
     fulfilled?: false,
     checker_fn: #Function<...>,
     num_attempts: 5,
     total_delay: 150,
     value: nil
   }
  ```

  This displays a `Waiter` struct, which includes a recording of everything
  that happened during attempts.

  The `await/2` function would return either `{:ok, %Click{}, %Waiter{}}` or
  `{:error, nil, %Waiter}`. It can be helpful to inspect this `Waiter`
  struct for debugging and optics into timing.

  ### Additional Options

  * `:delay_before_fn` - takes a function that receives the `%Waiter{}` struct at
    that moment and returns a number of milliseconds to delay prior to performing
    the next attempt. The default is `fn waiter -> waiter.attempt_num * 10 end`.
  * `:num_attempts` - The number of attempts before retries are exhausted.
    (default: 5)
  """

  alias ExWaiter.Attempt
  alias ExWaiter.Waiter
  alias ExWaiter.Exceptions.InvalidResult
  alias ExWaiter.Exceptions.RetriesExhausted

  @type await_options ::
          {:delay_before_fn, (Waiter.t() -> integer())} | {:num_attempts, integer()}
  @type checker_fn :: (() -> {:ok, any()} | {:error, any()} | :ok | :error | boolean())

  @doc """
  Periodically checks that a given condition has been met.

  Takes a function that checks whether the given condition has been met.
  Returning `{:ok, value}` or `{:error, value}` will ensure that you receive
  a return "value" from `await/2` and that the resulting `%Waiter{}` tracks
  changes to that value throughout attempts. However, if that "value" doesn't
  matter, one of `:ok`, `:error`, `true`, or `false` may be returned. If the
  condition has been met, a tuple with `{:ok, value, %Waiter{}}` will be
  returned. If retries are exhausted prior to the condition being met,
  `{:error, value, %Waiter{}}` will be returned.

  ## Options

  * `:delay_before_fn` - takes a function that receives the `%Waiter{}` struct
     at that moment and returns a number of milliseconds to delay prior to
     performing the next attempt. The default function is
     `fn waiter -> waiter.attempt_num * 10 end`.
  * `:num_attempts` - The number of attempts before retries are exhausted.
     (default: 5)

  ## Examples

  Returning a tagged tuple ensures the `Project` is returned from `await/2`.

  ```elixir
  {:ok, %Project{name: name}, %Waiter{}} = await(fn ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, project}
      value -> {:error, value}
    end
  end)
  ```

  If you don't care about the `Project` returned from the query, any of
  `:ok`, `:error`, `true`, or `false` may be returned.

  ```elixir
  {:ok, _will_be_nil, %Waiter{}} = await(fn ->
    case Projects.get(1) do
      %Project{} -> :ok # or true
      _ -> :error # or false
    end
  end)
  ```
  """

  @spec await(checker_fn, [await_options]) ::
          {:ok, any(), Waiter.t()} | {:error, any(), Waiter.t()}
  def await(checker_fn, opts \\ []) do
    num_attempts = Keyword.get(opts, :num_attempts, 5)

    %Waiter{
      checker_fn: checker_fn,
      delay_before_fn: Keyword.get(opts, :delay_before_fn, &delay_before_fn_default/1),
      num_attempts: num_attempts,
      attempts_left: num_attempts
    }
    |> attempt()
  end

  @doc """
  Periodically checks a given condition and raises an exception if it
  is never met.

  Supports the same options as `await/2`. However, if the condition has
  been met, only the "value" will be returned. If retries are exhausted
  prior to the condition being met, an exception will be raised.

  ## Examples

  Returning a tagged tuple ensures that the `Project` is returned
  from `await!/2`.

  ```elixir
  %Project{name: name} = await!(fn ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, project}
      value -> {:error, value}
    end
  end)
  ```

  If you only care about whether an exception is raised, any of
  `:ok`, `:error`, `true`, or `false` may be returned.

  ```elixir
  await!(fn ->
    case Projects.get(1) do
      %Project{} -> :ok # or true
      _ -> :error # or false
    end
  end)
  ```
  """
  @spec await!(checker_fn, [await_options]) :: any()
  def await!(checker_fn, opts \\ []) do
    case await(checker_fn, opts) do
      {:ok, value, _waiter} -> value
      {:error, _, waiter} -> raise(RetriesExhausted, waiter)
    end
  end

  defp attempt(%Waiter{attempts_left: 0} = waiter), do: {:error, waiter.value, waiter}

  defp attempt(%Waiter{} = waiter) do
    waiter = init_attempt(waiter)

    delay_before = waiter.delay_before_fn.(waiter)
    Process.sleep(delay_before)

    case waiter.checker_fn.() do
      {:ok, value} -> handle_successful_attempt(waiter, value, delay_before)
      :ok -> handle_successful_attempt(waiter, nil, delay_before)
      true -> handle_successful_attempt(waiter, nil, delay_before)
      {:error, value} -> handle_failed_attempt(waiter, value, delay_before)
      :error -> handle_failed_attempt(waiter, nil, delay_before)
      false -> handle_failed_attempt(waiter, nil, delay_before)
      result -> raise InvalidResult, result
    end
  end

  defp init_attempt(waiter) do
    %{waiter | attempt_num: waiter.attempt_num + 1, attempts_left: waiter.attempts_left - 1}
  end

  defp handle_successful_attempt(%Waiter{} = waiter, value, delay_before) do
    waiter = record_attempt(waiter, true, value, delay_before)
    {:ok, value, waiter}
  end

  defp handle_failed_attempt(%Waiter{} = waiter, value, delay_before) do
    waiter
    |> record_attempt(false, value, delay_before)
    |> attempt()
  end

  defp record_attempt(%Waiter{} = waiter, fulfilled?, value, delay_before) do
    attempts =
      [
        %Attempt{
          attempt_num: waiter.attempt_num,
          fulfilled?: fulfilled?,
          value: value,
          delay_before: delay_before
        }
        | Enum.reverse(waiter.attempts)
      ]
      |> Enum.reverse()

    %{
      waiter
      | attempts: attempts,
        fulfilled?: fulfilled?,
        value: value,
        total_delay: waiter.total_delay + delay_before
    }
  end

  defp delay_before_fn_default(%Waiter{} = waiter) do
    waiter.attempt_num * 10
  end
end
