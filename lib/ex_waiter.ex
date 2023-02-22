defmodule ExWaiter do
  @moduledoc """
  Handy functions for polling and receiving.

  - Polling: `poll/1`, `poll!/1`, and `poll_once/1` periodically check that a
    given condition has been met.
  - Receiving: `receive_next/2` and `receive_next!/2` return the next message/s
    from the mailbox within a timeout.

  ## Installation

  Add the latest release to your `mix.exs` file:

  ```elixir
  defp deps do
    [
      {:ex_waiter, "~> 1.2.1"}
    ]
  end
  ```

  Then run `mix deps.get` in your shell to fetch the dependencies.
  """

  alias ExWaiter.Polling
  alias ExWaiter.Receiving

  @doc """
  Configures an `ExWaiter.Polling.Poller` struct to be passed into `poll/1`,
  `poll!/1`, or `poll_once/1` to keep track of polling status.

  ## Usage

  Takes a function that checks whether the given condition has been met. This
  function optionally takes 1 argument, which is the current `Poller` struct.
  Returning `{:ok, value}` or `{:error, value}` ensures that a "value" is set on
  the `Poller` struct that is returned after polling. If the value doesn't
  matter, any of `:ok`, `:error`, `true`, and `false` may be returned from the
  function instead.

  Create a poller and record the history of each attempt. By default, up to 5
  attempts will be made with a backoff delay totaling 100ms.

  ```elixir
  poller =
    ExWaiter.new_poller(
      fn ->
        case Projects.get(1) do
          %Project{} = project -> {:ok, project}
          _ -> {:error, :nope}
        end
      end,
      record_history: true
    )
  ```

  Then use `poll/1` (or `poll!/1`) to synchronously poll until the project is
  successfully found or retries are exhausted. For more complex asynchronous use
  cases, `poll_once/1` will make single attempts.

  ```elixir
  {:ok, poller} = ExWaiter.poll(poller)
  ```

  Below is an example of the contents of the poller struct after polling has
  successfully found the project after 5 attempts. The struct includes
  information about the number of attempts, the delay between each, total delay,
  and the eventual value.

  ```elixir
  %ExWaiter.Polling.Poller{
    attempt_num: 5,
    history: [
      %{value: :nope, next_delay: 10},
      %{value: :nope, next_delay: 20},
      %{value: :nope, next_delay: 30},
      %{value: :nope, next_delay: 40},
      %{value: %Project{}, next_delay: nil}
    ],
    next_delay: nil,
    total_delay: 100,
    value: %Project{}
  }
  ```

  ## Options

  * `:max_attempts` - The number of attempts before retries are exhausted. Takes
    an integer, `:infinity`, or a function that optionally receives the `Poller`
    struct just after the condition has been checked for configuring dynamic
    retries. The function must return `true` to retry or `false` if retries are
    exhausted. The default is `5`.
  * `:delay` - The delay before retries. Takes either an integer or a function
    that optionally receives the `Poller` struct just after the condition has
    been checked allowing for dynamically configured backoff. The default is `fn
    poller -> poller.attempt_num * 10 end`.
  * `:record_history` - Enabling the recording of attempt history will provide
    the tracked value and configured delay. The history is disabled by default
    to avoid growing too large.

  See `poll/1` for more in-depth usage examples.
  """
  @spec new_poller(Polling.Poller.Config.polling_fn(), Polling.options()) ::
          Polling.Poller.t()
  defdelegate new_poller(polling_fn, opts \\ []), to: Polling

  @doc """
  Periodically checks that a given condition has been met.

  In some scenarios there is no obvious way to ensure that asynchronous side
  effects have taken place without continuously checking for successful
  completion. For example, perhaps an assertion is needed on click data being
  asynchronously persisted to the database. It is not difficult to write a
  recursive function to handle this one-off, but there is a bit of ceremony
  involved. Additionally, perhaps it is desirable to configure the amount of
  delay prior to each check, the total number of attempts, and a record of the
  history of each attempt.

  ## Usage

  Takes an `ExWaiter.Polling.Poller` struct and checks the condition configured
  via `new_poller/2`. If the condition has been met, a tuple with `{:ok,
  %Poller{}}` will be returned. If retries are exhausted prior to the condition
  being met, `{:error, :retries_exhausted, %Poller{}}` will be returned. Retries
  will synchronously be attempted until either the condition has been met or max
  attempts reached. For more complex asynchronous use cases, `poll_once/1` will
  make single attempts; it is what this `poll/1` function uses under the hood.

  ## Examples

  By default, this query will be attempted up to 5 times in 100ms. Assuming the
  condition was successful on the 5th try, the returned `Poller` struct would
  include the following polling metadata:

  ```elixir
  poller =
    ExWaiter.new_poller(fn ->
      case Projects.get(1) do
        %Project{} = project -> {:ok, project}
        _ -> :error
      end
    end)

  assert {:ok, poller} = ExWaiter.poll(poller)
  assert %{
    attempt_num: 5,
    next_delay: nil,
    total_delay: 100,
    value: %Project{}
  } = poller
  ```

  If we try 5 times without receiving the project, an error tuple will be
  returned.

  ```elixir
  poller =
    ExWaiter.new_poller(fn ->
      case Projects.get(1) do
        %Project{} = project -> {:ok, project}
        _ -> :error
      end
    end)

  assert {:error, :retries_exhausted, poller} = ExWaiter.poll(poller)
  assert %{
    attempt_num: 5,
    next_delay: nil,
    total_delay: 100,
    value: nil
  } = poller
  ```

  The number of attempts and delay between each can be configured. Below we want
  to make up to 10 attempts with 20ms of delay between each. Both `max_attempts`
  and `delay` can be dynamically configured (more examples below). The
  `max_attempts` can also be set to `:infinity`.

  ```elixir
  poller =
    ExWaiter.new_poller(
      fn ->
        case Projects.get(1) do
          %Project{} = project -> {:ok, project}
          _ -> :error
        end
      end,
      max_attempts: 10,
      delay: 20
    )

  assert {:ok, poller} = ExWaiter.poll(poller)
  ```

  Enabling the recording of history will provide the tracked value and
  configured delay for each attempt. History is disabled by default to avoid
  growing too large.

  ```elixir
  poller =
    ExWaiter.new_poller(
      fn ->
        case Projects.get(1) do
          %Project{} = project -> {:ok, project}
          _ -> {:error, :nope}
        end
      end,
      record_history: true
    )

  assert {:ok, poller} = ExWaiter.poll(poller)
  assert %{
    attempt_num: 5,
    history: [
      %{value: :nope, next_delay: 10},
      %{value: :nope, next_delay: 20},
      %{value: :nope, next_delay: 30},
      %{value: :nope, next_delay: 40},
      %{value: %Project{}, next_delay: nil}
    ],
    next_delay: nil,
    total_delay: 100,
    value: %Project{}
  } = poller
  ```

  The delay can be configured via a function that receives the `Poller` struct
  immediately after an attempt has been made to configure the delay before the
  next attempt. Enabling the recording of history allows us to see what was the
  next configured delay after each attempt.

  ```elixir
  poller =
    ExWaiter.new_poller(
      fn ->
        case Projects.get(1) do
          %Project{} -> :ok
          _ -> :error
        end
      end,
      record_history: true,
      delay: fn poller -> poller.attempt_num * 2 end
    )

  assert {:ok, poller} = ExWaiter.poll(poller)
  assert %{
    history: [
      %{next_delay: 2},
      %{next_delay: 4},
      %{next_delay: 6},
      %{next_delay: 8},
      %{next_delay: nil}
    ],
    total_delay: 20,
  } = poller
  ```

  Max attempts can also be configured dynamically. Suppose we wanted to
  continuously retry on Monday up to 100 attempts, but stop retrying any other
  day of the week. The function should return `true` to retry or `false` to stop
  retrying. Let's assume it's Monday and the project was returned after 5
  attempts.

  ```elixir
  poller =
    ExWaiter.new_poller(
      fn _poller ->
        case Projects.get(1) do
          %Project{} -> :ok
          _ -> :error
        end
      end,
      max_attempts: fn poller ->
        is_monday? = DateTime.utc_now() |> DateTime.to_date() |> Date.day_of_week() == 1
        is_monday? and poller.attempt_num < 100
      end
    )

  assert {:ok, poller} = ExWaiter.poll(poller)
  assert %{
    attempt_num: 5
  } = poller
  ```

  The poller function optionally receives the `Poller` struct. This can be used
  for customization and logging.

  ```elixir
  poller = ExWaiter.new_poller(fn poller ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, {project, poller.attempt_num}}
      _ ->
        Logger.info(inspect(poller))
        :error
    end
  end)

  assert {:ok, {%Project{}, 5}} = ExWaiter.poll(poller)
  ```
  """
  @spec poll(Polling.Poller.t()) :: Polling.poll_result()
  def poll(poller) do
    case Polling.poll_once(poller) do
      {:error, :attempt_failed, poller} ->
        Process.sleep(poller.next_delay)
        poll(poller)

      result ->
        result
    end
  end

  @doc """
  Periodically checks that a given condition has been met. Raises an exception
  upon exhausted retries.

  Supports the same options as `poll/1`. However, if the condition has been met,
  only the `Poller` struct will be returned (i.e. not in an :ok tuple). If
  retries are exhausted prior to the condition being met, an exception will be
  raised.
  """
  @spec poll!(Polling.Poller.t()) ::
          Polling.Poller.t() | {:error, :attempt_failed, Polling.Poller.t()}
  def poll!(poller) do
    case poll(poller) do
      {:ok, poller} -> poller
      {:error, :retries_exhausted, poller} -> raise(Polling.RetriesExhausted, poller)
    end
  end

  @doc """
  Checks one time that a given condition has been met.

  ## Usage

  Takes an `ExWaiter.Polling.Poller` struct and checks the condition configured
  via `new_poller/2`. If the condition has been met, a tuple with `{:ok,
  %Poller{}}` will be returned. If the condition is unmet and retries have
  exhausted, `{:error, :retries_exhausted, %Poller{}}` will be returned. If
  additional retries are available, `{:error, :attempt_failed, %Poller{}}` will
  be returned. Subsequent retries via `poll_once/1` should supply the returned
  `Poller` struct from the previous failed attempt as it will maintain the
  current attempt number, next and total delay, and value. The `next_delay`
  should be used to schedule the attempt at the desired later time (e.g. via
  `Process.send_after`).

  See `poll/1` for additional configuration examples as it uses this function
  under the hood running it recursively until either success or exhausted
  retries.

  ## Examples

  Below is a contrived example of scheduling retries. In practice, you might use
  a GenServer with `handle_info` and send to self or a different process that
  notifies the caller when finished.

  ```elixir
  poller =
    ExWaiter.new_poller(fn ->
      case Projects.get(1) do
        %Project{} = project -> {:ok, project}
        _ -> :error
      end
    end)
  ```

  Suppose the first attempts fails...

  ```elixir
  assert {:error, :attempt_failed, poller} = ExWaiter.poll_once(poller)
  ```

  The returned `Poller` struct includes the default delay for the first retry of
  10 milliseconds. This can be used to schedule a later retry.

  ```elixir
  assert poller.next_delay == 10
  Process.send_after(self(), {:retry, poller}, poller.next_delay)
  ```

  Using the `receive_next!/2` function built into this package we receive the
  `{:retry, poller}` message sent via `Process.send_after`.

  ```elixir
  assert {:retry, poller} = ExWaiter.receive_next!()
  ```

  We try another attempt that fails, but there are still retries available.

  ```elixir
  assert {:error, :attempt_failed, poller} = ExWaiter.poll_once(poller)
  ```

  The default delay for a second retry is 20 milliseconds and we use that to
  schedule another retry.

  ```elixir
  assert poller.next_delay == 20
  Process.send_after(self(), {:retry, poller}, poller.next_delay)
  ```

  We again receive our scheduled message and kickoff another poll attempt. This
  time our project is there and we can get it on the returned `Poller` struct in
  the `value` attribute.

  ```elixir
  assert {:retry, poller} = ExWaiter.receive_next!()
  assert {:ok, poller} = ExWaiter.poll_once(poller)
  assert %{
    attempt_num: 3,
    next_delay: nil,
    total_delay: 30,
    value: %Project{}
  } = poller
  ```
  """

  @spec poll_once(Polling.Poller.t()) :: Polling.poll_result()
  defdelegate poll_once(poller), to: Polling

  @doc """
  Returns the next message/s from the mailbox within a timeout.

  Especially in testing scenarios, it can be useful to be able to assert
  that a number of messages are received in a mailbox in a specific order
  and that all of those messages are received within a timeout. It is not
  difficult to use `receive` to grab the messages, but there is a bit of
  ceremony/verbosity involved especially if requiring that all messages
  are received in a specific total amount of time.

  ## Usage

  By default, the next single message in the mailbox will be returned if it
  appears within 100ms. The number of messages to return and timeout are
  configurable. If the message/s are received within the timeout window,
  `{:ok, message}` will be returned for a single message or
  `{:ok, [messages]}` for multiple. If the configured timeout is reached
  prior to returning a single requested message, `:error` will be returned.
  If multiple messages were requested, `{:error, [messages]}` will be
  returned containing any messages that _were_ received.

  ## Options

  * `:timeout` - The time to wait for the number of messages requested from
    the mailbox. Takes either an integer (ms) or `:infinity`. (default: 100)

  ## Examples

  By default, the next message in the mailbox is returned if it appears within
  100ms.

  ```elixir
  send(self(), :hello)

  assert {:ok, :hello} = ExWaiter.receive_next()
  ```

  Multiple messages may be returned.

  ```elixir
  send(self(), :hello)
  send(self(), :hi)
  send(self(), :yo)

  assert {:ok, [:hello, :hi]} = ExWaiter.receive_next(2)
  ```

  A timeout (in ms) can be set. If the timeout occurs prior to
  receiving all requested messages, the messages that _were_
  received will be returned in the error tuple.

  ```elixir
  send(self(), :hello)
  send(self(), :hi)
  Process.send_after(self(), :yo, 80)

  assert {:error, [:hello, :hi]} = ExWaiter.receive_next(3, timeout: 50)
  ```
  """

  @spec receive_next(pos_integer(), Receiving.Receiver.options()) ::
          {:ok, any()} | {:error, any()}
  def receive_next(num_messages \\ 1, opts \\ []) do
    case Receiving.receive_next(num_messages, opts) do
      {:ok, receiver} ->
        if receiver.num_messages == 1 do
          {:ok, List.first(receiver.messages)}
        else
          {:ok, receiver.messages}
        end

      {:error, receiver} ->
        if receiver.num_messages == 1 do
          :error
        else
          {:error, receiver.messages}
        end
    end
  end

  @doc """
  Returns the next message/s from the mailbox within a timeout. Raises an
  exception upon timeout.

  Supports the same options as `receive_next/2`. However, if the mailbox has the
  right number of messages, only the message/s will be returned (i.e. not in an
  :ok tuple). If the messages are not received prior to the timeout, an
  exception will be raised.
  """
  @spec receive_next!(pos_integer(), Receiving.Receiver.options()) :: any()
  def receive_next!(num_messages \\ 1, opts \\ []) do
    case Receiving.receive_next(num_messages, opts) do
      {:ok, receiver} ->
        if receiver.num_messages == 1 do
          List.first(receiver.messages)
        else
          receiver.messages
        end

      {:error, receiver} ->
        raise(Receiving.Timeout, receiver)
    end
  end
end
