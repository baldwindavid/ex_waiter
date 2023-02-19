defmodule ExWaiter.ReceivingTest do
  use ExUnit.Case

  describe "receive_next/2" do
    test "returns a single message by default wrapped in an ok tuple" do
      send(self(), :hello)
      send(self(), :hi)

      assert {:ok, :hello} = ExWaiter.receive_next()
    end

    test "returns a list of messages when multiple are requested" do
      send(self(), :hello)
      send(self(), :hi)
      send(self(), :yo)
      assert {:ok, [:hello, :hi]} = ExWaiter.receive_next(2)
    end

    test "defaults to timing out after 100ms" do
      Process.send_after(self(), :will_receive, 50)
      assert {:ok, :will_receive} = ExWaiter.receive_next()

      Process.send_after(self(), :wont_receive, 120)
      assert :error = ExWaiter.receive_next()
    end

    test "can take a configurable timeout (ms)" do
      send(self(), :will_receive)
      assert {:ok, :will_receive} = ExWaiter.receive_next(1, timeout: 10)

      Process.send_after(self(), :wont_receive, 30)
      assert :error = ExWaiter.receive_next(1, timeout: 10)
    end

    test "can take an infinite timeout" do
      Process.send_after(self(), :will_receive, 120)
      assert {:ok, :will_receive} = ExWaiter.receive_next(1, timeout: :infinity)
    end

    test "times out unless all messages are received within timeout" do
      send(self(), :hello)
      send(self(), :hi)
      Process.send_after(self(), :yo, 30)

      assert {:error, _} = ExWaiter.receive_next(3, timeout: 10)
    end

    test "returns messages that were received previous to a timeout" do
      send(self(), :hello)
      send(self(), :hi)
      Process.send_after(self(), :yo, 20)

      assert {:error, [:hello, :hi]} = ExWaiter.receive_next(3, timeout: 10)
    end

    test "raises an exception with an invalid timeout" do
      assert_raise(
        RuntimeError,
        ":timeout must be either an integer (ms) or :infinity",
        fn ->
          ExWaiter.receive_next(1, timeout: :invalid_stuff)
        end
      )
    end

    test "raises an exception with an invalid option" do
      assert_raise(
        RuntimeError,
        "hello is not a valid option - Valid Options: timeout",
        fn ->
          ExWaiter.receive_next(1, hello: :world)
        end
      )
    end
  end
end
