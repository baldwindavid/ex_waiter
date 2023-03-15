defmodule ExWaiter.RateLimiting.Limiter do
  @type timestamp_in_ms :: pos_integer()

  defstruct [
    :refill_rate,
    :interval,
    :burst_limit,
    :cost,
    :checked_at,
    :created_at,
    :previous_updated_at,
    :updated_at,
    :next_refill_at,
    :ms_until_next_refill,
    :previous_tokens,
    :refilled_tokens,
    :tokens_after_refill,
    :paid_tokens,
    :tokens_after_paid
  ]

  @type t :: %__MODULE__{
          refill_rate: pos_integer(),
          interval: pos_integer(),
          burst_limit: pos_integer(),
          cost: pos_integer(),
          checked_at: timestamp_in_ms(),
          created_at: timestamp_in_ms() | nil,
          previous_updated_at: timestamp_in_ms() | nil,
          updated_at: timestamp_in_ms(),
          next_refill_at: timestamp_in_ms(),
          ms_until_next_refill: non_neg_integer(),
          previous_tokens: non_neg_integer() | nil,
          refilled_tokens: non_neg_integer(),
          tokens_after_refill: non_neg_integer(),
          paid_tokens: non_neg_integer(),
          tokens_after_paid: non_neg_integer()
        }
end
