defmodule ExWaiter.Exceptions.InvalidResult do
  defexception [:message]

  @impl true
  @spec exception(any()) :: %__MODULE__{}
  def exception(result) do
    msg = """

    Expected:
    {:ok, value}, :ok, or true for success
    {:error, value}, :error, or false for failure

    Got:
    #{inspect(result)}

    Examples:

      Returning a tagged tuple ensures that the Project is returned
      from await!/2.

      %Project{name: name} = await!(fn ->
        case Projects.get(1) do
          %Project{} = project -> {:ok, project}
          value -> {:error, value}
        end
      end)

      If you only care about whether an exception is raised, any of
      :ok, :error, true, or false may be returned.

      await!(fn ->
        case Projects.get(1) do
          %Project{} -> :ok # or true
          _ -> :error # or false
        end
      end)
    """

    %__MODULE__{message: msg}
  end
end
