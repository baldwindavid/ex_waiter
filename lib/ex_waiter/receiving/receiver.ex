defmodule ExWaiter.Receiving.Receiver do
  @keys [
    :message_num,
    :timeout,
    :remaining_timeout,
    :num_messages,
    :filter_fn,
    :on_complete,
    all_messages: [],
    filtered_messages: [],
    rejected_messages: []
  ]
  defstruct @keys

  @type filter_fn :: (any() -> boolean())
  @type on_complete :: (__MODULE__.t() -> any())

  @type t :: %__MODULE__{
          message_num: pos_integer(),
          timeout: timeout(),
          remaining_timeout: non_neg_integer() | nil,
          all_messages: [any()],
          filtered_messages: [any()],
          rejected_messages: [any()],
          num_messages: pos_integer(),
          filter_fn: filter_fn(),
          on_complete: on_complete()
        }
end
