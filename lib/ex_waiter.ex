defmodule ExWaiter do
  @moduledoc """
  Handy functions for polling and receiving.

  - Polling: `poll/2` and `poll!/2` periodically check that a given
    condition has been met.
  - Receiving: `receive/2` and `receive!/2` return the next message/s
    from the mailbox within a timeout.

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
  """

  alias ExWaiter.Polling
  alias ExWaiter.Receiving

  @type poll_options ::
          {:delay, Polling.Poller.delay()}
          | {:num_attempts, Polling.Poller.num_attempts()}
          | {:on_complete, Polling.Poller.on_complete()}

  @doc """
  Periodically checks that a given condition has been met.

  In some scenarios there is no obvious way to ensure that asynchronous
  side effects have taken place without continuously checking for successful
  completion. For example, perhaps an assertion is needed on click data being
  asynchronously persisted to the database. It is not difficult to write a
  recursive function to handle this one-off, but there is a bit of ceremony
  involved. Additionally, perhaps it is desirable to configure the amount of
  delay prior to each check, the total number of attempts, and a record of
  the history of each attempt.

  ## Usage

  Takes a function that checks whether the given condition has been met. This
  function can take 0 or 1 arguments, with the argument being the `%Poller{}`.
  Returning `{:ok, value}` or `{:error, value}` will ensure that you receive
  a return "value" from `poll/2` and that value changes are tracked throughout
  attempts. If the value doesn't matter, `:ok` and `:error` may be returned
  from the function instead. If the condition has been met, a tuple with
  `{:ok, value}` (or `:ok`) will be returned. If retries are exhausted prior
  to the condition being met, `{:error, value}` (or `:error`) will be returned.

  ## Options

  * `:num_attempts` - The number of attempts before retries are exhausted. Takes
    either an integer or `:infinity`. (default: 5)
  * `:delay` - Takes either an integer or a function that receives the
    `%Poller{}` struct at that moment and returns a number of milliseconds to
    delay prior to performing the next attempt. The default is
    `fn poller -> poller.attempt_num * 10 end`.
  * `:on_complete` - Configures a callback upon the condition being met or retries
    being exhausted. Takes a function that receives the `%Poller{}` struct. Can be
    used for logging and inspection.

  ## Examples

  By default, this will attempt this query up to 5 times in 100ms.

  ```elixir
  assert {:ok, %Project{}} = ExWaiter.poll(fn ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, project}
      _ -> :error
    end
  end)
  ```

  The number of attempts and delay between each can be configured.

  ```elixir
  assert {:ok, %Project{}} = ExWaiter.poll(fn ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, project}
      _ -> :error
    end,
    num_attempts: 10,
    delay: 20
  end)
  ```

  A callback upon the condition being met or retries being
  exhausted can be configured. This callback receives the
  %Poller{} for inspection.

  ```elixir
  assert {:ok, %Project{}} = ExWaiter.poll(fn ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, project}
      _ -> :error
    end,
    on_complete: fn poller ->
      assert %{
        attempt_num: 5,
        num_attempts: 5,
        attempts: [
          %{value: :error, delay: 10},
          %{value: :error, delay: 20},
          %{value: :error, delay: 30},
          %{value: :error, delay: 40},
          %{value: {:ok, %Project{}}, delay: 50}
        ],
        total_delay: 100,
        value: {:ok, %Project{}}
      }
    end
  end)
  ```

  The poller function can optionally receive an argument, which will be
  the `Poller` struct at that moment. This can be used for customization
  and logging.

  ```elixir
  assert {:ok, {%Project{}, 5}} = ExWaiter.poll(fn poller ->
    case Projects.get(1) do
      %Project{} = project -> {:ok, {project, poller.attempt_num}}
      _ -> :error
    end
  end)
  ```
  """

  @spec poll(Polling.Poller.polling_fn(), [poll_options]) ::
          :ok | {:ok, any()} | :error | {:error, any()}
  def poll(polling_fn, opts \\ []) do
    case Polling.poll(polling_fn, opts) do
      {_, poller} -> poller.value
    end
  end

  @doc """
  Periodically checks that a given condition has been met. Raises an
  exception upon exhausted retries.

  Supports the same options as `poll/2`. However, if the condition has
  been met, only the "value" will be returned. If retries are exhausted
  prior to the condition being met, an exception will be raised.
  """
  @spec poll!(Waiter.polling_fn(), [poll_options]) :: any()
  def poll!(polling_fn, opts \\ []) do
    case Polling.poll(polling_fn, opts) do
      {:ok, poller} ->
        case poller.value do
          :ok -> :ok
          {:ok, value} -> value
        end

      {:error, poller} ->
        raise(Polling.RetriesExhausted, poller)
    end
  end

  @type receive_options ::
          {:timeout, timeout()}
          | {:filter, Receiving.Receiver.filter_fn()}
          | {:on_complete, Receiving.Receiver.on_complete()}

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
  * `:filter` - Configures which messages to return. This can be useful if
    a mailbox in testing is receiving a lot of extra messages that you don't
    care about. Takes a function that receives a new message and must return
    a boolean (`true` for a match). The default is `fn _message -> true end`.
    (i.e. match all messages). Please note that any rejected messages will
    be captured and tracked alongside the matched messages.
  * `:on_complete` - Configures a callback upon receiving all messages or
    timeout. Takes a function that receives the `%Receiver{}` struct. Can be
    used for logging and inspection.

  ## Examples

  By default, the next message in the mailbox is returned if it appears within
  100ms.

  ```elixir
  send(self(), :hello)

  assert {:ok, :hello} = ExWaiter.receive()
  ```

  Multiple messages may be returned.

  ```elixir
  send(self(), :hello)
  send(self(), :hi)
  send(self(), :yo)

  assert {:ok, [:hello, :hi]} = ExWaiter.receive(2)
  ```

  A timeout (in ms) can be set. If the timeout occurs prior to
  receiving all requested messages, the messages that _were_
  received will be returned in the error tuple.

  ```elixir
  send(self(), :hello)
  send(self(), :hi)
  Process.send_after(self(), :yo, 80)

  assert {:error, [:hello, :hi]} = ExWaiter.receive(3, timeout: 50)
  ```

  Messages can be filtered to ignore noise in the mailbox.

  ```elixir
  send(self(), {:greeting, :hello})
  send(self(), {:age, 25})
  send(self(), {:greeting, :hi})

  assert {:ok, [{:greeting, :hello}, {:greeting, :hi}]} =
            ExWaiter.receive(2, filter: &match?({:greeting, _}, &1))
  ```

  A callback upon receiving all message or timeout can be
  configured. This callback receives the %Receiver{} for
  inspection.

  ```elixir
  send(self(), :hello)
  Process.send_after(self(), :hi, 90)

  {:ok, [:hello, :hi]} =
    ExWaiter.receive(2,
      on_complete: fn receiver ->
        assert %ExWaiter.Receiving.Receiver{
                  message_num: 2,
                  all_messages: [:hello, :hi],
                  filtered_messages: [:hello, :hi],
                  rejected_messages: [],
                  num_messages: 2,
                  remaining_timeout: 10,
                  timeout: 100
                } = receiver
      end
    )
  ```
  """

  @spec receive(pos_integer(), [receive_options]) ::
          {:ok, any()} | {:ok, [any()]} | {:error, any()} | {:error, [any()]}
  def receive(num_messages \\ 1, opts \\ []) do
    case Receiving.receive(num_messages, opts) do
      {:ok, receiver} ->
        if receiver.num_messages == 1 do
          {:ok, List.first(receiver.filtered_messages)}
        else
          {:ok, receiver.filtered_messages}
        end

      {:error, receiver} ->
        if receiver.num_messages == 1 do
          :error
        else
          {:error, receiver.filtered_messages}
        end
    end
  end

  @doc """
  Returns the next message/s from the mailbox within a timeout. Raises an
  exception upon timeout.

  Supports the same options as `receive/1`. However, if the mailbox has the
  right number of messages, only the message/s will be returned. If the
  messages are not received prior to the timeout, an exception will be raised.
  """
  @spec receive!(pos_integer(), [receive_options]) :: any()
  def receive!(num_messages \\ 1, opts \\ []) do
    case Receiving.receive(num_messages, opts) do
      {:ok, receiver} ->
        if receiver.num_messages == 1 do
          List.first(receiver.filtered_messages)
        else
          receiver.filtered_messages
        end

      {:error, receiver} ->
        raise(Receiving.Timeout, receiver)
    end
  end
end
