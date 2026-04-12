# Invelion IN-R200 Serial Protocol

Protocol findings from testing the Invelion R200 dev board (purchased from AliExpress). Despite being marketed as "R200", the board identifies as **M100 26dBm V1.0** with firmware **V2.3.5**.

## Connection Settings

| Setting | Value |
|---------|-------|
| Baud rate | 115200 |
| Data bits | 8 |
| Parity | None |
| Stop bits | 1 |
| Flow control | None |
| DTR | **Must be False** |
| RTS | **Must be False** |

**CH340 wake quirk (macOS):** The CH340 USB-to-serial chip on this board requires a brief connection at 9600 baud before switching to 115200. Without this, the device doesn't respond. This may be macOS-specific — test on Linux/Pi to see if it's needed there.

```python
# Wake sequence
ser = serial.Serial(port, 9600, timeout=0.3)
ser.dtr = False
ser.rts = False
time.sleep(0.2)
ser.write(b"\xAA\x00\x03\x00\x00\x03\xDD")  # any valid command
time.sleep(0.2)
ser.read(ser.in_waiting or 128)
ser.close()
time.sleep(0.2)

# Now open at real baud rate
ser = serial.Serial(port, 115200, timeout=1)
ser.dtr = False
ser.rts = False
```

## Frame Format

**This board does NOT use the standard BB/7E framing.** It uses `AA` header and `DD` end marker.

### Command frame (host → reader)

```
AA  type  cmd  len_h  len_l  [params...]  checksum  DD
```

| Field | Size | Description |
|-------|------|-------------|
| Header | 1 | Always `0xAA` |
| Type | 1 | `0x00` = command |
| Command | 1 | Command code |
| Length | 2 | Parameter length (big-endian) |
| Params | variable | Command parameters |
| Checksum | 1 | `sum(type + cmd + len_h + len_l + params) & 0xFF` |
| End | 1 | Always `0xDD` |

### Response frame (reader → host)

```
AA  type  cmd  len_h  len_l  [params...]  checksum  [extra?]  DD
```

| Type value | Meaning |
|------------|---------|
| `0x01` | Response to a command |
| `0x02` | Notification (tag read) |

**Error responses** have `cmd = 0xFF` and a 1-byte error code in params:
- `0x05` = command frame error (wrong header/end marker)
- `0x17` = unknown (possibly wrong end marker)
- `0x15` = no tag found

**Note:** Tag notification frames appear to have 2 bytes between params and end marker (possibly CRC-16 in addition to the 1-byte checksum). For now, find the `DD` end marker to determine frame boundaries rather than relying on length alone.

## Commands

### Get Version (0x03)

```
TX: AA 00 03 00 01 00 04 DD    → hardware version
TX: AA 00 03 00 01 01 05 DD    → firmware version
```

Response params:
- Hardware: `00 4D 31 30 30 20 32 36 64 42 6D 20 56 31 2E 30` = "M100 26dBm V1.0"
- Firmware: `01 56 32 2E 33 2E 35` = "V2.3.5" (first byte is version type)

### Get Region (0x08)

```
TX: AA 00 08 00 00 08 DD
```

Response param (1 byte): region code
- `0x01` = US (902-928 MHz)
- `0x02` = EU (865-868 MHz)
- `0x03` = China (920-925 MHz)
- `0x04` = Korea

### Set Region (0x07)

```
TX: AA 00 07 00 01 02 0A DD    → set to EU (0x02)
```

### Get TX Power (0xB7)

```
TX: AA 00 B7 00 00 B7 DD
```

Response params (2 bytes): power in centidBm, big-endian.
Example: `0A 28` = 2600 = 26.00 dBm

### Set TX Power (0xB6)

```
TX: AA 00 B6 00 02 07 D0 8F DD    → set to 20.00 dBm (0x07D0 = 2000)
```

### Single Inventory (0x22)

```
TX: AA 00 22 00 00 22 DD
```

Tag notification response (type=0x02, cmd=0x22):

```
Params: RSSI(1) + PC(2) + EPC(variable) + CRC(2)
```

- **RSSI**: 1 byte, raw value (higher = stronger signal)
- **PC**: Protocol Control word (2 bytes). Bits 15-11 = EPC length in 16-bit words.
- **EPC**: Tag identifier. Length determined by PC. Typically 12 bytes (96 bits) for standard Gen2 tags.
- **CRC**: 2 bytes, tag-level CRC

After all tags are read, the reader sends a response frame (type=0x01, cmd=0x22) indicating the round is complete.

### Multi/Continuous Inventory (0x27)

```
TX: AA 00 27 00 03 22 FF FF checksum DD
```

Params: `0x22` (inventory sub-command) + repeat count (2 bytes, big-endian). `0xFFFF` = maximum repeats.

Produces the same tag notification frames as single inventory, streaming continuously.

### Stop Inventory (0x28)

```
TX: AA 00 28 00 00 28 DD
```

## Test Results

| Metric | Value |
|--------|-------|
| Read rate | ~36 tags/second (713 reads in 20s, single tag) |
| Tag EPC | `000000000000000000003147` (factory default, 12 bytes) |
| RSSI range | 213-214 (tag held near antenna) |
| Default region | China (0x03), changed to EU (0x02) |
| Default power | 26 dBm (max), set to 20 dBm for testing |
| Max power | 26 dBm |
