defmodule ExWaiter.Polling do
  alias ExWaiter.Polling.Attempt
  alias ExWaiter.Polling.InvalidResult
  alias ExWaiter.Polling.Poller

  @valid_options [:delay, :num_attempts, :on_complete]

  def poll(polling_fn, opts) do
    Enum.each(opts, fn {key, _} ->
      unless key in @valid_options do
        raise "#{key} is not a valid option"
      end
    end)

    num_attempts = Keyword.get(opts, :num_attempts, 5)

    unless is_integer(num_attempts) || num_attempts == :infinity do
      raise ":num_attempts must be either an integer (ms) or :infinity"
    end

    %Poller{
      polling_fn: polling_fn,
      delay: Keyword.get(opts, :delay, &delay_default/1),
      num_attempts: Keyword.get(opts, :num_attempts, 5),
      on_complete: Keyword.get(opts, :on_complete, & &1)
    }
    |> attempt()
  end

  defp attempt(%Poller{attempt_num: num, num_attempts: num} = poller) do
    poller.on_complete.(poller)
    {:error, poller}
  end

  defp attempt(%Poller{} = poller) do
    poller = init_attempt(poller)

    delay = determine_delay(poller)
    Process.sleep(delay)

    case handle_polling_fn(poller) do
      {:ok, _} = result -> handle_successful_attempt(poller, result, delay)
      :ok = result -> handle_successful_attempt(poller, result, delay)
      {:error, _} = result -> handle_failed_attempt(poller, result, delay)
      :error = result -> handle_failed_attempt(poller, result, delay)
      result -> raise InvalidResult, result
    end
  end

  defp init_attempt(%Poller{} = poller) do
    %{poller | attempt_num: poller.attempt_num + 1}
  end

  defp handle_successful_attempt(%Poller{} = poller, value, delay) do
    poller = record_attempt(poller, value, delay)
    poller.on_complete.(poller)
    {:ok, poller}
  end

  defp handle_failed_attempt(%Poller{} = poller, value, delay) do
    poller
    |> record_attempt(value, delay)
    |> attempt()
  end

  defp record_attempt(%Poller{} = poller, value, delay) do
    attempts =
      [
        %Attempt{
          value: value,
          delay: delay
        }
        | Enum.reverse(poller.attempts)
      ]
      |> Enum.reverse()

    %{
      poller
      | attempts: attempts,
        value: value,
        total_delay: poller.total_delay + delay
    }
  end

  defp determine_delay(%Poller{delay: ms}) when is_integer(ms), do: ms

  defp determine_delay(%Poller{delay: delay_fn} = poller)
       when is_function(delay_fn),
       do: delay_fn.(poller)

  defp delay_default(%Poller{} = poller) do
    poller.attempt_num * 10
  end

  defp handle_polling_fn(%Poller{polling_fn: polling_fn} = poller) do
    case :erlang.fun_info(polling_fn)[:arity] do
      1 -> polling_fn.(poller)
      0 -> polling_fn.()
      _ -> raise "Poller function must have an arity of either 0 or 1"
    end
  end
end
