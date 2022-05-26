defmodule ExWaiter.Exceptions.RetriesExhausted do
  defexception [:message]

  alias ExWaiter.Waiter
  alias __MODULE__

  @impl true
  # FIXME: I'd rather use %__MODULE__ than need to alias it to reference
  # @spec exception(%Waiter{}) :: %__MODULE__{}
  @spec exception(%Waiter{}) :: %RetriesExhausted{}
  def exception(%Waiter{} = waiter) do
    msg = """
    Tried #{waiter.num_attempts} times over #{waiter.total_delay}ms, but condition was never met.

    #{inspect(waiter, pretty: true)}
    """

    %__MODULE__{message: msg}
  end
end
