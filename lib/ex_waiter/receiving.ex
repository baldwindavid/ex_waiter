defmodule ExWaiter.Receiving do
  alias ExWaiter.Receiving.Receiver

  @valid_options [:timeout]

  @spec receive_next(pos_integer(), Receiver.options()) ::
          {:ok, Receiver.t()} | {:error, Receiver.t()}
  def receive_next(num_messages \\ 1, opts) when is_integer(num_messages) and num_messages > 0 do
    Enum.each(opts, fn {key, _} ->
      unless key in @valid_options do
        valid_options = @valid_options |> Enum.join(", ")
        raise "#{key} is not a valid option - Valid Options: #{valid_options}"
      end
    end)

    timeout = Keyword.get(opts, :timeout, 100)

    unless is_integer(timeout) || timeout == :infinity do
      raise ":timeout must be either an integer (ms) or :infinity"
    end

    do_receive_next(%Receiver{
      message_num: 1,
      timeout: timeout,
      remaining_timeout: timeout,
      messages: [],
      num_messages: num_messages
    })
  end

  defp do_receive_next(
         %Receiver{
           num_messages: num_messages,
           timeout: timeout,
           message_num: message_num
         } = receiver
       ) do
    time_before_receive = System.os_time(:millisecond)

    receive do
      msg ->
        receiver = set_remaining_timeout(receiver, time_before_receive)

        if message_num == num_messages do
          receiver = add_message(receiver, msg)
          {:ok, receiver}
        else
          receiver
          |> Map.put(:message_num, message_num + 1)
          |> add_message(msg)
          |> do_receive_next()
        end
    after
      timeout ->
        {:error, receiver}
    end
  end

  defp set_remaining_timeout(%Receiver{timeout: :infinity} = receiver, _ref_time), do: receiver

  defp set_remaining_timeout(%Receiver{remaining_timeout: remaining_timeout} = receiver, ref_time) do
    time_after_receive = System.os_time(:millisecond)
    remaining_timeout = remaining_timeout - (time_after_receive - ref_time)
    %{receiver | remaining_timeout: remaining_timeout}
  end

  defp add_message(%Receiver{} = receiver, new_message) do
    messages =
      receiver.messages
      |> Enum.reverse()
      |> then(&[new_message | &1])
      |> Enum.reverse()

    Map.put(receiver, :messages, messages)
  end
end
