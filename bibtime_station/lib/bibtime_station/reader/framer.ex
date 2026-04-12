defmodule BibtimeStation.Reader.Framer do
  @moduledoc """
  `Circuits.UART.Framing` implementation for the Invelion/M100 `AA ... DD`
  envelope.

  The framer buffers incoming bytes and, each time `remove_framing/2` is
  called, extracts as many complete frames as it can using
  `BibtimeStation.Reader.Protocol.parse_frame/1`. Incomplete trailing
  bytes are kept in the buffer for the next round.
  """

  @behaviour Circuits.UART.Framing

  alias BibtimeStation.Reader.Protocol

  defmodule State do
    @moduledoc false
    defstruct buffer: <<>>
  end

  @impl true
  def init(_args), do: {:ok, %State{}}

  @impl true
  def add_framing(data, state) when is_binary(data) do
    # Outbound data is already framed by Protocol.build_frame/2.
    {:ok, data, state}
  end

  @impl true
  def remove_framing(data, %State{buffer: buf}) do
    new_buf = buf <> data
    {frames, rest} = extract_all(new_buf, [])
    in_frame? = byte_size(rest) > 0
    {status(in_frame?), frames, %State{buffer: rest}}
  end

  @impl true
  def frame_timeout(%State{buffer: buf}) do
    # Flush whatever partial buffer we have as a "frame" — the Reader can
    # drop it if it doesn't parse.
    {:ok, [buf], %State{buffer: <<>>}}
  end

  @impl true
  def flush(:transmit, %State{} = state), do: state
  def flush(:receive, %State{}), do: %State{buffer: <<>>}
  def flush(:both, %State{}), do: %State{buffer: <<>>}

  defp extract_all(buf, acc) do
    case Protocol.parse_frame(buf) do
      {:ok, frame, rest} ->
        extract_all(rest, [frame.raw | acc])

      {:more, rest} ->
        {Enum.reverse(acc), rest}

      {:error, _} ->
        # Drop buffer on unrecoverable errors.
        {Enum.reverse(acc), <<>>}
    end
  end

  defp status(true), do: :in_frame
  defp status(false), do: :ok
end
