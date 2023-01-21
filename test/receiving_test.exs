defmodule ExWaiter.ReceivingTest do
  use ExUnit.Case

  alias ExWaiter.Receiving.Timeout

  describe "receive/2" do
    test "returns a single message by default wrapped in an ok tuple" do
      send(self(), :hello)
      send(self(), :hi)

      assert {:ok, :hello} = ExWaiter.receive()
    end

    test "returns a list of messages when multiple are requested" do
      send(self(), :hello)
      send(self(), :hi)
      send(self(), :yo)
      assert {:ok, [:hello, :hi]} = ExWaiter.receive(2)
    end

    test "defaults to timing out after 100ms" do
      Process.send_after(self(), :will_receive, 50)
      assert {:ok, :will_receive} = ExWaiter.receive()

      Process.send_after(self(), :wont_receive, 120)
      assert :error = ExWaiter.receive()
    end

    test "can take a configurable timeout (ms)" do
      send(self(), :will_receive)
      assert {:ok, :will_receive} = ExWaiter.receive(1, timeout: 10)

      Process.send_after(self(), :wont_receive, 30)
      assert :error = ExWaiter.receive(1, timeout: 10)
    end

    test "can take an infinite timeout" do
      Process.send_after(self(), :will_receive, 120)
      assert {:ok, :will_receive} = ExWaiter.receive(1, timeout: :infinity)
    end

    test "times out unless all messages are received within timeout" do
      send(self(), :hello)
      send(self(), :hi)
      Process.send_after(self(), :yo, 30)

      assert {:error, _} = ExWaiter.receive(3, timeout: 10)
    end

    test "returns messages that were received previous to a timeout" do
      send(self(), :hello)
      send(self(), :hi)
      Process.send_after(self(), :yo, 20)

      assert {:error, [:hello, :hi]} = ExWaiter.receive(3, timeout: 10)
    end

    test "can filter messages" do
      send(self(), {:greeting, :hello})
      send(self(), {:age, 25})
      send(self(), {:greeting, :hi})

      assert {:ok, [{:greeting, :hello}, {:greeting, :hi}]} =
               ExWaiter.receive(2, filter: &match?({:greeting, _}, &1))
    end

    test "raises an exception with an invalid timeout" do
      assert_raise(
        RuntimeError,
        ":timeout must be either an integer (ms) or :infinity",
        fn ->
          ExWaiter.receive(1, timeout: :invalid_stuff)
        end
      )
    end

    test "raises an exception with an invalid filter" do
      assert_raise(
        RuntimeError,
        ":filter must be a function with an arity of 1",
        fn ->
          ExWaiter.receive(1, filter: :invalid_stuff)
        end
      )
    end

    test "raises an exception with an invalid option" do
      assert_raise(
        RuntimeError,
        "hello is not a valid option - Valid Options: timeout, filter, on_complete",
        fn ->
          ExWaiter.receive(1, hello: :world)
        end
      )
    end

    test "can take a callback on complete" do
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
                     remaining_timeout: remaining_timeout,
                     timeout: 100
                   } = receiver

            assert remaining_timeout < 100
          end
        )
    end

    test "tracks all received messages (filtered and rejected)" do
      send(self(), {:greeting, :hello})
      send(self(), {:age, 25})
      send(self(), {:greeting, :hi})

      assert {:ok, [{:greeting, :hello}, {:greeting, :hi}]} =
               ExWaiter.receive(2,
                 filter: &match?({:greeting, _}, &1),
                 on_complete: fn receiver ->
                   assert %ExWaiter.Receiving.Receiver{
                            message_num: 2,
                            all_messages: [{:greeting, :hello}, {:age, 25}, {:greeting, :hi}],
                            filtered_messages: [{:greeting, :hello}, {:greeting, :hi}],
                            rejected_messages: [{:age, 25}],
                            num_messages: 2
                          } = receiver
                 end
               )
    end
  end

  describe "receive!/2" do
    test "returns a single message by default" do
      send(self(), :hello)
      send(self(), :hi)

      assert :hello = ExWaiter.receive!()
    end

    test "returns a list of messages when multiple messages are requested" do
      send(self(), :hello)
      send(self(), :hi)
      send(self(), :yo)

      assert [:hello, :hi] = ExWaiter.receive!(2)
    end

    test "raises an exception when a timeout occurs" do
      Process.send_after(self(), :wont_receive, 50)

      assert_raise(Timeout, fn -> ExWaiter.receive!(10) end)
    end
  end
end
