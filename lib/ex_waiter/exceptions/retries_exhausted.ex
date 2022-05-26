defmodule ExWaiter.Exceptions.RetriesExhausted do
  defexception [:message]

  alias ExWaiter.Waiter

  @impl true
  @spec exception(%Waiter{}) :: %__MODULE__{}
  def exception(%Waiter{} = waiter) do
    msg = """
    Tried #{waiter.num_attempts} times over #{waiter.total_delay}ms, but condition was never met.

    #{inspect(waiter, pretty: true)}
    """

    %__MODULE__{message: msg}
  end
end
