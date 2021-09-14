defmodule ExWaiter do
  @moduledoc """
  Helper for waiting on asynchronous conditions to be met.

  ## Installation

  Add the latest release to your `mix.exs` file:

  ```elixir
  defp deps do
    [
      {:ex_waiter, "~> 0.1.0"}
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
  exhausted retries, and a record of the history of each attempt.

  This simple package provides all that and more! Well, actually just that.

  ## A Walkthrough

  The package provides a single `await/2` function. This function requires a
  function that MUST return either `{:ok, value}` or `{:error, value}`. It can
  take additional options for setting the desired number of attempts, custom
  delay between attempts, and how to handle exhausted retries.

  As mentioned above, suppose it is necessary to check the database for the
  most recently persisted click.

  ```elixir
  {:ok, click, waiter} = ExWaiter.await(fn ->
    case Clicks.most_recent() do
      nil ->
        {:error, nil}

      %Click{} = click ->
        {:ok, click}
    end
  end)
  ```

  By default, this will check the database up to 5 times spaced out over 150ms.
  If, at some point, it is fulfilled, a tuple with `{:ok, %Click{}, %Waiter{}}`
  will be returned. If retries are exhausted, an exception will be raised that
  looks something like:

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
     delay_before_fn: #Function<>,
     exception_on_retries_exhausted?: true,
     fulfilled?: false,
     checker_fn: #Function<...>,
     num_attempts: 5,
     total_delay: 150,
     value: nil
   }
  ```

  This returns the aforementioned `Waiter` struct, which includes a recording of
  everything that happened during attempts. It can be helpful to inspect this
  `Waiter` struct (available as the third element in the `:ok` tuple returned in
  the first example) for debugging and optics into timing.

  ### Additional Options

  * `:delay_before_fn` - takes a function that receives the `%Waiter{}` struct at
    that moment and returns a number of milliseconds to delay prior to performing
    the next attempt. The default is `fn waiter -> waiter.attempt_num * 10 end`.
  * `:exception_on_retries_exhausted?` - a boolean dictating if an exception
    should be raised when retries have been exhausted. If `false`, a tuple with
    `{:error, value, %Waiter{}}` will be returned. (default: true)
  * `:num_attempts` - The number of attempts before retries are exhausted.
    (default: 5)
  """

  alias ExWaiter.Attempt
  alias ExWaiter.Waiter
  alias ExWaiter.Exceptions.InvalidResult
  alias ExWaiter.Exceptions.RetriesExhausted

  @doc """
  Periodically checks that a given condition has been met.

  Takes a function that checks whether the given condition has been met. It MUST return either `{:ok, value}` or `{:error, value}`. If the condition has been met, a tuple with `{:ok, value, %Waiter{}}` will be returned. If retries are exhausted prior to the condition being met, an exception will be raised.

  ## Options

  * `:delay_before_fn` - takes a function that receives the `%Waiter{}` struct at that moment and returns a number of milliseconds to delay prior to performing the next attempt. The default function is `fn waiter -> waiter.attempt_num * 10 end`.
  * `:exception_on_retries_exhausted?` - a boolean dictating if an exception should be raised when retries have been exhausted. If `false`, a tuple with `{:error, value, %Waiter{}}` will be returned. (default: true)
  * `:num_attempts` - The number of attempts before retries are exhausted. (default: 5)
  """

  @type await_options ::
          {:delay_before_fn, (Waiter.t() -> integer())}
          | {:exception_on_retries_exhausted?, boolean()}
          | {:num_attempts, integer()}
  @spec await((() -> {:ok, any()} | {:error, any()}), [await_options]) ::
          {:ok, any(), Waiter.t()} | {:error, any(), Waiter.t()}
  def await(checker_fn, opts \\ []) do
    num_attempts = Keyword.get(opts, :num_attempts, 5)

    %Waiter{
      checker_fn: checker_fn,
      delay_before_fn: Keyword.get(opts, :delay_before_fn, &delay_before_fn_default/1),
      exception_on_retries_exhausted?: Keyword.get(opts, :exception_on_retries_exhausted?, true),
      num_attempts: num_attempts,
      attempts_left: num_attempts
    }
    |> attempt()
  end

  defp attempt(%Waiter{attempts_left: 0} = waiter), do: handle_retries_exhausted(waiter)

  defp attempt(%Waiter{} = waiter) do
    waiter = init_attempt(waiter)

    delay_before = waiter.delay_before_fn.(waiter)
    Process.sleep(delay_before)

    case waiter.checker_fn.() do
      {:ok, value} ->
        waiter = record_attempt(waiter, true, value, delay_before)
        {:ok, value, waiter}

      {:error, value} ->
        waiter
        |> record_attempt(false, value, delay_before)
        |> attempt()

      result ->
        raise InvalidResult, result
    end
  end

  defp init_attempt(waiter) do
    %{waiter | attempt_num: waiter.attempt_num + 1, attempts_left: waiter.attempts_left - 1}
  end

  defp record_attempt(waiter, fulfilled?, value, delay_before) do
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

  defp handle_retries_exhausted(%Waiter{} = waiter) do
    if waiter.exception_on_retries_exhausted? do
      raise(RetriesExhausted, waiter)
    else
      {:error, waiter.value, waiter}
    end
  end
end
