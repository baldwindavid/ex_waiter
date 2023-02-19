defmodule ExWaiter.Polling.Poller.Config do
  @type polling_result :: :ok | :error | {:ok, any()} | {:error, any()}
  @type polling_fn :: (__MODULE__.t() -> polling_result())
  @type delay :: (__MODULE__.t() -> non_neg_integer()) | non_neg_integer()
  @type max_attempts :: non_neg_integer() | :infinity | (__MODULE__.t() -> boolean())

  defstruct [
    :polling_fn,
    :delay,
    :max_attempts,
    auto_retry: true,
    record_history: false
  ]

  @type t :: %__MODULE__{
          polling_fn: polling_fn(),
          delay: delay(),
          max_attempts: max_attempts(),
          auto_retry: boolean(),
          record_history: boolean()
        }
end
