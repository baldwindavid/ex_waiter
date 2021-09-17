defmodule ExWaiter.Waiter do
  alias ExWaiter.Attempt
  @enforce_keys [:checker_fn, :delay_before]

  defstruct [
    :checker_fn,
    :delay_before,
    fulfilled?: false,
    value: nil,
    total_delay: 0,
    num_attempts: 5,
    attempts_left: 5,
    attempt_num: 0,
    attempts: [],
    exception_on_retries_exhausted?: true
  ]

  @type t :: %__MODULE__{
          checker_fn: (() -> {:ok, any()} | {:error, any()}),
          delay_before: (__MODULE__.t() -> integer()) | integer(),
          fulfilled?: boolean(),
          value: any(),
          total_delay: integer(),
          num_attempts: integer(),
          attempts_left: integer(),
          attempt_num: integer(),
          attempts: [Attempt.t()]
        }
end
