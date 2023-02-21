defmodule ExWaiter.Polling.RetriesExhausted do
  defexception [:message]

  alias ExWaiter.Polling.Poller

  @impl true
  def exception(%Poller{} = poller) do
    msg = """
    Tried #{poller.attempt_num} times over #{poller.total_delay}ms, but condition was never met.

    #{inspect(poller, pretty: true)}
    """

    %__MODULE__{message: msg}
  end
end
