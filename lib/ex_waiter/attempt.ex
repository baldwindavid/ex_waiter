defmodule ExWaiter.Attempt do
  @keys [:attempt_num, :fulfilled?, :value, :delay]
  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{
          attempt_num: integer(),
          fulfilled?: boolean(),
          value: any(),
          delay: integer()
        }
end
