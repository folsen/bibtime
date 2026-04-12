defmodule BibtimeStation.Reader.Protocol do
  @moduledoc """
  Pure functions for the Invelion IN-R200 / M100 serial protocol.

  Frame format (non-standard):

      AA  type  cmd  len_h  len_l  [params...]  checksum  [1-2 trailer]  DD

  * Header byte: `0xAA`
  * End marker:  `0xDD`
  * Type: `0x00` = command, `0x01` = response, `0x02` = notification
  * Checksum: `sum(type + cmd + len_h + len_l + params) & 0xFF`

  Tag notification frames (`type=0x02 cmd=0x22`) carry an additional
  (probably CRC-16) byte or two between the checksum and the `DD` end
  marker, so the parser always locates the `DD` marker explicitly
  rather than trusting the length field alone.

  See `hardware/R200_PROTOCOL.md` for the full protocol description.
  """

  import Bitwise

  @header 0xAA
  @end_marker 0xDD
  @type_command 0x00

  @doc "Build a command frame for the given command byte and (optional) parameters."
  @spec build_frame(byte(), binary()) :: binary()
  def build_frame(cmd_byte, params \\ <<>>) when is_integer(cmd_byte) and is_binary(params) do
    pl = byte_size(params)
    body = <<@type_command, cmd_byte, pl::16-big, params::binary>>
    cs = checksum(body)
    <<@header, body::binary, cs, @end_marker>>
  end

  @doc "Set the reader's operating region. `0x07`."
  def set_region(region) do
    code =
      case region do
        :us -> 0x01
        :eu -> 0x02
        :cn -> 0x03
        :kr -> 0x04
      end

    build_frame(0x07, <<code>>)
  end

  @doc "Set TX power in centi-dBm (e.g. 2000 = 20.00 dBm). `0xB6`."
  def set_power(centidbm) when is_integer(centidbm) and centidbm >= 0 and centidbm <= 0xFFFF do
    build_frame(0xB6, <<centidbm::16-big>>)
  end

  @doc "Get firmware/hardware version. `0x03`. `kind` :hardware | :firmware."
  def get_version(kind \\ :hardware)
  def get_version(:hardware), do: build_frame(0x03, <<0x00>>)
  def get_version(:firmware), do: build_frame(0x03, <<0x01>>)

  @doc "Get current TX power. `0xB7`."
  def get_power, do: build_frame(0xB7)

  @doc "Get region. `0x08`."
  def get_region, do: build_frame(0x08)

  @doc "Trigger a single inventory round. `0x22`."
  def single_inventory, do: build_frame(0x22)

  @doc """
  Start a multi/continuous inventory. `0x27`.

  `repeat_count` is big-endian 16-bit; `0xFFFF` means effectively forever.
  """
  def multi_inventory(repeat_count)
      when is_integer(repeat_count) and repeat_count >= 0 and repeat_count <= 0xFFFF do
    build_frame(0x27, <<0x22, repeat_count::16-big>>)
  end

  @doc "Stop any running inventory. `0x28`."
  def stop_inventory, do: build_frame(0x28)

  @doc """
  Incremental frame parser.

  Given a buffer of bytes, attempts to extract the next complete frame.
  Returns:

    * `{:ok, frame, rest}` — one frame parsed, rest of the buffer returned
    * `{:more, buffer}`    — need more bytes (buffer may have leading junk
      stripped up to the next `0xAA`)
    * `{:error, reason}`   — malformed frame that the caller cannot recover
      from; the caller should drop the buffer
  """
  @spec parse_frame(binary()) ::
          {:ok, map(), binary()} | {:more, binary()} | {:error, term()}
  def parse_frame(<<>>), do: {:more, <<>>}

  def parse_frame(buf) when is_binary(buf) do
    case :binary.match(buf, <<@header>>) do
      :nomatch ->
        {:more, <<>>}

      {idx, _} ->
        rest = binary_part(buf, idx, byte_size(buf) - idx)

        case parse_from_header(rest) do
          {:ok, frame, tail} ->
            {:ok, frame, tail}

          {:more, _} = more ->
            more

          {:bad_frame, skip} ->
            # Skip the leading AA and try again with the remainder.
            remainder = binary_part(rest, skip, byte_size(rest) - skip)
            parse_frame(remainder)
        end
    end
  end

  # Precondition: buf starts with 0xAA.
  defp parse_from_header(<<@header, type, cmd, len_h, len_l, rest::binary>> = buf) do
    pl = len_h * 256 + len_l

    if byte_size(rest) < pl + 2 do
      # Not enough bytes yet for even the minimum tail (params + cs + DD).
      {:more, buf}
    else
      <<params::binary-size(pl), after_params::binary>> = rest
      find_end(type, cmd, params, after_params, buf)
    end
  end

  defp parse_from_header(buf), do: {:more, buf}

  # After the params we expect: checksum (1 byte) + 0-2 trailer bytes + DD.
  # Try trailer widths 0, 1, 2.
  #
  # Returns:
  #   {:ok, frame, rest}        — frame parsed
  #   {:more, original_buf}     — need more bytes
  #   {:bad_frame, skip}        — checksum never matched; skip `skip` bytes
  defp find_end(type, cmd, params, after_params, original_buf) do
    body = <<type, cmd, byte_size(params)::16-big, params::binary>>
    expected_cs = checksum(body)
    scan_widths(0, type, cmd, params, after_params, original_buf, expected_cs, false)
  end

  defp scan_widths(extra, _type, _cmd, _params, _after_params, original_buf, _cs, needed_more?)
       when extra > 2 do
    if needed_more?, do: {:more, original_buf}, else: {:bad_frame, 1}
  end

  defp scan_widths(extra, type, cmd, params, after_params, original_buf, expected_cs, needed_more?) do
    tail_len = 1 + extra + 1

    if byte_size(after_params) < tail_len do
      # Can't decide at this width — need more bytes.
      scan_widths(extra + 1, type, cmd, params, after_params, original_buf, expected_cs, true)
    else
      <<cs, _trailer::binary-size(extra), end_byte, rest::binary>> = after_params

      if end_byte == @end_marker and cs == expected_cs do
        frame_total = 5 + byte_size(params) + tail_len
        raw = binary_part(original_buf, 0, frame_total)
        frame = %{type: type, cmd: cmd, params: params, raw: raw}
        {:ok, frame, rest}
      else
        scan_widths(extra + 1, type, cmd, params, after_params, original_buf, expected_cs, needed_more?)
      end
    end
  end

  @doc """
  Parse the params of a tag notification (type=0x02, cmd=0x22).

  Format: `RSSI(1) + PC(2) + EPC(variable) + CRC(2)`.

  The EPC length is encoded in the upper 5 bits of PC as a 16-bit
  word count (typically 6 words = 12 bytes).
  """
  @spec parse_tag(binary()) :: {:ok, %{rssi: non_neg_integer(), pc: non_neg_integer(), epc: String.t()}} | :error
  def parse_tag(<<rssi, pc::16-big, rest::binary>>) do
    epc_words = pc |> bsr(11) |> band(0x1F)
    epc_bytes = epc_words * 2

    cond do
      epc_bytes > 0 and byte_size(rest) >= epc_bytes ->
        <<epc::binary-size(epc_bytes), _crc_or_more::binary>> = rest
        {:ok, %{rssi: rssi, pc: pc, epc: Base.encode16(epc)}}

      # Fallback: no EPC length info — assume everything but a trailing CRC is EPC.
      byte_size(rest) >= 2 ->
        fallback = byte_size(rest) - 2
        <<epc::binary-size(fallback), _crc::binary-size(2)>> = rest
        {:ok, %{rssi: rssi, pc: pc, epc: Base.encode16(epc)}}

      true ->
        :error
    end
  end

  def parse_tag(_), do: :error

  @doc false
  @spec checksum(binary()) :: byte()
  def checksum(body) when is_binary(body) do
    body
    |> :binary.bin_to_list()
    |> Enum.sum()
    |> Bitwise.band(0xFF)
  end
end
