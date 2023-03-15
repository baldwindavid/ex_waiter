defmodule ExWaiter.RateLimitingTest do
  use ExUnit.Case

  alias ExWaiter.RateLimiting.Limiter

  describe "refill rate" do
    test "refills tokens by 1 by default" do
      opts = [interval: 50]
      assert {:ok, {0, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:error, {0, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      Process.sleep(50)
      assert {:ok, {0, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end

    test "refill rate is configurable" do
      opts = [refill_rate: 3, interval: 50]
      assert {:ok, {2, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {1, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:ok, {0, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:error, {0, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      Process.sleep(50)
      assert {:ok, {2, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end

    test "refills based upon the number of intervals that have passed since last request" do
      opts = [interval: 50, burst_limit: 10, refill_rate: 1]
      assert {:ok, {9, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {8, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:ok, {7, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      Process.sleep(150)
      assert {:ok, {9, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end
  end

  describe "burst limit" do
    test "burst limit is equal to rate limit by default" do
      opts = [refill_rate: 3, interval: 50]
      assert {:ok, {2, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {1, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:ok, {0, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end

    test "burst limit is configurable" do
      opts = [refill_rate: 3, burst_limit: 5, interval: 50]
      assert {:ok, {4, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {3, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end

    test "tokens cannot grow larger than burst limit" do
      opts = [burst_limit: 2, interval: 50]
      assert {:ok, {1, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      Process.sleep(100)
      assert {:ok, {1, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end
  end

  describe "interval" do
    test "interval is one second by default" do
      assert {:ok, {0, _} = bucket, _} = ExWaiter.limit_rate(nil)
      assert {:error, {0, _} = bucket, _} = ExWaiter.limit_rate(bucket)
      Process.sleep(1000)
      assert {:ok, {0, _}, _} = ExWaiter.limit_rate(bucket)
    end

    test "interval is configurable" do
      opts = [burst_limit: 3, interval: 50]
      assert {:ok, {2, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {1, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      Process.sleep(100)
      assert {:ok, {2, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end
  end

  describe "cost" do
    test "the cost is one token by default" do
      opts = [burst_limit: 10]
      assert {:ok, {9, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {8, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:ok, {7, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end

    test "the cost is configurable" do
      opts = [cost: 3, burst_limit: 10]
      assert {:ok, {7, _} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {4, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:ok, {1, _} = bucket, _} = ExWaiter.limit_rate(bucket, opts)
      assert {:error, {1, _}, _} = ExWaiter.limit_rate(bucket, opts)
    end
  end

  describe "bucket validation" do
    test "raises an error with an invalid bucket" do
      Enum.each(
        [
          "not a bucket",
          42,
          {3},
          {1, 2, 3},
          {1, nil},
          {nil, System.os_time(:millisecond)},
          {nil, nil}
        ],
        fn bucket_data ->
          assert_raise RuntimeError,
                       "Bucket must be either nil or {integer_token_count, unix_timestamp_in_ms}",
                       fn ->
                         ExWaiter.limit_rate(bucket_data)
                       end
        end
      )
    end

    test "raises an error if previous updated at is in the future" do
      assert_raise RuntimeError,
                   "Bucket timestamp must not be in the future",
                   fn ->
                     ExWaiter.limit_rate({1, System.os_time(:millisecond) + 1000})
                   end
    end
  end

  describe "bucket timestamp changes" do
    test "timestamp changes if ok and new tokens received" do
      opts = [interval: 50]

      assert {:ok, {0, first_timestamp} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      Process.sleep(50)
      assert {:ok, {0, second_timestamp}, _} = ExWaiter.limit_rate(bucket, opts)
      assert first_timestamp != second_timestamp
    end

    test "timestamp does not change if ok and no new tokens received" do
      opts = [burst_limit: 2]

      assert {:ok, {1, first_timestamp} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      assert {:ok, {0, second_timestamp}, _} = ExWaiter.limit_rate(bucket, opts)
      assert first_timestamp == second_timestamp
    end

    test "timestamp changes if error and new tokens received" do
      opts = [refill_rate: 1, burst_limit: 2, interval: 50, cost: 2]

      assert {:ok, {0, first_timestamp} = bucket, _} = ExWaiter.limit_rate(nil, opts)
      Process.sleep(50)
      assert {:error, {1, second_timestamp}, _} = ExWaiter.limit_rate(bucket, opts)
      assert first_timestamp != second_timestamp
    end

    test "timestamp does not change if error and no new tokens received" do
      assert {:ok, {0, first_timestamp} = bucket, _} = ExWaiter.limit_rate(nil)
      assert {:error, {0, second_timestamp}, _} = ExWaiter.limit_rate(bucket)
      assert first_timestamp == second_timestamp
    end
  end

  test "tracks changes throughout calls" do
    opts = [interval: 50]

    assert {:ok, {0, checked_at} = bucket,
            %Limiter{
              refill_rate: 1,
              interval: 50,
              burst_limit: 1,
              cost: 1,
              checked_at: checked_at,
              created_at: checked_at,
              previous_updated_at: nil,
              updated_at: checked_at,
              next_refill_at: next_refill_at,
              ms_until_next_refill: 50,
              previous_tokens: nil,
              refilled_tokens: 1,
              tokens_after_refill: 1,
              paid_tokens: 1,
              tokens_after_paid: 0
            }} = ExWaiter.limit_rate(nil, opts)

    assert next_refill_at == checked_at + 50

    assert {:error, {0, updated_at} = bucket,
            %Limiter{
              refill_rate: 1,
              interval: 50,
              burst_limit: 1,
              cost: 1,
              checked_at: checked_at,
              created_at: nil,
              previous_updated_at: updated_at,
              updated_at: updated_at,
              next_refill_at: next_refill_at,
              ms_until_next_refill: ms_until_next_refill,
              previous_tokens: 0,
              refilled_tokens: 0,
              tokens_after_refill: 0,
              paid_tokens: 0,
              tokens_after_paid: 0
            }} = ExWaiter.limit_rate(bucket, opts)

    assert next_refill_at == updated_at + 50
    assert ms_until_next_refill == next_refill_at - checked_at

    Process.sleep(50)

    assert {:ok, {0, checked_at},
            %{
              refill_rate: 1,
              interval: 50,
              burst_limit: 1,
              cost: 1,
              checked_at: checked_at,
              created_at: nil,
              previous_updated_at: ^updated_at,
              updated_at: checked_at,
              next_refill_at: next_refill_at,
              ms_until_next_refill: 50,
              previous_tokens: 0,
              refilled_tokens: 1,
              tokens_after_refill: 1,
              paid_tokens: 1,
              tokens_after_paid: 0
            }} = ExWaiter.limit_rate(bucket, opts)

    assert next_refill_at == checked_at + 50
  end

  describe "state management" do
    defmodule RateLimitServer do
      use GenServer

      def init(buckets) do
        {:ok, buckets}
      end

      def handle_call({:enforce, bucket_name}, _, buckets) do
        bucket = Map.get(buckets, bucket_name)

        case ExWaiter.limit_rate(bucket,
               refill_rate: 2,
               interval: 100
             ) do
          {:ok, updated_bucket, _} ->
            {:reply, {:ok, updated_bucket}, Map.put(buckets, bucket_name, updated_bucket)}

          {:error, updated_bucket, _} ->
            {:reply, {:error, updated_bucket}, Map.put(buckets, bucket_name, updated_bucket)}
        end
      end
    end

    test "Genserver as shared rate limiter and bucket storage" do
      {:ok, server} = GenServer.start_link(RateLimitServer, %{})

      assert {:ok, {1, _}} = GenServer.call(server, {:enforce, "jane"})
      assert {:ok, {0, _}} = GenServer.call(server, {:enforce, "jane"})
      assert {:ok, {1, _}} = GenServer.call(server, {:enforce, "bill"})
      assert {:error, {0, _}} = GenServer.call(server, {:enforce, "jane"})
      assert {:ok, {0, _}} = GenServer.call(server, {:enforce, "bill"})
      assert {:error, {0, _}} = GenServer.call(server, {:enforce, "bill"})
      Process.sleep(100)
      assert {:ok, {1, _}} = GenServer.call(server, {:enforce, "bill"})
      assert {:ok, {1, _}} = GenServer.call(server, {:enforce, "pam"})
      assert {:ok, {1, _}} = GenServer.call(server, {:enforce, "jane"})
      assert {:ok, {0, _}} = GenServer.call(server, {:enforce, "bill"})
      assert {:error, {0, _}} = GenServer.call(server, {:enforce, "bill"})

      assert %{
               "jane" => {1, _},
               "bill" => {0, _},
               "pam" => {1, _}
             } = :sys.get_state(server)
    end
  end
end
