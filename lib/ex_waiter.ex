defmodule ExWaiter do
  @moduledoc """
  Helper for waiting on asynchronous conditions to be met.

  ## Installation

  Add the latest release to your `mix.exs` file:

  ```elixir
  defp deps do
    [
      {:ex_waiter, "~> 0.6.0"}
    ]
  end
  ```

  Then run `mix deps.get` in your shell to fetch the dependencies.

  ## Why This Exists?

  In some scenarios there is no obvious way to ensure that asynchronous
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
  `{:error, nil}`. It can be helpful to inspect this `Waiter`
  struct for debugging and optics into timing. The anonymous function to
  check if the condition has been met can take 0 or 1 arguments, with the
  argument being the `%Waiter{}`.

  ### Additional Options

  * `:num_attempts` - The number of attempts before retries are exhausted. Takes
    either an integer or `:infinity`. (default: 5)
  * `:delay` - Takes either an integer or a function that receives the
    `%Waiter{}` struct at that moment and returns a number of milliseconds to
    delay prior to performing the next attempt. The default is
    `fn waiter -> waiter.attempt_num * 10 end`.
  * `:returning` - Configures the return value when the condition is met. Takes
    a function that receives the `%Waiter{}` struct. The default is
    `fn waiter -> waiter.value end`.
  * `:on_success` - Configures a callback when the condition is met. Takes
    a function that receives the `%Waiter{}` struct. Can be used for logging
    and inspection.
  * `:on_failure` - Configures a callback when retries are exhausted. Takes
    a function that receives the `%Waiter{}` struct. Can be used for logging
    and inspection.
  """

  alias ExWaiter.Attempt
  alias ExWaiter.Waiter
  alias ExWaiter.Exceptions.InvalidResult
  alias ExWaiter.Exceptions.RetriesExhausted

  @valid_options [:delay, :returning, :on_success, :on_failure, :num_attempts]

  @type await_options ::
          {:delay, Waiter.delay()}
          | {:num_attempts, Waiter.num_attempts()}
          | {:returning, Waiter.returning()}
          | {:on_success, Waiter.on_success()}
          | {:on_failure, Waiter.on_failure()}

  @doc """
  Periodically checks that a given condition has been met.

  Takes a function that checks whether the given condition has been met. This
  function can take 0 or 1 arguments, with the argument being the `%Waiter{}`.
  Returning `{:ok, value}` or `{:error, value}` will ensure that you receive
  a return "value" from `await/2` and that value changes are tracked throughout
  attempts. However, if that "value" doesn't matter, one of `:ok`, `:error`,
  `true`, or `false` may be returned. If the condition has been met, a tuple
  with `{:ok, value}` will be returned. If retries are exhausted prior to the
  condition being met, `{:error, value}` will be returned.

  ## Options

  * `:num_attempts` - The number of attempts before retries are exhausted. Takes
    either an integer or `:infinity`. (default: 5)
  * `:delay` - Takes either an integer or a function that receives the
    `%Waiter{}` struct at that moment and returns a number of milliseconds to
    delay prior to performing the next attempt. The default is
    `fn waiter -> waiter.attempt_num * 10 end`.
  * `:returning` - Configures the return value when the condition is met. Takes
    a function that receives the `%Waiter{}` struct. The default is
    `fn waiter -> waiter.value end`.
  * `:on_success` - Configures a callback when the condition is met. Takes
    a function that receives the `%Waiter{}` struct. Can be used for logging
    and inspection.
  * `:on_failure` - Configures a callback when retries are exhausted. Takes
    a function that receives the `%Waiter{}` struct. Can be used for logging
    and inspection.

  ## Examples

  Returning a tagged tuple ensures the `Project` is returned from `await/2`.

  ```elixir
  {:ok, %Project{name: name}} = await(fn ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, project}
      value -> {:error, value}
    end
  end)
  ```

  If you don't care about the `Project` returned from the query, any of
  `:ok`, `:error`, `true`, or `false` may be returned.

  ```elixir
  {:ok, _will_be_nil} = await(fn ->
    case Projects.get(1) do
      %Project{} -> :ok # or true
      _ -> :error # or false
    end
  end)
  ```
  """

  @spec await(Waiter.checker_fn(), [await_options]) ::
          {:ok, any()} | {:error, Waiter.t()}
  def await(checker_fn, opts \\ []) do
    case do_await(checker_fn, opts) do
      {:ok, waiter} -> {:ok, determine_returning(waiter)}
      {:error, waiter} -> {:error, determine_returning(waiter)}
    end
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
  @spec await!(Waiter.checker_fn(), [await_options]) :: any()
  def await!(checker_fn, opts \\ []) do
    case do_await(checker_fn, opts) do
      {:ok, waiter} -> determine_returning(waiter)
      {:error, waiter} -> raise(RetriesExhausted, waiter)
    end
  end

  defp do_await(checker_fn, opts) do
    Enum.each(opts, fn {key, _} ->
      unless key in @valid_options do
        valid_options = @valid_options |> Enum.join(", ")
        raise "#{key} is not a valid option - Valid Options: #{valid_options}"
      end
    end)

    num_attempts = Keyword.get(opts, :num_attempts, 5)

    unless is_integer(num_attempts) || num_attempts == :infinity do
      raise ":num_attempts must be either an integer (ms) or :infinity"
    end

    %Waiter{
      checker_fn: checker_fn,
      delay: Keyword.get(opts, :delay, &delay_default/1),
      num_attempts: Keyword.get(opts, :num_attempts, 5),
      returning: Keyword.get(opts, :returning, &returning_default/1),
      on_success: Keyword.get(opts, :on_success, & &1),
      on_failure: Keyword.get(opts, :on_failure, & &1)
    }
    |> attempt()
  end

  defp attempt(%Waiter{attempt_num: num, num_attempts: num} = waiter) do
    waiter.on_failure.(waiter)
    {:error, waiter}
  end

  defp attempt(%Waiter{} = waiter) do
    waiter = init_attempt(waiter)

    delay = determine_delay(waiter)
    Process.sleep(delay)

    case handle_checker_fn(waiter) do
      {:ok, value} -> handle_successful_attempt(waiter, value, delay)
      :ok -> handle_successful_attempt(waiter, nil, delay)
      true -> handle_successful_attempt(waiter, nil, delay)
      {:error, value} -> handle_failed_attempt(waiter, value, delay)
      :error -> handle_failed_attempt(waiter, nil, delay)
      false -> handle_failed_attempt(waiter, nil, delay)
      result -> raise InvalidResult, result
    end
  end

  defp init_attempt(%Waiter{} = waiter) do
    %{waiter | attempt_num: waiter.attempt_num + 1}
  end

  defp handle_successful_attempt(%Waiter{} = waiter, value, delay) do
    waiter = record_attempt(waiter, true, value, delay)
    waiter.on_success.(waiter)
    {:ok, waiter}
  end

  defp handle_failed_attempt(%Waiter{} = waiter, value, delay) do
    waiter
    |> record_attempt(false, value, delay)
    |> attempt()
  end

  defp record_attempt(%Waiter{} = waiter, fulfilled?, value, delay) do
    attempts =
      [
        %Attempt{
          attempt_num: waiter.attempt_num,
          fulfilled?: fulfilled?,
          value: value,
          delay: delay
        }
        | Enum.reverse(waiter.attempts)
      ]
      |> Enum.reverse()

    %{
      waiter
      | attempts: attempts,
        fulfilled?: fulfilled?,
        value: value,
        total_delay: waiter.total_delay + delay
    }
  end

  defp determine_delay(%Waiter{delay: ms}) when is_integer(ms), do: ms

  defp determine_delay(%Waiter{delay: delay_fn} = waiter)
       when is_function(delay_fn),
       do: delay_fn.(waiter)

  defp delay_default(%Waiter{} = waiter) do
    waiter.attempt_num * 10
  end

  defp determine_returning(%Waiter{returning: returning_fn} = waiter) do
    returning_fn.(waiter)
  end

  defp returning_default(%Waiter{value: value}), do: value

  defp handle_checker_fn(%Waiter{checker_fn: checker_fn} = waiter) do
    case :erlang.fun_info(checker_fn)[:arity] do
      1 -> checker_fn.(waiter)
      0 -> checker_fn.()
      _ -> raise "Checker function must have an arity of either 0 or 1"
    end
  end
end
