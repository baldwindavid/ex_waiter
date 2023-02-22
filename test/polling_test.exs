defmodule ExWaiter.PollingTest do
  use ExUnit.Case

  alias ExWaiter.Polling.InvalidResult
  alias ExWaiter.Polling.RetriesExhausted

  # We want to simulate a series of queries and stub out the expected
  # values upon each successive attempt. This store takes an ordered list
  # of expected return values and a starting index of 0. Every time it is
  # queried, it grabs the value at the current index and increments the index.
  defmodule OrderedStore do
    def new(ordered_attempts, starting_index \\ 0) do
      {:ok, store} = Agent.start_link(fn -> {ordered_attempts, starting_index} end)
      store
    end

    def current_value(store) do
      value =
        Agent.get(store, fn {attempts, current_index} -> Enum.at(attempts, current_index) end)

      increment_index(store)
      value
    end

    defp increment_index(store) do
      Agent.update(store, fn {attempts, current_index} -> {attempts, current_index + 1} end)
    end
  end

  describe "default behavior" do
    test "a poller that has not been polled starts with defaults" do
      poller = ExWaiter.new_poller(fn -> true end)

      assert %{
               attempt_num: 0,
               history: nil,
               total_delay: 0,
               next_delay: nil,
               value: nil,
               status: nil
             } = poller
    end

    test "history will be initially set to an empty list if history is enabled" do
      poller =
        ExWaiter.new_poller(
          fn -> true end,
          record_history: true
        )

      assert %{history: []} = poller
    end

    test "retries up to 5 times and returns the value by default upon success" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil -> {:error, nil}
            value -> {:ok, value}
          end
        end)

      assert {:ok, %{value: "Got it!"}} = ExWaiter.poll(poller)
    end

    test "returns the poller struct" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> {:error, nil}
              value -> {:ok, value}
            end
          end,
          record_history: true
        )

      assert {:ok,
              %{
                attempt_num: 5,
                history: [
                  %{value: nil, next_delay: 10},
                  %{value: nil, next_delay: 20},
                  %{value: nil, next_delay: 30},
                  %{value: nil, next_delay: 40},
                  %{value: "Got it!", next_delay: nil}
                ],
                total_delay: 100,
                next_delay: nil,
                value: "Got it!"
              }} = ExWaiter.poll(poller)
    end

    test "doesn't make any more attempts than necessary" do
      attempts = [nil, "Got it!", "third", "fourth", "fifth"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end)

      assert {:ok,
              %{
                attempt_num: 2
              }} = ExWaiter.poll(poller)
    end

    test "returns an error when retries are exhausted" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end)

      assert {:error, :retries_exhausted,
              %{
                attempt_num: 5
              }} = ExWaiter.poll(poller)
    end

    test "raises an exception with an invalid option" do
      assert_raise(
        RuntimeError,
        "hello is not a valid option",
        fn ->
          ExWaiter.new_poller(
            fn -> "doesn't matter" end,
            hello: :world
          )
        end
      )
    end
  end

  describe "delay configuration" do
    test "waits increasing milliseconds before each successive retry by default" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          record_history: true
        )

      assert {:error, :retries_exhausted,
              %{
                history: [
                  %{next_delay: 10},
                  %{next_delay: 20},
                  %{next_delay: 30},
                  %{next_delay: 40},
                  %{next_delay: nil}
                ],
                total_delay: 100
              }} = ExWaiter.poll(poller)
    end

    test "can take a delay configuration function" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          record_history: true,
          delay: fn -> 2 * 2 end
        )

      assert {:error, :retries_exhausted,
              %{
                history: [
                  %{next_delay: 4},
                  %{next_delay: 4},
                  %{next_delay: 4},
                  %{next_delay: 4},
                  %{next_delay: nil}
                ],
                total_delay: 16
              }} = ExWaiter.poll(poller)
    end

    test "can optionally receive the poller as an argument to the delay function" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          record_history: true,
          delay: fn poller -> poller.attempt_num * 2 end
        )

      assert {:error, :retries_exhausted,
              %{
                history: [
                  %{next_delay: 2},
                  %{next_delay: 4},
                  %{next_delay: 6},
                  %{next_delay: 8},
                  %{next_delay: nil}
                ],
                total_delay: 20
              }} = ExWaiter.poll(poller)
    end

    test "can take an integer for delay after attempt" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          delay: 1,
          record_history: true
        )

      assert {:error, :retries_exhausted,
              %{
                history: [
                  %{next_delay: 1},
                  %{next_delay: 1},
                  %{next_delay: 1},
                  %{next_delay: 1},
                  %{next_delay: nil}
                ],
                total_delay: 4
              }} = ExWaiter.poll(poller)
    end

    test "raises an exception with an invalid delay configuration" do
      assert_raise(
        RuntimeError,
        ":delay must be either an integer or a function with an arity of 0 or 1 (can take the Poller struct)",
        fn ->
          ExWaiter.new_poller(fn -> "doesn't matter" end, delay: "doesn't matter")
        end
      )
    end
  end

  describe "max attempts configuration" do
    test "can be configured for less attempts" do
      attempts = [nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          max_attempts: 2
        )

      assert {:error, :retries_exhausted,
              %{
                attempt_num: 2
              }} = ExWaiter.poll(poller)
    end

    test "can be configured for infinite attempts" do
      attempts = [nil, nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          max_attempts: :infinity
        )

      assert {:ok,
              %{
                attempt_num: 6
              }} = ExWaiter.poll(poller)
    end

    test "can take a max attempts configuration function" do
      attempts = [nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              _ -> :ok
            end
          end,
          max_attempts: fn -> false end
        )

      assert {:error, :retries_exhausted,
              %{
                attempt_num: 1
              }} = ExWaiter.poll(poller)
    end

    test "can optionally receive the poller as an argument to the max attempts function" do
      attempts = [3, 2, 9, 7, 10, 4, 12]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              4 -> {:ok, 4}
              value -> {:error, value}
            end
          end,
          max_attempts: fn poller -> poller.value < 10 end,
          record_history: true
        )

      assert {:error, :retries_exhausted,
              %{
                attempt_num: 5,
                value: 10
              }} = ExWaiter.poll(poller)
    end

    test "raises an exception with an invalid number of attempts" do
      assert_raise(
        RuntimeError,
        ":max_attempts must be either an integer (ms), :infinity, or a function with an arity of 0 or 1 (can take the Poller struct)",
        fn ->
          ExWaiter.new_poller(
            fn -> "doesn't matter" end,
            max_attempts: :invalid_stuff
          )
        end
      )
    end
  end

  describe "polling function configuration" do
    test "supports :ok and :error return values, but with no value tracking" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end)

      assert {:ok, %{value: nil}} = ExWaiter.poll(poller)
    end

    test "can optionally take the Poller struct as an argument" do
      attempts = [nil, "first", "second", "third"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn poller ->
            case OrderedStore.current_value(store) do
              nil ->
                :error

              value ->
                if poller.value == "second" do
                  {:ok, value}
                else
                  {:error, value}
                end
            end
          end,
          record_history: true
        )

      assert {:ok,
              %{
                attempt_num: 4,
                history: [
                  %{value: nil},
                  %{value: "first"},
                  %{value: "second"},
                  %{value: "third"}
                ],
                value: "third"
              }} = ExWaiter.poll(poller)
    end

    test "raises an exception with an invalid polling function" do
      assert_raise(
        RuntimeError,
        "The polling function must have an arity of 0 or 1 (can take the Poller struct)",
        fn ->
          ExWaiter.new_poller("doesn't matter")
        end
      )
    end

    test "raises an exception with an invalid result" do
      Enum.each(["yep", "nope", nil], fn value ->
        assert_raise(InvalidResult, fn ->
          ExWaiter.new_poller(fn -> value end)
          |> ExWaiter.poll()
        end)
      end)
    end
  end

  describe "attempting to poll an already completed Poller" do
    test "returns the successful completion result without polling" do
      attempts = [nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> {:error, nil}
              value -> {:ok, value}
            end
          end,
          max_attempts: 2
        )

      assert {:ok,
              %{
                attempt_num: 2,
                value: "Got it!",
                status: :ok
              } = poller} = result = ExWaiter.poll(poller)

      assert ExWaiter.poll(poller) == result
    end

    test "returns the exhausted retries result without polling" do
      attempts = [nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> {:error, nil}
              value -> {:ok, value}
            end
          end,
          max_attempts: 2
        )

      assert {:error, :retries_exhausted,
              %{
                attempt_num: 2,
                value: nil,
                status: {:error, :retries_exhausted}
              } = poller} = result = ExWaiter.poll(poller)

      assert ExWaiter.poll(poller) == result
    end
  end

  describe "polling with poll!/1" do
    test "waits for a result and returns the value" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil ->
              :error

            value ->
              {:ok, value}
          end
        end)

      assert %{value: "Got it!"} = ExWaiter.poll!(poller)
    end

    test "throws an exception when retries are exhausted" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert_raise(RetriesExhausted, fn ->
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end)
        |> ExWaiter.poll!()
      end)
    end
  end

  describe "polling with manual retries via poll_once/1" do
    defmodule RetryServer do
      use GenServer

      def init(_) do
        {:ok, :ok}
      end

      def handle_call({:start_polling, poller}, {sender, _}, state) do
        send(self(), {:poll, sender, poller})
        {:reply, :ok, state}
      end

      def handle_info({:poll, sender, poller}, state) do
        ExWaiter.poll_once(poller)
        |> case do
          {:error, :attempt_failed, poller} ->
            assert poller.next_delay == poller.attempt_num * 10
            Process.send_after(self(), {:poll, sender, poller}, poller.next_delay)

          result ->
            send(sender, result)
        end

        {:noreply, state}
      end
    end

    test "supports manual retries" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              value -> {:ok, value}
            end
          end,
          record_history: true
        )

      assert {:error, :attempt_failed, %{next_delay: 10, total_delay: 0} = poller} =
               ExWaiter.poll_once(poller)

      Process.sleep(poller.next_delay)

      assert {:error, :attempt_failed, %{next_delay: 20, total_delay: 10} = poller} =
               ExWaiter.poll_once(poller)

      Process.sleep(poller.next_delay)

      assert {:error, :attempt_failed, %{next_delay: 30, total_delay: 30} = poller} =
               ExWaiter.poll_once(poller)

      Process.sleep(poller.next_delay)

      assert {:error, :attempt_failed, %{next_delay: 40, total_delay: 60} = poller} =
               ExWaiter.poll_once(poller)

      Process.sleep(poller.next_delay)

      assert {:ok,
              %{
                attempt_num: 5,
                history: [
                  %{value: nil, next_delay: 10},
                  %{value: nil, next_delay: 20},
                  %{value: nil, next_delay: 30},
                  %{value: nil, next_delay: 40},
                  %{value: "Got it!", next_delay: nil}
                ],
                total_delay: 100,
                next_delay: nil,
                value: "Got it!"
              }} = ExWaiter.poll_once(poller)
    end

    test "reports exhausted retries" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            value -> {:ok, value}
          end
        end)

      assert {:error, :attempt_failed, %{attempt_num: 1} = poller} = ExWaiter.poll_once(poller)
      assert {:error, :attempt_failed, %{attempt_num: 2} = poller} = ExWaiter.poll_once(poller)
      assert {:error, :attempt_failed, %{attempt_num: 3} = poller} = ExWaiter.poll_once(poller)
      assert {:error, :attempt_failed, %{attempt_num: 4} = poller} = ExWaiter.poll_once(poller)

      assert {:error, :retries_exhausted,
              %{
                attempt_num: 5
              }} = ExWaiter.poll_once(poller)
    end

    test "can be setup to poll after messages received to self" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              value -> {:ok, value}
            end
          end,
          record_history: true
        )

      assert {:error, :attempt_failed, poller} = ExWaiter.poll_once(poller)
      Process.send_after(self(), {:retry, poller}, poller.next_delay)
      {:retry, %{next_delay: 10, total_delay: 0} = poller} = ExWaiter.receive_next!()

      assert {:error, :attempt_failed, poller} = ExWaiter.poll_once(poller)
      Process.send_after(self(), {:retry, poller}, poller.next_delay)
      {:retry, %{next_delay: 20, total_delay: 10} = poller} = ExWaiter.receive_next!()

      assert {:error, :attempt_failed, poller} = ExWaiter.poll_once(poller)
      Process.send_after(self(), {:retry, poller}, poller.next_delay)
      {:retry, %{next_delay: 30, total_delay: 30} = poller} = ExWaiter.receive_next!()

      assert {:error, :attempt_failed, poller} = ExWaiter.poll_once(poller)
      Process.send_after(self(), {:retry, poller}, poller.next_delay)
      {:retry, %{next_delay: 40, total_delay: 60} = poller} = ExWaiter.receive_next!()

      assert {:ok,
              %{
                attempt_num: 5,
                history: [
                  %{value: nil, next_delay: 10},
                  %{value: nil, next_delay: 20},
                  %{value: nil, next_delay: 30},
                  %{value: nil, next_delay: 40},
                  %{value: "Got it!", next_delay: nil}
                ],
                total_delay: 100,
                next_delay: nil,
                value: "Got it!"
              }} = ExWaiter.poll_once(poller)
    end

    test "can be setup to poll via a separate process" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      poller =
        ExWaiter.new_poller(
          fn ->
            case OrderedStore.current_value(store) do
              nil -> :error
              value -> {:ok, value}
            end
          end,
          record_history: true
        )

      {:ok, retry_server} = GenServer.start_link(RetryServer, [])
      :ok = GenServer.call(retry_server, {:start_polling, poller})

      assert {:ok,
              %{
                attempt_num: 5,
                history: [
                  %{value: nil, next_delay: 10},
                  %{value: nil, next_delay: 20},
                  %{value: nil, next_delay: 30},
                  %{value: nil, next_delay: 40},
                  %{value: "Got it!", next_delay: nil}
                ],
                total_delay: 100,
                next_delay: nil,
                value: "Got it!"
              }} = ExWaiter.receive_next!(1, timeout: 200)
    end
  end
end
