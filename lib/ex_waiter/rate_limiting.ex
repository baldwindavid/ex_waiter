defmodule ExWaiter.RateLimiting do
  alias ExWaiter.RateLimiting.Limiter

  @type options :: [
          {:refill_rate, pos_integer()}
          | {:interval, pos_integer()}
          | {:burst_limit, pos_integer()}
          | {:cost, pos_integer()}
        ]
  @type token_count :: non_neg_integer()
  @type unix_timestamp_in_ms :: pos_integer()
  @type bucket :: {token_count(), unix_timestamp_in_ms()}

  @spec limit_rate(bucket() | nil, options()) ::
          {:ok, bucket(), Limiter.t()} | {:error, bucket(), Limiter.t()}
  def limit_rate(bucket, opts \\ []) do
    refill_rate = Keyword.get(opts, :refill_rate, 1)

    limiter = %Limiter{
      refill_rate: refill_rate,
      interval: Keyword.get(opts, :interval, 1000),
      burst_limit: Keyword.get(opts, :burst_limit, refill_rate),
      cost: Keyword.get(opts, :cost, 1),
      checked_at: System.os_time(:millisecond)
    }

    limiter =
      case bucket do
        {previous_tokens, previous_updated_at}
        when is_integer(previous_tokens) and
               previous_tokens >= 0 and
               is_integer(previous_updated_at) and
               previous_updated_at > 0 ->
          unless previous_updated_at <= limiter.checked_at do
            raise "Bucket timestamp must not be in the future"
          end

          handle_existing_bucket(limiter, previous_tokens, previous_updated_at)

        nil ->
          new_bucket(limiter)

        _ ->
          raise "Bucket must be either nil or {integer_token_count, unix_timestamp_in_ms}"
      end

    if limiter.paid_tokens > 0 do
      {:ok, {limiter.tokens_after_paid, limiter.updated_at}, limiter}
    else
      {:error, {limiter.tokens_after_paid, limiter.updated_at}, limiter}
    end
  end

  defp handle_existing_bucket(%Limiter{} = limiter, previous_tokens, previous_updated_at) do
    %{
      limiter
      | previous_tokens: previous_tokens,
        previous_updated_at: previous_updated_at
    }
    |> refill_tokens()
    |> pay_cost()
    |> set_updated_at()
  end

  defp new_bucket(%Limiter{} = limiter) do
    %{
      limiter
      | updated_at: limiter.checked_at,
        previous_updated_at: nil,
        created_at: limiter.checked_at,
        previous_tokens: nil,
        tokens_after_refill: limiter.burst_limit,
        tokens_after_paid: limiter.burst_limit - limiter.cost,
        ms_until_next_refill: limiter.interval,
        next_refill_at: limiter.checked_at + limiter.interval,
        refilled_tokens: limiter.burst_limit,
        paid_tokens: limiter.cost
    }
  end

  defp refill_tokens(%Limiter{} = limiter) do
    gained_tokens = calculate_gained_tokens(limiter)

    if gained_tokens > 0 do
      tokens_after_refill = min(limiter.previous_tokens + gained_tokens, limiter.burst_limit)

      %{
        limiter
        | tokens_after_refill: tokens_after_refill,
          refilled_tokens: tokens_after_refill - limiter.previous_tokens,
          ms_until_next_refill: limiter.interval,
          next_refill_at: limiter.checked_at + limiter.interval
      }
    else
      next_refill_at = limiter.previous_updated_at + limiter.interval

      %{
        limiter
        | tokens_after_refill: limiter.previous_tokens,
          refilled_tokens: 0,
          ms_until_next_refill: next_refill_at - limiter.checked_at,
          next_refill_at: next_refill_at
      }
    end
  end

  defp calculate_gained_tokens(%Limiter{} = limiter) do
    milliseconds_since_last_request = limiter.checked_at - limiter.previous_updated_at

    div(milliseconds_since_last_request, limiter.interval) *
      limiter.refill_rate
  end

  defp pay_cost(%Limiter{} = limiter) do
    tokens_after_paid = limiter.tokens_after_refill - limiter.cost

    if tokens_after_paid >= 0 do
      %{limiter | paid_tokens: limiter.cost, tokens_after_paid: tokens_after_paid}
    else
      %{limiter | paid_tokens: 0, tokens_after_paid: limiter.tokens_after_refill}
    end
  end

  defp set_updated_at(%Limiter{} = limiter) do
    if limiter.refilled_tokens > 0 do
      %{limiter | updated_at: limiter.checked_at}
    else
      %{limiter | updated_at: limiter.previous_updated_at}
    end
  end
end
