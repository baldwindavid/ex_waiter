defmodule ExWaiter.Waiter do
  alias ExWaiter.Attempt

  @enforce_keys [:checker_fn, :delay_before, :returning]

  @type checker_result :: {:ok, any()} | {:error, any()} | :ok | :error | boolean()
  @type checker_fn :: (() -> checker_result) | (__MODULE__.t() -> checker_result)
  @type delay_before :: (__MODULE__.t() -> integer()) | integer()
  @type returning :: (__MODULE__.t() -> any())
  @type num_attempts :: integer() | :infinite

  defstruct([
    :checker_fn,
    :delay_before,
    :returning,
    fulfilled?: false,
    value: nil,
    total_delay: 0,
    num_attempts: 5,
    attempts_left: 5,
    attempt_num: 0,
    attempts: [],
    exception_on_retries_exhausted?: true
  ])

  @type t :: %__MODULE__{
          checker_fn: checker_fn,
          delay_before: delay_before,
          returning: returning,
          fulfilled?: boolean(),
          value: any(),
          total_delay: integer(),
          num_attempts: num_attempts,
          attempts_left: integer(),
          attempt_num: integer(),
          attempts: [Attempt.t()]
        }
end
