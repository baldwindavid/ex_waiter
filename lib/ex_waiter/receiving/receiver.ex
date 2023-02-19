defmodule ExWaiter.Receiving.Receiver do
  @keys [
    :message_num,
    :timeout,
    :remaining_timeout,
    :num_messages,
    messages: []
  ]
  defstruct @keys

  @type options :: [{:timeout, timeout()}]
  @type t :: %__MODULE__{
          message_num: pos_integer(),
          timeout: timeout(),
          remaining_timeout: non_neg_integer() | nil,
          messages: [any()],
          num_messages: pos_integer()
        }
end
