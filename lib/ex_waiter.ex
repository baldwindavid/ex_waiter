defmodule ExWaiter do
  @moduledoc """
  Handy functions for rate limiting, polling, and receiving.

  - Rate Limiting: `limit_rate/2` enforces a configurable token bucket rate limit.
  - Polling: `poll/1`, `poll!/1`, and `poll_once/1` periodically check that a
    given condition has been met.
  - Receiving: `receive_next/2` and `receive_next!/2` return the next message/s
    from the mailbox within a timeout.

  ## Installation

  Add the latest release to your `mix.exs` file:

  ```elixir
  defp deps do
    [
      {:ex_waiter, "~> 1.3.0"}
    ]
  end
  ```

  Then run `mix deps.get` in your shell to fetch the dependencies.
  """

  alias ExWaiter.Polling
  alias ExWaiter.RateLimiting
  alias ExWaiter.Receiving

  @doc """
  Enforces a configurable rate limit using the token bucket algorithm.

  ## Usage

  "Token Bucket" is a common algorithm for enforcing rate limits like "5
  requests per second". A "bucket" contains "tokens" (just a name representing a
  count) and the time the last token was added to the bucket. The number of
  tokens indicates how many requests can be made in a given period.

  This function takes a "bucket" tuple `{token_count, last_updated_timestamp}`
  and configuration options and checks if a bucket has the required token/s to
  make a request. The resulting updated "bucket" is then passed in for
  enforcement of the next request...rinse and repeat. In each case, if the
  required tokens are present, you make the request; otherwise you don't and
  wait until you can. This function intentionally has no constraints or opinions
  around bucket storage or state management (see [Storage and
  State](#limit_rate/2-storage-and-state) below for a simple example of state
  management with a Genserver)

  Each enforcement of a given bucket first checks the amount of time elapsed
  since the last tokens were "refilled" in the bucket. For "5 requests per
  second", 5 is the `refill_rate` while 1 second is the `interval`. The bucket
  will be refilled based upon the number of intervals that have passed. If 2
  seconds have passed, the user will have gained 10 more tokens (2 seconds x 5
  refill rate). If less than a second has passed, the bucket would not be
  refilled with any tokens.

  Let's assume the user already had 3 tokens and those 2 seconds have passed;
  they would now have 13 tokens. After adding the tokens, 1 token is then
  subtracted for the request and something like `{:ok, {12, 1678657185594},
  %Limiter{...}}` is returned. The second element in the tuple is the updated
  "bucket". The first element in that bucket (12) is the number of remaining
  tokens and the second element is the unix timestamp (in milliseconds) as the
  new updated time. This bucket can then be passed as the first argument of a
  future call of this function. The last element in the tuple is a `Limiter`
  struct which contains full details of the result (see details below). Had the
  user made a request with no remaining tokens and no tokens were refilled then
  something like `{:error, {0, 1678657185530}, %Limiter{...}}` would be
  returned. The timestamp would not be updated in this case because no tokens
  were refilled.

  This function allows configuration of both the `refill_rate` and `interval`.
  That may be enough in many cases, but it also supports `burst_limit` and
  `cost` options. "Burst limit" is the maximum amount of tokens that can be
  accumulated in a bucket (i.e. the bucket size). If the refill rate was 5 per
  second and no requests are made through the night you wouldn't want the user
  to continually fill the bucket and then be able to make a _burst_ of 144k
  requests in a small window of time, right? By default, the `burst_limit` is
  equal to the `refill_rate`, but it can be configured separately if you want
  the burst limit to be higher than the refill rate (for infrequent bursts). The
  `cost` is simply the number of tokens to be "paid" (subtracted) during
  enforcement. By default the cost is 1, but is configurable in case a single
  enforcement actually represents, say, 5 requests.

  ## Options

  * `:refill_rate` - The number of tokens to refill in the bucket per "interval"
    since the last refill. The default is `1`.
  * `:burst_limit` - The maximum amount of tokens that can be accumulated in a
    bucket (i.e. the bucket size). The default is equal to the `refill_rate`. A
    burst limit that is higher than the refill rate would support infrequent
    bursts, whereas the default enforces more of a consistent limit.
  * `:interval` - The time window that the rate limit enforces in milliseconds.
    For example, for a rate limit of "5 requests per second" the interval would
    be `1000` milliseconds (i.e. 1 second). The default is `1000`.
  * `:cost` - The number of tokens to remove from the bucket upon enforcement of
    the rate limit in case a single enforcement represents more than 1 API
    request. The default is `1`.

  ## Limiter struct

  This function returns a tuple of the format `{:ok, {remaining_tokens,
  updated_at}, %Limiter{...}}` or `{:error, {remaining_tokens, updated_at},
  %Limiter{...}}`. This `Limiter` struct contains additional details about
  refilled tokens, paid tokens, when the next tokens will be refilled, etc. This
  can be helpful for scheduling future requests and understanding the result of
  various configurations. Below is an example with a "bucket" containing 3
  tokens with a last update timestamp of 1678822656122. This bucket tuple along
  with the specified configuration options returns the `Limiter` struct below
  it. The resulting bucket can be used for the next result.

  ```elixir
  result =
    ExWaiter.limit_rate({3, 1678822656122},
      refill_rate: 3,
      interval: 50,
      burst_limit: 5,
      cost: 2
    )

  {:ok, {1, 1678822656122},
    %ExWaiter.RateLimiting.Limiter{
      # How many tokens to add with each passing interval
      refill_rate: 3,
      # Milliseconds between token refills
      interval: 50,
      # Max amount of tokens that can be in a bucket
      burst_limit: 5,
      # Amount of tokens to subtract
      cost: 2,
      # Timetamp when this limit was checked
      checked_at: 1678822656124,
      # If there is no bucket to pass in (e.g. user's first request ever)
      # this will be equal to checked_at; otherwise nil
      created_at: nil,
      # The timestamp passed into the check or nil if there is no bucket
      # to pass to the function
      previous_updated_at: 1678822656122,
      # Updated timestamp after the check - Equal to checked_at
      # if tokens are refilled; otherwise equal to previous_updated_at
      updated_at: 1678822656122,
      # Timestamp of next refill - If tokens were refilled this will
      # be equal to checked_at + interval; otherwise equal to
      # previous_updated_at + interval
      next_refill_at: 1678822656172,
      # Milliseconds until the next refill
      ms_until_next_refill: 48,
      # Number of tokens passed into the check or nil if there is no bucket
      # to pass to the function
      previous_tokens: 3,
      # Number of tokens refilled in this check
      refilled_tokens: 0,
      # Number of tokens in the bucket after refilling,
      # but prior to paying the cost - Equal to
      # previous_tokens + refilled_tokens
      tokens_after_refill: 3,
      # Number of tokens subtracted in this check
      paid_tokens: 2,
      # Number of tokens remaining - Equal to
      # previous_tokens + refilled_tokens - paid_tokens
      tokens_after_paid: 1
    }} = result
  ```

  ## Examples

  By default 1 token is refilled every 1 second. Below we enforce on a `nil`
  bucket; imagine this is a bucket for a user that has not made any requests
  before. The bucket will automatically get 1 token (equal to the "burst limit")
  so the first enforcement is successful.

  ```elixir
  {:ok, {0, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(nil)
  ```

  The first element of the bucket is the number of tokens left. The second
  element is a unix timestamp in milliseconds. An example bucket with a single
  token might be `{1, 1678669778198}`.

  We then pass that updated bucket and try to enforce again. Since the bucket
  now has no tokens we'll get back an error.

  ```elixir
  {:error, {0, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket)
  ```

  We then enforce again, but given a second has now passed, the bucket will get
  refilled with another token. The token is used and we get a successful return
  showing that the bucket again has no tokens.

  ```elixir
  Process.sleep(1000)
  {:ok, {0, _}, %Limiter{}} = ExWaiter.limit_rate(bucket)
  ```

  ### Configure Refill Rate

  The default `refill_rate` is 1, but this configurable. This is the number of
  tokens to refill in the bucket per "interval" that has passed since the last
  refill.

  ```elixir
  opts = [refill_rate: 3]
  {:ok, {2, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(nil, opts)
  {:ok, {1, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  {:ok, {0, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  {:error, {0, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  Process.sleep(1000)
  {:ok, {2, _}, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  ```

  ### Configure Interval

  The default `interval` is 1 second, but this is configurable. This is the time
  window that the rate limit enforces in milliseconds. For example, for a rate
  limit of "5 requests per second" the interval would be `1000` milliseconds.

  ```elixir
  opts = [interval: 50]
  {:ok, {0, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(nil, opts)
  {:error, {0, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  Process.sleep(50)
  {:ok, {0, _}, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  ```

  ### Configure Burst Limit

  The default `burst_limit` is equal to the `refill_rate`, but this is
  configurable. This is the maximum amount of tokens that can be accumulated in
  a bucket (i.e. the bucket size). A burst limit that is higher than the refill
  rate would support infrequent bursts, whereas the default enforces more of a
  consistent limit. Note that passing in `nil` for the first argument results in
  a new "full" bucket with a number of tokens equal to the burst limit.

  ```elixir
  opts = [refill_rate: 3, burst_limit: 5]
  {:ok, {4, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(nil, opts)
  {:ok, {3, _}, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  ```

  ### Configure Cost

  The cost defaults to 1, but this is configurable. This is the number of tokens
  to remove from the bucket upon enforcement of the rate limit in case a single
  enforcement represents more than 1 API request.

  ```elixir
  opts = [cost: 3, burst_limit: 10]
  {:ok, {7, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(nil, opts)
  {:ok, {4, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  {:ok, {1, _} = bucket, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  {:error, {1, _}, %Limiter{}} = ExWaiter.limit_rate(bucket, opts)
  ```

  ### Storage and State

  This function intentionally has no constraints or opinions around bucket
  storage or state management. It just takes a bucket and rate limit
  configuration and returns an updated bucket with a yay or nay on whether
  sufficient tokens exist for the request to be made. This provides for a lot of
  flexibility; you can manage a collection of user buckets with a Genserver,
  ETS, redis, etc. The only thing it requires is that "buckets" are passed to it
  that are either `nil` (no bucket for the user yet) or a tuple containing the
  token count and last request as a unix timestamp in milliseconds. The function
  will both produce (if the bucket is `nil`) and update those bucket tuples; you
  don't have to do any of that. You just need to store it somewhere and be able
  to return it later in the same format. Below is an example of a Genserver that
  stores a map of buckets with username keys in state.

  ```elixir
  defmodule RateLimitServer do
    use GenServer

    def init(buckets) do
      {:ok, buckets}
    end

    def handle_call({:enforce, bucket_key}, _, buckets) do
      bucket = Map.get(buckets, bucket_key)

      {_, updated_bucket, %Limiter{}} =
        result =
        ExWaiter.limit_rate(bucket,
          refill_rate: 2,
          interval: 100
        )

      {:reply, result, Map.put(buckets, bucket_key, updated_bucket)}
    end
  end

  {:ok, server} = GenServer.start_link(RateLimitServer, %{})

  {:ok, {1, _}} = GenServer.call(server, {:enforce, "jane"})
  {:ok, {0, _}} = GenServer.call(server, {:enforce, "jane"})
  {:ok, {1, _}} = GenServer.call(server, {:enforce, "bill"})
  {:error, {0, _}} = GenServer.call(server, {:enforce, "jane"})
  {:ok, {0, _}} = GenServer.call(server, {:enforce, "bill"})
  {:error, {0, _}} = GenServer.call(server, {:enforce, "bill"})
  Process.sleep(100)
  {:ok, {1, _}} = GenServer.call(server, {:enforce, "bill"})
  {:ok, {1, _}} = GenServer.call(server, {:enforce, "pam"})
  {:ok, {1, _}} = GenServer.call(server, {:enforce, "jane"})
  {:ok, {0, _}} = GenServer.call(server, {:enforce, "bill"})
  {:error, {0, _}} = GenServer.call(server, {:enforce, "bill"})

  %{
    "jane" => {1, _},
    "bill" => {0, _},
    "pam" => {1, _}
  } = :sys.get_state(server)
  ```
  """
  @spec limit_rate(RateLimiting.bucket() | nil, RateLimiting.options()) ::
          {:ok, RateLimiting.bucket(), RateLimiting.Limiter.t()}
          | {:error, RateLimiting.bucket(), RateLimiting.Limiter.t()}
  defdelegate limit_rate(bucket, opts \\ []), to: RateLimiting

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
