defmodule ExWaiter.Receiving.Timeout do
  defexception [:message]

  alias ExWaiter.Receiving.Receiver

  @impl true
  def exception(%Receiver{} = receiver) do
    msg = """
    Tried to get #{receiver.num_messages} message/s over #{receiver.timeout}ms, but not all messages were received.

    #{inspect(receiver, pretty: true)}
    """

    %__MODULE__{message: msg}
  end
end
