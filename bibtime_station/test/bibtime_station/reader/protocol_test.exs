defmodule BibtimeStation.Reader.ProtocolTest do
  use ExUnit.Case, async: true

  alias BibtimeStation.Reader.Protocol

  describe "build_frame/2" do
    test "builds the single-inventory command" do
      assert Protocol.single_inventory() == <<0xAA, 0x00, 0x22, 0x00, 0x00, 0x22, 0xDD>>
    end

    test "builds the set-region(:eu) command" do
      # From R200_PROTOCOL.md: AA 00 07 00 01 02 0A DD
      assert Protocol.set_region(:eu) == <<0xAA, 0x00, 0x07, 0x00, 0x01, 0x02, 0x0A, 0xDD>>
    end

    test "builds the set-power(2000) command" do
      # From R200_PROTOCOL.md: AA 00 B6 00 02 07 D0 8F DD
      assert Protocol.set_power(2000) == <<0xAA, 0x00, 0xB6, 0x00, 0x02, 0x07, 0xD0, 0x8F, 0xDD>>
    end

    test "builds the stop-inventory command" do
      assert Protocol.stop_inventory() == <<0xAA, 0x00, 0x28, 0x00, 0x00, 0x28, 0xDD>>
    end

    test "builds multi_inventory(0xFFFF)" do
      frame = Protocol.multi_inventory(0xFFFF)
      # type(0)+cmd(0x27)+len_hi(0)+len_lo(3)+params(0x22, 0xFF, 0xFF)
      # sum = 0x27+3+0x22+0xFF+0xFF = 0x24A → & 0xFF = 0x4A
      assert frame == <<0xAA, 0x00, 0x27, 0x00, 0x03, 0x22, 0xFF, 0xFF, 0x4A, 0xDD>>
    end
  end

  describe "parse_frame/1" do
    test "round-trips a build_frame output" do
      frame = Protocol.set_region(:eu)
      assert {:ok, parsed, <<>>} = Protocol.parse_frame(frame)
      assert parsed.type == 0x00
      assert parsed.cmd == 0x07
      assert parsed.params == <<0x02>>
      assert parsed.raw == frame
    end

    test "parses the version response from R200_PROTOCOL.md" do
      # Response: type=0x01, cmd=0x03, params = "\x00" <> "M100 26dBm V1.0"
      params = <<0x00, 0x4D, 0x31, 0x30, 0x30, 0x20, 0x32, 0x36, 0x64, 0x42, 0x6D, 0x20, 0x56, 0x31, 0x2E, 0x30>>
      pl = byte_size(params)
      body = <<0x01, 0x03, pl::16-big, params::binary>>
      cs = Protocol.checksum(body)
      frame = <<0xAA, body::binary, cs, 0xDD>>

      assert {:ok, parsed, <<>>} = Protocol.parse_frame(frame)
      assert parsed.type == 0x01
      assert parsed.cmd == 0x03
      assert parsed.params == params
    end

    test "parses an error response (no tag found)" do
      # Error response: type=0x01, cmd=0xFF, params = <<0x15>> (no-tag-found).
      body = <<0x01, 0xFF, 0x00, 0x01, 0x15>>
      cs = Protocol.checksum(body)
      bytes = <<0xAA, body::binary, cs, 0xDD>>

      assert {:ok, parsed, <<>>} = Protocol.parse_frame(bytes)
      assert parsed.type == 0x01
      assert parsed.cmd == 0xFF
      assert parsed.params == <<0x15>>
    end

    test "parses a tag notification with no trailer" do
      # PC 0x3000: upper 5 bits = 00110 = 6 words = 12 bytes of EPC
      epc = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x31, 0x47>>
      crc_tag = <<0xAB, 0xCD>>
      params = <<0xD5, 0x30, 0x00>> <> epc <> crc_tag

      pl = byte_size(params)
      body = <<0x02, 0x22, pl::16-big, params::binary>>
      cs = Protocol.checksum(body)
      frame = <<0xAA, body::binary, cs, 0xDD>>

      assert {:ok, parsed, <<>>} = Protocol.parse_frame(frame)
      assert parsed.type == 0x02
      assert parsed.cmd == 0x22

      assert {:ok, %{rssi: 0xD5, epc: epc_hex, pc: 0x3000}} = Protocol.parse_tag(parsed.params)
      assert String.starts_with?(epc_hex, "000000000000000000003147")
    end

    test "parses a tag notification with 1-byte trailer between checksum and DD" do
      epc = <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x31, 0x47>>
      crc_tag = <<0xAB, 0xCD>>
      params = <<0xD5, 0x30, 0x00>> <> epc <> crc_tag
      pl = byte_size(params)
      body = <<0x02, 0x22, pl::16-big, params::binary>>
      cs = Protocol.checksum(body)
      # Insert a bogus 1-byte trailer between checksum and DD.
      frame = <<0xAA, body::binary, cs, 0x99, 0xDD>>

      assert {:ok, parsed, <<>>} = Protocol.parse_frame(frame)
      assert parsed.type == 0x02
      assert byte_size(parsed.raw) == byte_size(frame)
    end

    test "parses two back-to-back frames" do
      a = Protocol.single_inventory()
      b = Protocol.stop_inventory()
      combined = a <> b

      assert {:ok, frame_a, rest1} = Protocol.parse_frame(combined)
      assert frame_a.cmd == 0x22
      assert rest1 == b

      assert {:ok, frame_b, rest2} = Protocol.parse_frame(rest1)
      assert frame_b.cmd == 0x28
      assert rest2 == <<>>
    end

    test "skips leading junk before the header" do
      junk = <<0xFF, 0xFE>>
      frame = Protocol.single_inventory()

      assert {:ok, parsed, <<>>} = Protocol.parse_frame(junk <> frame)
      assert parsed.cmd == 0x22
    end

    test "returns :more when buffer is incomplete" do
      full = Protocol.set_region(:eu)
      half = binary_part(full, 0, 4)

      assert {:more, _} = Protocol.parse_frame(half)
    end
  end

  describe "parse_tag/1" do
    test "extracts rssi, pc, and 12-byte epc" do
      epc = <<0xE2, 0x00, 0x34, 0x12, 0xB7, 0x0C, 0x01, 0x40, 0x00, 0x00, 0x00, 0x00>>
      params = <<0xD5, 0x30, 0x00>> <> epc <> <<0xAA, 0xBB>>

      assert {:ok, tag} = Protocol.parse_tag(params)
      assert tag.rssi == 0xD5
      assert tag.pc == 0x3000
      assert tag.epc == "E2003412B70C014000000000"
    end

    test "returns :error on too-short params" do
      assert :error = Protocol.parse_tag(<<0x01, 0x02>>)
    end
  end
end
