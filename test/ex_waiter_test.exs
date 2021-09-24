defmodule ExWaiterTest do
  use ExUnit.Case

  alias ExWaiter.Exceptions.InvalidResult
  alias ExWaiter.Exceptions.RetriesExhausted

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

  describe "await/2" do
    test "retries up to 5 times and returns the value by default upon success" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:ok, "Got it!"} =
               ExWaiter.await(fn ->
                 case OrderedStore.current_value(store) do
                   nil ->
                     {:error, nil}

                   value ->
                     {:ok, value}
                 end
               end)
    end

    test "can be configured to return the Waiter struct" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:ok, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil ->
                       {:error, nil}

                     value ->
                       {:ok, value}
                   end
                 end,
                 returning: fn waiter -> waiter end
               )

      assert %{
               attempt_num: 5,
               attempts_left: 0,
               num_attempts: 5,
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: nil, delay: 10},
                 %{attempt_num: 2, fulfilled?: false, value: nil, delay: 20},
                 %{attempt_num: 3, fulfilled?: false, value: nil, delay: 30},
                 %{attempt_num: 4, fulfilled?: false, value: nil, delay: 40},
                 %{attempt_num: 5, fulfilled?: true, value: "Got it!", delay: 50}
               ],
               total_delay: 150,
               fulfilled?: true,
               value: "Got it!"
             } = waiter
    end

    test "supports boolean return values, but with no value tracking" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:ok, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> false
                     _ -> true
                   end
                 end,
                 returning: fn waiter -> waiter end
               )

      assert %{
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: nil},
                 %{attempt_num: 2, fulfilled?: false, value: nil},
                 %{attempt_num: 3, fulfilled?: false, value: nil},
                 %{attempt_num: 4, fulfilled?: false, value: nil},
                 %{attempt_num: 5, fulfilled?: true, value: nil}
               ],
               fulfilled?: true,
               value: nil
             } = waiter
    end

    test "supports :ok and :error return values, but with no value tracking" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:ok, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> :error
                     _ -> :ok
                   end
                 end,
                 returning: fn waiter -> waiter end
               )

      assert %{
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: nil},
                 %{attempt_num: 2, fulfilled?: false, value: nil},
                 %{attempt_num: 3, fulfilled?: false, value: nil},
                 %{attempt_num: 4, fulfilled?: false, value: nil},
                 %{attempt_num: 5, fulfilled?: true, value: nil}
               ],
               fulfilled?: true,
               value: nil
             } = waiter
    end

    test "doesn't make any more attempts than necessary" do
      attempts = [nil, "Got it!", "third", "fourth", "fifth"]
      store = OrderedStore.new(attempts)

      assert {:ok, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> {:error, nil}
                     value -> {:ok, value}
                   end
                 end,
                 returning: fn waiter -> waiter end
               )

      assert %{
               attempt_num: 2,
               attempts_left: 3,
               num_attempts: 5,
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: nil},
                 %{attempt_num: 2, fulfilled?: true, value: "Got it!"}
               ],
               fulfilled?: true,
               value: "Got it!"
             } = waiter
    end

    test "returns an error tuple with the Waiter struct when retries are exhausted" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert {:error, waiter} =
               ExWaiter.await(fn ->
                 case OrderedStore.current_value(store) do
                   nil -> {:error, nil}
                   value -> {:ok, value}
                 end
               end)

      assert %{
               attempt_num: 5,
               attempts_left: 0,
               num_attempts: 5,
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: nil},
                 %{attempt_num: 2, fulfilled?: false, value: nil},
                 %{attempt_num: 3, fulfilled?: false, value: nil},
                 %{attempt_num: 4, fulfilled?: false, value: nil},
                 %{attempt_num: 5, fulfilled?: false, value: nil}
               ],
               fulfilled?: false,
               value: nil
             } = waiter
    end

    test "can be configured for less attempts" do
      attempts = [nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:error, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> {:error, nil}
                     value -> {:ok, value}
                   end
                 end,
                 num_attempts: 2
               )

      assert %{
               attempt_num: 2,
               attempts_left: 0,
               num_attempts: 2,
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: nil},
                 %{attempt_num: 2, fulfilled?: false, value: nil}
               ],
               fulfilled?: false,
               value: nil
             } = waiter
    end

    test "can be configured for infinite attempts" do
      attempts = [nil, nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert {:ok, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> {:error, nil}
                     value -> {:ok, value}
                   end
                 end,
                 num_attempts: :infinite,
                 returning: fn waiter -> waiter end
               )

      assert %{
               attempt_num: 6,
               attempts_left: :infinite,
               num_attempts: :infinite,
               attempts: [
                 %{attempt_num: 1, fulfilled?: false},
                 %{attempt_num: 2, fulfilled?: false},
                 %{attempt_num: 3, fulfilled?: false},
                 %{attempt_num: 4, fulfilled?: false},
                 %{attempt_num: 5, fulfilled?: false},
                 %{attempt_num: 6, fulfilled?: true}
               ],
               fulfilled?: true,
               value: "Got it!"
             } = waiter
    end

    test "can optionally take the Waiter struct as an argument to the checker function" do
      attempts = ["first", "second", "third"]
      store = OrderedStore.new(attempts)

      assert {:ok, waiter} =
               ExWaiter.await(
                 fn waiter ->
                   case OrderedStore.current_value(store) do
                     nil ->
                       {:error, nil}

                     value ->
                       if waiter.value == "second" do
                         {:ok, value}
                       else
                         {:error, value}
                       end
                   end
                 end,
                 returning: fn waiter -> waiter end
               )

      assert %{
               attempt_num: 3,
               attempts_left: 2,
               num_attempts: 5,
               attempts: [
                 %{attempt_num: 1, fulfilled?: false, value: "first"},
                 %{attempt_num: 2, fulfilled?: false, value: "second"},
                 %{attempt_num: 3, fulfilled?: true, value: "third"}
               ],
               fulfilled?: true,
               value: "third"
             } = waiter
    end

    test "waits increasing milliseconds before each successive retry by default" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert {:error, waiter} =
               ExWaiter.await(fn ->
                 case OrderedStore.current_value(store) do
                   nil -> {:error, nil}
                   value -> {:ok, value}
                 end
               end)

      assert %{
               attempts: [
                 %{attempt_num: 1, delay: 10},
                 %{attempt_num: 2, delay: 20},
                 %{attempt_num: 3, delay: 30},
                 %{attempt_num: 4, delay: 40},
                 %{attempt_num: 5, delay: 50}
               ],
               fulfilled?: false,
               total_delay: 150
             } = waiter
    end

    test "can take a delay configuration function" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert {:error, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> {:error, nil}
                     value -> {:ok, value}
                   end
                 end,
                 delay: fn waiter -> waiter.attempt_num * 2 end
               )

      assert %{
               attempts: [
                 %{attempt_num: 1, delay: 2},
                 %{attempt_num: 2, delay: 4},
                 %{attempt_num: 3, delay: 6},
                 %{attempt_num: 4, delay: 8},
                 %{attempt_num: 5, delay: 10}
               ],
               fulfilled?: false,
               total_delay: 30
             } = waiter
    end

    test "can take an integer for delay before" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert {:error, waiter} =
               ExWaiter.await(
                 fn ->
                   case OrderedStore.current_value(store) do
                     nil -> {:error, nil}
                     value -> {:ok, value}
                   end
                 end,
                 delay: 1
               )

      assert %{
               attempts: [
                 %{attempt_num: 1, delay: 1},
                 %{attempt_num: 2, delay: 1},
                 %{attempt_num: 3, delay: 1},
                 %{attempt_num: 4, delay: 1},
                 %{attempt_num: 5, delay: 1}
               ],
               fulfilled?: false,
               total_delay: 5
             } = waiter
    end

    test "raises an exception with an invalid option" do
      assert_raise(
        RuntimeError,
        "hello is not a valid option - Valid Options: delay, returning, num_attempts",
        fn ->
          ExWaiter.await(
            fn -> "doesn't matter" end,
            hello: :world
          )
        end
      )
    end

    test "raises an exception with an invalid result" do
      attempts = [nil]
      store = OrderedStore.new(attempts)

      assert_raise(InvalidResult, fn ->
        ExWaiter.await(fn ->
          case OrderedStore.current_value(store) do
            nil ->
              "example invalid result value - should be {:ok, value}, {:error, value}, :ok, :error, true, or false"

            value ->
              {:ok, value}
          end
        end)
      end)
    end
  end

  describe "await!/2" do
    test "waits for a result and returns the value" do
      attempts = [nil, nil, nil, nil, "Got it!"]
      store = OrderedStore.new(attempts)

      assert ExWaiter.await!(fn ->
               case OrderedStore.current_value(store) do
                 nil ->
                   {:error, nil}

                 value ->
                   {:ok, value}
               end
             end) == "Got it!"
    end

    test "throws an exception when retries are exhausted" do
      attempts = [nil, nil, nil, nil, nil]
      store = OrderedStore.new(attempts)

      assert_raise(RetriesExhausted, fn ->
        ExWaiter.await!(fn ->
          case OrderedStore.current_value(store) do
            nil -> {:error, nil}
            value -> {:ok, value}
          end
        end)
      end)
    end
  end
end
