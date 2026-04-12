#!/usr/bin/env python3
"""
R200 RFID Reader — confirmed protocol:
  Header: AA (commands and responses)
  End:    DD
  Frame:  AA type cmd len_h len_l [params...] checksum DD
  Checksum: sum(type + cmd + len_h + len_l + params) & 0xFF

  Response types:
    0x01 = response to command
    0x02 = tag notification

Wave tags near the antenna during continuous inventory!
"""

import serial
import time
import sys

DEVICE = "/dev/cu.usbserial-11330"
BAUD = 115200


def checksum(data):
    return sum(data) & 0xFF


def build_cmd(cmd_byte, params=b""):
    """Build a command frame with AA header and DD end."""
    frame_type = 0x00  # command
    pl = len(params)
    body = bytes([frame_type, cmd_byte, (pl >> 8) & 0xFF, pl & 0xFF]) + params
    cs = checksum(body)
    return bytes([0xAA]) + body + bytes([cs, 0xDD])


def wake_and_connect():
    """Wake CH340 at 9600, then connect at 115200."""
    ser = serial.Serial(DEVICE, 9600, timeout=0.3)
    ser.dtr = False
    ser.rts = False
    time.sleep(0.2)
    ser.write(b"\xAA\x00\x03\x00\x00\x03\xDD")
    time.sleep(0.2)
    ser.read(ser.in_waiting or 128)
    ser.close()
    time.sleep(0.2)

    ser = serial.Serial(DEVICE, BAUD, timeout=1)
    ser.dtr = False
    ser.rts = False
    time.sleep(0.3)
    ser.reset_input_buffer()
    return ser


def send_cmd(ser, cmd_byte, params=b"", label="", wait=0.5):
    frame = build_cmd(cmd_byte, params)
    ser.reset_input_buffer()
    ser.write(frame)
    ser.flush()
    time.sleep(wait)
    resp = ser.read(ser.in_waiting or 512)
    if label:
        print(f"  {label}: TX={frame.hex()} → RX={resp.hex() if resp else '(none)'}")
    return resp


def parse_frames(data):
    """Parse AA-framed responses."""
    frames = []
    buf = bytearray(data)

    while len(buf) >= 7:
        try:
            idx = buf.index(0xAA)
        except ValueError:
            break
        if idx > 0:
            buf = buf[idx:]

        if len(buf) < 5:
            break

        pl = (buf[3] << 8) | buf[4]
        # header(1) + type(1) + cmd(1) + len(2) + params(pl) + checksum(1) + end(1)
        # But we saw 2 bytes between params and end in tag responses.
        # Try to find the DD end marker to determine actual frame length.
        min_len = 5 + pl + 2  # minimum: 1 byte cs + 1 byte end

        # Look for DD at expected positions
        found = False
        for extra in range(3):  # try 1-byte cs, 2-byte cs, 3-byte cs
            check_pos = 5 + pl + extra
            end_pos = check_pos + 1
            if end_pos < len(buf) and buf[end_pos] == 0xDD:
                total = end_pos + 1
                frames.append({
                    "type": buf[1],
                    "cmd": buf[2],
                    "pl": pl,
                    "params": bytes(buf[5:5 + pl]),
                    "trailer": bytes(buf[5 + pl:end_pos]),  # checksum byte(s)
                    "raw": bytes(buf[:total]),
                })
                buf = buf[total:]
                found = True
                break

        if not found:
            # Can't find end marker, might need more data
            break

    return frames


def parse_tag(params):
    """Parse tag data from an inventory notification's params.

    Known format: RSSI(1) + PC(2) + EPC(variable) + CRC(2)
    PC bits 15-11 encode EPC length in 16-bit words.
    """
    if len(params) < 5:
        return None

    rssi_raw = params[0]
    pc = (params[1] << 8) | params[2]
    epc_words = (pc >> 11) & 0x1F
    epc_bytes = epc_words * 2

    if len(params) < 3 + epc_bytes + 2:
        # Try treating remaining bytes as EPC
        epc_bytes = len(params) - 5  # -1 rssi -2 pc -2 crc

    epc = params[3:3 + epc_bytes]
    crc = params[3 + epc_bytes:3 + epc_bytes + 2]

    return {
        "rssi": rssi_raw,
        "pc": f"{pc:04X}",
        "epc": epc.hex().upper(),
        "crc": crc.hex().upper() if crc else "",
    }


