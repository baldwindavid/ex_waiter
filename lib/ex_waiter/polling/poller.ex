defmodule ExWaiter.Polling.Poller do
  alias ExWaiter.Polling.Attempt
  alias ExWaiter.Polling.Poller.Config

  @derive {Inspect,
           only: [
             :value,
             :next_delay,
             :total_delay,
             :attempt_num,
             :history
           ]}

  @type status :: :ok | {:error, :attempt_failed} | {:error, :retries_exhausted} | nil

  @enforce_keys [:config]
  defstruct [
    :config,
    status: nil,
    value: nil,
    next_delay: nil,
    history: nil,
    total_delay: 0,
    attempt_num: 0
  ]

  @type t :: %__MODULE__{
          config: Config.t(),
          status: status(),
          value: any(),
          next_delay: non_neg_integer() | nil,
          total_delay: non_neg_integer(),
          attempt_num: non_neg_integer(),
          history: [Attempt.t()] | nil
        }
end
