defmodule ExWaiter.Receiving do
  alias ExWaiter.Receiving.Receiver

  @valid_options [:timeout, :filter, :on_complete]

  def receive(num_messages \\ 1, opts) do
    Enum.each(opts, fn {key, _} ->
      unless key in @valid_options do
        valid_options = @valid_options |> Enum.join(", ")
        raise "#{key} is not a valid option - Valid Options: #{valid_options}"
      end
    end)

    filter_fn = Keyword.get(opts, :filter, fn _message -> true end)

    unless is_function(filter_fn, 1) do
      raise ":filter must be a function with an arity of 1"
    end

    timeout = Keyword.get(opts, :timeout, 100)

    unless is_integer(timeout) || timeout == :infinity do
      raise ":timeout must be either an integer (ms) or :infinity"
    end

    receive_next(%Receiver{
      message_num: 1,
      timeout: timeout,
      remaining_timeout: timeout,
      all_messages: [],
      filtered_messages: [],
      rejected_messages: [],
      num_messages: num_messages,
      filter_fn: filter_fn,
      on_complete: Keyword.get(opts, :on_complete, & &1)
    })
  end

  defp receive_next(
         %Receiver{
           num_messages: num_messages,
           timeout: timeout,
           filter_fn: filter_fn,
           message_num: message_num
         } = receiver
       ) do
    time_before_receive = System.os_time(:millisecond)

    receive do
      msg ->
        receiver = set_remaining_timeout(receiver, time_before_receive)

        case {filter_fn.(msg), message_num == num_messages} do
          {true, true} ->
            receiver = add_message(receiver, :filtered_messages, msg)
            receiver.on_complete.(receiver)
            {:ok, receiver}

          {true, false} ->
            receiver
            |> Map.put(:message_num, message_num + 1)
            |> add_message(:filtered_messages, msg)
            |> receive_next()

          _ ->
            receiver
            |> add_message(:rejected_messages, msg)
            |> receive_next()
        end
    after
      timeout ->
        receiver.on_complete.(receiver)
        {:error, receiver}
    end
  end

  defp set_remaining_timeout(%Receiver{timeout: :infinity} = receiver, _ref_time), do: receiver

  defp set_remaining_timeout(%Receiver{remaining_timeout: remaining_timeout} = receiver, ref_time) do
    time_after_receive = System.os_time(:millisecond)
    remaining_timeout = remaining_timeout - (time_after_receive - ref_time)
    %{receiver | remaining_timeout: remaining_timeout}
  end

  defp add_message(%Receiver{} = receiver, message_list, new_message) do
    receiver
    |> update_message_list(message_list, new_message)
    |> update_message_list(:all_messages, new_message)
  end

  defp update_message_list(%Receiver{} = receiver, message_list, new_message) do
    messages =
      receiver
      |> Map.get(message_list)
      |> Enum.reverse()
      |> then(&[new_message | &1])
      |> Enum.reverse()

    Map.put(receiver, message_list, messages)
  end
end
