defmodule ExWaiter.Polling do
  alias ExWaiter.Polling.Attempt
  alias ExWaiter.Polling.InvalidResult
  alias ExWaiter.Polling.Poller
  alias ExWaiter.Polling.Poller.Config

  @valid_options [:delay, :max_attempts, :record_history]

  @type poll_result ::
          {:ok, Poller.t()}
          | {:error, :retries_exhausted, Poller.t()}
          | {:error, :attempt_failed, Poller.t()}
  @type options :: [
          {:delay, Config.delay()}
          | {:max_attempts, Config.max_attempts()}
          | {:record_history, boolean()}
        ]

  @spec new_poller(Poller.Config.polling_fn(), options()) :: Poller.t()
  def new_poller(polling_fn, opts) do
    Enum.each(opts, fn {key, _} ->
      unless key in @valid_options do
        raise "#{key} is not a valid option"
      end
    end)

    max_attempts = Keyword.get(opts, :max_attempts, 5)
    record_history = Keyword.get(opts, :record_history, false)
    delay = Keyword.get(opts, :delay, &(&1.attempt_num * 10))

    unless is_integer(delay) or is_function(delay, 0) or is_function(delay, 1) do
      raise ":delay must be either an integer or a function with an arity of 0 or 1 (can take the Poller struct)"
    end

    unless is_function(polling_fn, 0) || is_function(polling_fn, 1) do
      raise "The polling function must have an arity of 0 or 1 (can take the Poller struct)"
    end

    unless is_integer(max_attempts) || max_attempts == :infinity || is_function(max_attempts, 0) ||
             is_function(max_attempts, 1) do
      raise ":max_attempts must be either an integer (ms), :infinity, or a function with an arity of 0 or 1 (can take the Poller struct)"
    end

    history = if record_history, do: []

    %Poller{
      config: %Config{
        polling_fn: polling_fn,
        delay: delay,
        max_attempts: max_attempts,
        record_history: record_history
      },
      attempt_num: 0,
      history: history
    }
  end

  @spec poll_once(Poller.t()) :: poll_result()
  def poll_once(%Poller{status: :ok} = poller), do: {:ok, poller}

  def poll_once(%Poller{status: {:error, :retries_exhausted}} = poller),
    do: {:error, :retries_exhausted, poller}

  def poll_once(%Poller{} = poller) do
    poller =
      poller
      |> Map.put(:attempt_num, poller.attempt_num + 1)
      |> then(&Map.put(&1, :total_delay, calculate_total_delay(&1)))
      |> Map.put(:next_delay, nil)

    case handle_config_fn(poller, poller.config.polling_fn) do
      {:ok, value} -> handle_successful_attempt(poller, value)
      :ok -> handle_successful_attempt(poller, nil)
      true -> handle_successful_attempt(poller, nil)
      {:error, value} -> handle_failed_attempt(poller, value)
      :error -> handle_failed_attempt(poller, nil)
      false -> handle_failed_attempt(poller, nil)
      result -> raise InvalidResult, result
    end
  end

  defp handle_successful_attempt(%Poller{} = poller, value) do
    poller =
      poller
      |> Map.put(:value, value)
      |> Map.put(:status, :ok)
      |> record_history()

    {:ok, poller}
  end

  defp handle_failed_attempt(%Poller{} = poller, value) do
    poller = Map.put(poller, :value, value)

    if retryable?(poller) do
      handle_retryable_attempt(poller)
    else
      poller =
        poller
        |> Map.put(:status, {:error, :retries_exhausted})
        |> record_history()

      {:error, :retries_exhausted, poller}
    end
  end

  defp handle_retryable_attempt(%Poller{} = poller) do
    poller =
      poller
      |> Map.put(:status, {:error, :attempt_failed})
      |> then(&Map.put(&1, :next_delay, determine_delay(&1)))
      |> record_history()

    {:error, :attempt_failed, poller}
  end

  defp record_history(%Poller{config: %{record_history: false}} = poller), do: poller

  defp record_history(%Poller{} = poller) do
    current_attempt = %Attempt{
      value: poller.value,
      next_delay: poller.next_delay
    }

    history =
      poller.history
      |> Enum.reverse()
      |> then(&[current_attempt | &1])
      |> Enum.reverse()

    %{poller | history: history}
  end

  defp calculate_total_delay(%Poller{total_delay: total_delay, next_delay: nil}),
    do: total_delay

  defp calculate_total_delay(%Poller{total_delay: total_delay, next_delay: next_delay}),
    do: total_delay + next_delay

  defp determine_delay(%Poller{config: %{delay: ms}}) when is_integer(ms), do: ms

  defp determine_delay(%Poller{config: %{delay: delay_fn}} = poller)
       when is_function(delay_fn),
       do: handle_config_fn(poller, delay_fn)

  defp retryable?(%Poller{attempt_num: attempt_num, config: %{max_attempts: max_attempts}})
       when is_integer(max_attempts),
       do: attempt_num < max_attempts

  defp retryable?(%Poller{config: %{max_attempts: :infinity}}), do: true

  defp retryable?(%Poller{config: %{max_attempts: max_attempts_fn}} = poller)
       when is_function(max_attempts_fn) do
    case handle_config_fn(poller, max_attempts_fn) do
      true -> true
      false -> false
      _ -> raise ":max_attempts must return a boolean"
    end
  end

  defp handle_config_fn(%Poller{} = poller, config_fn) do
    case :erlang.fun_info(config_fn)[:arity] do
      1 -> config_fn.(poller)
      0 -> config_fn.()
      _ -> raise "Function must have an arity of either 0 or 1"
    end
  end
end