def main():
    print("Connecting to R200...")
    ser = wake_and_connect()
    print(f"Connected at {BAUD} baud\n")

    # --- Device info ---
    print("=== Device Queries ===")
    for cmd, params, label in [
        (0x03, b"", "Version"),
        (0x03, b"\x00", "Version(0)"),
        (0x03, b"\x01", "Version(1)"),
        (0xB7, b"", "Get Power"),
        (0x08, b"", "Get Region"),
    ]:
        resp = send_cmd(ser, cmd, params, label)
        if resp:
            for f in parse_frames(resp):
                if f["type"] == 0x01 and f["cmd"] != 0xFF:
                    print(f"    → Response params: {f['params'].hex()}")
                elif f["cmd"] == 0xFF:
                    err = f["params"][0] if f["params"] else "?"
                    print(f"    → Error: 0x{err:02X}" if isinstance(err, int) else f"    → Error: {err}")

    # --- Set region to EU ---
    print("\n=== Configure ===")
    send_cmd(ser, 0x07, bytes([0x02]), "Set Region EU")
    send_cmd(ser, 0xB6, bytes([0x07, 0xD0]), "Set Power 20dBm")

    # --- Single inventory ---
    print("\n" + "=" * 50)
    print("SINGLE INVENTORY — hold a tag near the antenna!")
    print("=" * 50)

    for attempt in range(3):
        time.sleep(1)
        print(f"\n  Poll {attempt + 1}/3...")
        resp = send_cmd(ser, 0x22, b"", wait=1.0)
        if resp:
            frames = parse_frames(resp)
            for f in frames:
                if f["type"] == 0x02 and f["cmd"] == 0x22:
                    tag = parse_tag(f["params"])
                    if tag:
                        print(f"  *** TAG FOUND! ***")
                        print(f"      EPC:  {tag['epc']}")
                        print(f"      RSSI: {tag['rssi']}")
                        print(f"      PC:   {tag['pc']}")
                        print(f"      CRC:  {tag['crc']}")
                elif f["type"] == 0x01:
                    if f["cmd"] == 0xFF:
                        code = f["params"][0] if f["params"] else -1
                        # 0x15 = no tag, 0x05 = frame error
                        if code == 0x15:
                            print(f"  No tags in range")
                        else:
                            print(f"  Response: cmd=0x{f['cmd']:02X} err=0x{code:02X}")
                    elif f["cmd"] == 0x22:
                        print(f"  Inventory round done: {f['params'].hex()}")

    # --- Continuous inventory ---
    print("\n" + "=" * 60)
    print("CONTINUOUS INVENTORY — 20 seconds")
    print("Wave tags near the antenna!")
    print("=" * 60)

    # Multi-poll: cmd 0x27, params: [0x22, repeat_h, repeat_l]
    cmd = build_cmd(0x27, bytes([0x22, 0xFF, 0xFF]))
    ser.reset_input_buffer()
    ser.write(cmd)
    ser.flush()

    tags_seen = {}
    raw_buf = bytearray()
    start = time.time()
    last_status = start

    while time.time() - start < 20:
        chunk = ser.read(ser.in_waiting or 1)
        if not chunk:
            if time.time() - last_status > 3:
                elapsed = time.time() - start
                print(f"  [{elapsed:.0f}s] Listening... "
                      f"({len(tags_seen)} unique tags, "
                      f"{sum(t['count'] for t in tags_seen.values())} total reads)")
                last_status = time.time()
            continue

        raw_buf.extend(chunk)

        # Parse frames from buffer
        while len(raw_buf) >= 7:
            try:
                aa_idx = raw_buf.index(0xAA)
            except ValueError:
                raw_buf.clear()
                break

            if aa_idx > 0:
                raw_buf = raw_buf[aa_idx:]

            if len(raw_buf) < 5:
                break

            pl = (raw_buf[3] << 8) | raw_buf[4]

            # Find DD end marker
            found = False
            for extra in range(3):
                end_pos = 5 + pl + extra + 1
                if end_pos < len(raw_buf) and raw_buf[end_pos] == 0xDD:
                    frame = bytes(raw_buf[:end_pos + 1])
                    raw_buf = raw_buf[end_pos + 1:]

                    cmd_byte = frame[2]
                    frame_type = frame[1]
                    params = frame[5:5 + pl]

                    if cmd_byte == 0x22 and frame_type == 0x02 and pl >= 5:
                        tag = parse_tag(params)
                        if tag and tag["epc"]:
                            epc = tag["epc"]
                            if epc not in tags_seen:
                                elapsed = time.time() - start
                                tags_seen[epc] = {
                                    "rssi": tag["rssi"],
                                    "count": 1,
                                    "first_seen": elapsed,
                                    "pc": tag["pc"],
                                    "crc": tag["crc"],
                                }
                                print(f"  [{elapsed:.1f}s] *** NEW TAG: {epc} "
                                      f"(RSSI: {tag['rssi']}, PC: {tag['pc']}) ***")
                            else:
                                tags_seen[epc]["count"] += 1
                                tags_seen[epc]["rssi"] = tag["rssi"]

                    found = True
                    break

            if not found:
                if len(raw_buf) > 256:
                    raw_buf = raw_buf[-64:]
                break

    # Stop continuous inventory
    stop_cmd = build_cmd(0x28)
    ser.write(stop_cmd)
    time.sleep(0.3)
    ser.read(ser.in_waiting or 256)

    print(f"\n{'=' * 60}")
    print(f"RESULTS: {len(tags_seen)} unique tags")
    print(f"{'=' * 60}")
    for epc, info in tags_seen.items():
        print(f"  EPC:  {epc}")
        print(f"  PC:   {info['pc']}  CRC: {info['crc']}  "
              f"RSSI: {info['rssi']}  Reads: {info['count']}  "
              f"First: {info['first_seen']:.1f}s")
        print()

    if not tags_seen:
        print("  No tags detected.")
        print("  - Is the antenna connected?")
        print("  - Were tags within range?")
        print("  - Try holding a tag directly against the antenna")

    ser.close()
    print("Done.")


if __name__ == "__main__":
    main()
