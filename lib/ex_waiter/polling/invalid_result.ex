defmodule ExWaiter.Polling.InvalidResult do
  defexception [:message]

  @impl true
  def exception(result) do
    msg = """

    Expected:
    {:ok, value}, :ok, or true for success
    {:error, value}, :error, or false for failure

    Got:
    #{inspect(result)}

    Examples:

      Returning a tagged tuple ensures that the Project is returned
      from poll/1.

      poller = ExWaiter.new_poller(fn ->
        case Projects.get(1) do
          %Project{} = project -> {:ok, project}
          value -> {:error, value}
        end
      end)

      {:ok, poller} = ExWaiter.poll(poller)
      %Project{name: name} = poller.value
    """

    %__MODULE__{message: msg}
  end
end
