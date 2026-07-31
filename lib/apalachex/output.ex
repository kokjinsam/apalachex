defmodule Apalachex.Output do
  @moduledoc false

  @limit 4096

  @spec summary(binary()) :: map()
  def summary(output) when is_binary(output) do
    {tail, truncated?} = tail(output)
    %{"byte_size" => byte_size(output), "tail" => tail, "tail_truncated" => truncated?}
  end

  @spec tail(binary()) :: {String.t(), boolean()}
  def tail(output) when is_binary(output) do
    if String.valid?(output) do
      truncate(output)
    else
      invalid_tail(output)
    end
  end

  defp invalid_tail(output) do
    raw_limit = 1024
    raw_truncated? = byte_size(output) > raw_limit

    raw_tail =
      if raw_truncated? do
        binary_part(output, byte_size(output) - raw_limit, raw_limit)
      else
        output
      end

    {rendered, rendered_truncated?} =
      raw_tail
      |> inspect(binaries: :as_binaries, limit: :infinity, printable_limit: :infinity)
      |> truncate()

    {rendered, raw_truncated? or rendered_truncated?}
  end

  defp truncate(value) when byte_size(value) <= @limit, do: {value, false}

  defp truncate(value) do
    start = byte_size(value) - @limit
    candidate = binary_part(value, start, @limit)
    {align_utf8(candidate), true}
  end

  defp align_utf8(candidate) do
    if String.valid?(candidate) do
      candidate
    else
      <<_byte, rest::binary>> = candidate
      align_utf8(rest)
    end
  end
end
