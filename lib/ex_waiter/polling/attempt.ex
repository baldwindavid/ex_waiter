defmodule ExWaiter.Polling.Attempt do
  @keys [:value, :delay]
  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{
          value: any(),
          delay: integer()
        }
end
