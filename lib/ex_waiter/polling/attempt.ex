defmodule ExWaiter.Polling.Attempt do
  defstruct [:value, :next_delay]

  @type t :: %__MODULE__{
          value: any(),
          next_delay: non_neg_integer() | nil
        }
end
