defmodule ExWaiter.Waiter do
  alias ExWaiter.Attempt

  @enforce_keys [:checker_fn, :delay, :returning]

  @type checker_result :: {:ok, any()} | {:error, any()} | :ok | :error | boolean()
  @type checker_fn :: (() -> checker_result) | (__MODULE__.t() -> checker_result)
  @type delay :: (__MODULE__.t() -> integer()) | integer()
  @type returning :: (__MODULE__.t() -> any())
  @type num_attempts :: integer() | :infinity
  @type on_success :: (__MODULE__.t() -> any())
  @type on_failure :: (__MODULE__.t() -> any())

  defstruct([
    :checker_fn,
    :delay,
    :returning,
    :on_success,
    :on_failure,
    fulfilled?: false,
    value: nil,
    total_delay: 0,
    num_attempts: 5,
    attempt_num: 0,
    attempts: [],
    exception_on_retries_exhausted?: true
  ])

  @type t :: %__MODULE__{
          checker_fn: checker_fn,
          delay: delay,
          returning: returning,
          on_success: on_success,
          on_failure: on_failure,
          fulfilled?: boolean(),
          value: any(),
          total_delay: integer(),
          num_attempts: num_attempts,
          attempt_num: integer(),
          attempts: [Attempt.t()]
        }
end
