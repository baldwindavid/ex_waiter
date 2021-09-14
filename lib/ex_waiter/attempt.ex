defmodule ExWaiter.Attempt do
  @keys [:attempt_num, :fulfilled?, :value, :delay_before]
  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{
          attempt_num: integer(),
          fulfilled?: boolean(),
          value: any(),
          delay_before: integer()
        }
end
