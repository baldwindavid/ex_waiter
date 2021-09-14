defmodule ExWaiter.Exceptions.InvalidResult do
  defexception [:message]

  @impl true
  def exception(result) do
    msg = """

    Expected:
    {:ok, term} or {:error, term}

    Got:
    #{inspect(result)}

    Example:

      wait_for(fn _waiter ->
        case Projects.get(1) do
          %Project{} = project -> {:ok, project}
          value -> {:error, value}
        end
      end)
    """

    %__MODULE__{message: msg}
  end
end
