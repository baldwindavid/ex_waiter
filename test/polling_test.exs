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

  describe "poll/2" do
    test "retries up to 5 times and returns the value by default upon success" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:ok, "Got it!"} =
               ExWaiter.poll(fn ->
                 case OrderedStore.current_value(store) do
                   nil ->
                     {:error, nil}

                   value ->
                     {:ok, value}
                 end
               end)
    end

    test "can take a callback on complete" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil ->
              {:error, nil}

            value ->
              {:ok, value}
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempt_num: 5,
                   num_attempts: 5,
                   attempts: [
                     %{value: {:error, nil}, delay: 10},
                     %{value: {:error, nil}, delay: 20},
                     %{value: {:error, nil}, delay: 30},
                     %{value: {:error, nil}, delay: 40},
                     %{value: {:ok, "Got it!"}, delay: 50}
                   ],
                   total_delay: 150,
                   value: {:ok, "Got it!"}
                 } = poller
        end
      )
    end

    test "supports :ok and :error return values, but with no value tracking" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert :ok =
               ExWaiter.poll(fn ->
                 case OrderedStore.current_value(store) do
                   nil -> :error
                   _ -> :ok
                 end
               end)
    end

    test "doesn't make any more attempts than necessary" do
      attempts = [nil, "Got it!", "third", "fourth", "fifth"]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempt_num: 2,
                   num_attempts: 5,
                   attempts: [
                     %{value: :error},
                     %{value: :ok}
                   ],
                   value: :ok
                 } = poller
        end
      )
    end

    test "returns an error when retries are exhausted" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempt_num: 5,
                   num_attempts: 5,
                   value: :error
                 } = poller
        end
      )
    end

    test "can be configured for less attempts" do
      attempts = [nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        num_attempts: 2,
        on_complete: fn poller ->
          assert %{
                   attempt_num: 2,
                   num_attempts: 2,
                   value: :error
                 } = poller
        end
      )
    end

    test "can be configured for infinite attempts" do
      attempts = [nil, nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        num_attempts: :infinity,
        on_complete: fn poller ->
          assert %{
                   attempt_num: 6,
                   num_attempts: :infinity,
                   value: :ok
                 } = poller
        end
      )
    end

    test "raises an exception with an invalid number of attempts" do
      assert_raise(
        RuntimeError,
        ":num_attempts must be either an integer (ms) or :infinity",
        fn ->
          ExWaiter.poll(
            fn -> "doesn't matter" end,
            num_attempts: :invalid_stuff
          )
        end
      )
    end

    test "can optionally take the Poller struct as an argument to the polling function" do
      attempts = [nil, "first", "second", "third"]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn poller ->
          case OrderedStore.current_value(store) do
            nil ->
              :error

            value ->
              if poller.value == {:error, "second"} do
                {:ok, value}
              else
                {:error, value}
              end
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempt_num: 4,
                   num_attempts: 5,
                   attempts: [
                     %{value: :error},
                     %{value: {:error, "first"}},
                     %{value: {:error, "second"}},
                     %{value: {:ok, "third"}}
                   ],
                   value: {:ok, "third"}
                 } = poller
        end
      )
    end

    test "waits increasing milliseconds before each successive retry by default" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempts: [
                     %{delay: 10},
                     %{delay: 20},
                     %{delay: 30},
                     %{delay: 40},
                     %{delay: 50}
                   ],
                   total_delay: 150
                 } = poller
        end
      )
    end

    test "can take a delay configuration function" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempts: [
                     %{delay: 2},
                     %{delay: 4},
                     %{delay: 6},
                     %{delay: 8},
                     %{delay: 10}
                   ],
                   value: :error,
                   total_delay: 30
                 } = poller
        end,
        delay: fn poller -> poller.attempt_num * 2 end
      )
    end

    test "can take an integer for delay before" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      ExWaiter.poll(
        fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end,
        on_complete: fn poller ->
          assert %{
                   attempts: [
                     %{delay: 1},
                     %{delay: 1},
                     %{delay: 1},
                     %{delay: 1},
                     %{delay: 1}
                   ],
                   value: :error,
                   total_delay: 5
                 } = poller
        end,
        delay: 1
      )
    end

    test "raises an exception with an invalid option" do
      assert_raise(
        RuntimeError,
        "hello is not a valid option",
        fn ->
          ExWaiter.poll(
            fn -> "doesn't matter" end,
            hello: :world
          )
        end
      )
    end

    test "raises an exception with an invalid result" do
      Enum.each(["yep", "nope", nil], fn value ->
        assert_raise(InvalidResult, fn ->
          ExWaiter.poll(fn -> value end)
        end)
      end)
    end
  end

  describe "poll!/2" do
    test "waits for a result and returns the value" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert "Got it!" =
               ExWaiter.poll!(fn ->
                 case OrderedStore.current_value(store) do
                   nil ->
                     :error

                   value ->
                     {:ok, value}
                 end
               end)
    end

    test "supports a successful result, but without a value" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert :ok =
               ExWaiter.poll!(fn ->
                 case OrderedStore.current_value(store) do
                   nil ->
                     :error

                   _ ->
                     :ok
                 end
               end)
    end

    test "throws an exception when retries are exhausted" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert_raise(RetriesExhausted, fn ->
        ExWaiter.poll!(fn ->
          case OrderedStore.current_value(store) do
            nil -> :error
            _ -> :ok
          end
        end)
      end)
    end
  end
end
