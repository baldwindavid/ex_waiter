defmodule ExWaiter.Polling.Poller do
  alias ExWaiter.Polling.Attempt

  @enforce_keys [:polling_fn, :delay]

  @type polling_result :: :ok | :error | {:ok, any()} | {:error, any()}
  @type polling_fn :: (() -> polling_result()) | (__MODULE__.t() -> polling_result())
  @type delay :: (__MODULE__.t() -> integer()) | integer()
  @type num_attempts :: integer() | :infinity
  @type on_complete :: (__MODULE__.t() -> any())

  defstruct([
    :delay,
    :polling_fn,
    :on_complete,
    value: nil,
    total_delay: 0,
    num_attempts: 5,
    attempt_num: 0,
    attempts: []
  ])

  @type t :: %__MODULE__{
          delay: delay(),
          polling_fn: polling_fn(),
          on_complete: on_complete(),
          value: any(),
          total_delay: integer(),
          num_attempts: num_attempts(),
          attempt_num: integer(),
          attempts: [Attempt.t()]
        }
end
