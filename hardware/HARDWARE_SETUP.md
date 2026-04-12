# Hardware Setup — R200 + Raspberry Pi Zero 2 W

Guide for assembling and configuring the RFID timing stations used with BibTime. Each station consists of an Invelion IN-R200 UHF RFID reader development board, a Raspberry Pi Zero 2 W, and a UHF antenna.

---

## Hardware Overview

### Invelion IN-R200 Dev Board

Purchased from Invelion on AliExpress. Key specs from the product listing:

| Spec | Value |
|------|-------|
| Chip | R200 |
| Frequency | EU 865-868 MHz / US 902-928 MHz |
| Read range | 0-20m (depends on tag and antenna) |
| Protocol | EPC Global UHF Class 1 Gen 2 / ISO 18000-6C |
| Interface | USB/TTL (default), TCP/IP, RS-232, Serial (optional) |
| Antenna connector | 1 port, SMA female |
| Power supply | +3.3V-5V |
| Output power | 15 dBm - 26 dBm |
| Working peak current | ~300mA |
| Baud rate | 115200 |
| Host communication | TTL UART / Micro USB |

The dev board exposes TTL UART pads along the bottom edge labeled **`5V3 RXD TXD GND`**, which can be used for direct GPIO connection to a Raspberry Pi.

### UHF Antenna

| Spec | Value |
|------|-------|
| Frequency | 860-960 MHz |
| Gain | 9.2 dBi |
| VSWR | ≤1.3 |
| Polarization | Circular |

Circular polarization is ideal for race timing — tag orientation on the bib doesn't matter.

### Raspberry Pi Zero 2 W

Two micro-USB ports:
- **PWR** (outer edge) — Power only.
- **USB** (inner, closer to HDMI) — USB OTG data port.

---

## Connection Options

There are two ways to connect the R200 to the Pi. Try Option A first since it requires the least extra hardware. Fall back to Option B if the R200 isn't stable on USB power.

### Option A: USB connection (simplest, try first)

The R200's spec says ~300mA peak current. The Pi Zero 2 W's USB OTG port can supply ~500mA, so it may be able to power the R200 directly over USB — data and power on one cable.

```
┌─────────────────┐                                      ┌─────────────────┐
│                  │    ┌──────────┐  USB-A to μUSB       │                 │
│  Pi Zero 2 W    │    │ USB OTG  │  cable (came with    │  R200 Dev Board │
│                USB──►│ adapter  ├──── R200) ──────────►│USB              │
│                  │    │(μUSB→A♀)│                       │                 │
│  PWR             │    └──────────┘                      │  ANT            │
│   │              │                                      │   │             │
└───┼──────────────┘                                      └───┼─────────────┘
    │                                                         │
    ▼                                                         ▼
 Power bank                                              UHF Antenna
 (USB output)                                            (via SMA)
```

**What you need to buy:**
- 3x USB OTG adapters (micro-USB male to USB-A female, ~$3-5 each)

**Assembly:**
1. Flash the Pi's microSD card (see Software section).
2. Connect the antenna to the R200's SMA connector. Hand-tighten. **Never power on the R200 without an antenna connected** — transmitting without a load can damage the RF front-end.
3. Plug the USB OTG adapter into the Pi's **USB** port (the inner one).
4. Connect the R200 using the included USB-A to micro-USB cable: USB-A into the OTG adapter, micro-USB into the R200.
5. Connect the power bank to the Pi's **PWR** port (outer micro-USB).

The R200 appears as `/dev/ttyUSB0` (USB serial device).

**When to switch to Option B:** If you see the R200 resetting during reads, reads failing intermittently at higher power levels, or the Pi reporting USB over-current warnings in `dmesg`, the USB port can't supply enough current and you need separate power.

### Option B: UART + separate power (most robust)

Connect the R200 to the Pi's GPIO UART pins for data, and power the R200 separately through its header pads. This eliminates the USB connection entirely — no OTG adapter needed.

The R200 dev board has TTL UART pads along the bottom edge:

```
R200 board bottom edge (looking at the front with USB on the left):

    ┌──────────────────────────────┐
    │  [USB]          R200    [SMA]│
    │                              │
    └──┤ ┤──┤ ┤──┤ ┤──┤ ┤─────────┘
       5V  RXD  TXD  GND
```

**What you need to buy/have:**
- 3x 4-pin male header strips (2.54mm pitch — standard size, usually included with dev boards)
- 3x USB breakout boards (micro-USB or USB-C, ~$2-3 each — search "USB breakout board" on Amazon/AliExpress)
- DuPont jumper wires, female-to-female (~$3 for a pack of 40)
- A soldering iron (for attaching the header pins to the R200 board)

**Wiring:**

```
                    DuPont jumper wires
┌──────────────┐                          ┌──────────────┐
│ Pi Zero 2 W  │                          │ R200 Board   │
│              │                          │              │
│  GPIO 14 (TXD) ─────────────────────── RXD             │
│  GPIO 15 (RXD) ─────────────────────── TXD             │
│  GND ───────────────────────────────── GND             │
│              │                          │ 5V ◄──┐      │
│  PWR         │                          │  ANT  │      │
│   │          │                          │   │   │      │
└───┼──────────┘                          └───┼───┼──────┘
    │                                         │   │
    ▼                                         ▼   │
 Power bank                             Antenna   │
 output 1                                         │
 (micro-USB)                                      │
                                                  │
    Power bank ──► USB breakout board ──5V, GND───┘
    output 2       (USB → bare pins)
```

**Assembly:**
1. **Solder the header pins** onto the R200 board's bottom pads (5V, RXD, TXD, GND). This is straightforward through-hole soldering.
2. Connect the antenna to the R200's SMA connector.
3. Wire R200 **TXD** → Pi **GPIO 15** (RXD / physical pin 10)
4. Wire R200 **RXD** → Pi **GPIO 14** (TXD / physical pin 8)
5. Wire R200 **GND** → Pi **GND** (physical pin 6)
6. Plug a USB cable from the power bank into the USB breakout board. Wire the breakout's **5V** and **GND** to the R200's **5V** and **GND** header pins.
7. Plug the power bank's other output into the Pi's **PWR** port.

The R200 appears as `/dev/serial0` (Pi hardware UART). You'll need to enable the hardware UART on the Pi — see the Software section.

**Why this option is better for field use:**
- Each device gets its own dedicated power from the power bank (no current sharing)
- UART is simpler and more reliable than USB serial for embedded use
- Fewer cables and adapters (no OTG adapter, no USB cable between the boards)
- The Pi's USB port stays free

---

## Power (Race Day)

Both options can run from a **single dual-output USB power bank**.

| Device | Draw | 8-hour estimate |
|--------|------|-----------------|
| Pi Zero 2 W | ~400-500mA | ~4,000 mAh |
| R200 (reading) | ~300mA peak | ~2,400 mAh |
| **Total** | **~800mA** | **~6,400 mAh** |

A **10,000 mAh power bank** with dual USB output gives comfortable margin for a full race day. A 20,000 mAh bank would last a weekend.

**Note:** Some power banks shut off when current draw is too low (they think nothing is connected). The R200 + Pi together should draw enough to keep most banks awake, but if yours shuts off, look for a power bank with a "low-current mode" or "always-on" feature.

---

## Antenna Placement

- **Position** the antenna at chest height pointing perpendicular to the direction of athlete travel, or aimed at the ground if using a mat-style setup.
- **Read range** with the 9.2 dBi antenna at full power: expect 3-10 meters depending on tag type. Start with lower power and increase until you get reliable reads at the desired distance.
- **Circular polarization** means you don't need to worry about matching antenna orientation to tag orientation — reads work regardless of how the bib tag is rotated.
- **Avoid metal surfaces** directly behind or beside the antenna — they create reflections and dead zones.

---

## Software Setup (Raspberry Pi)

### 1. Flash Raspberry Pi OS

Use **Raspberry Pi Imager** to flash **Raspberry Pi OS Lite (64-bit)** onto the microSD card.

In the imager's settings (gear icon), configure:
- **Hostname:** e.g. `timing-station-1` (use 1, 2, 3 for your three stations)
- **Enable SSH:** Yes (use password or add your public key)
- **WiFi:** Enter your WiFi SSID and password
- **Locale:** Set timezone and keyboard layout

Insert the card into the Pi and power it on. It should connect to your WiFi within a minute.

### 2. Find the Pi on your network

```bash
# From your laptop, on the same WiFi network:
ping timing-station-1.local

# Or scan the network:
arp -a | grep -i "b8:27:eb\|dc:a6:32\|d8:3a:dd\|2c:cf:67"
```

### 3. SSH in and update

```bash
ssh pi@timing-station-1.local

# On the Pi:
sudo apt update && sudo apt upgrade -y
```

### 4. Install dependencies

```bash
sudo apt install -y python3-pip python3-venv git
```

### 5. Enable hardware UART (Option B only)

If using the UART/GPIO connection (Option B), you need to enable the Pi's hardware UART and disable the serial console:

```bash
# Disable serial console (frees up the UART for our use)
sudo raspi-config nonint do_serial_hw 0   # Enable hardware UART
sudo raspi-config nonint do_serial_cons 1  # Disable console on serial

# Reboot for changes to take effect
sudo reboot
```

After reboot, the UART is available at `/dev/serial0`.

### 6. Verify the R200 is detected

**Option A (USB):**
```bash
# Check for USB serial device:
ls /dev/ttyUSB* /dev/ttyACM*
# Should show /dev/ttyUSB0

# Check dmesg for USB device recognition:
dmesg | grep -i usb | tail -10
```

**Option B (UART):**
```bash
# Check that the serial port exists:
ls -l /dev/serial0
# Should be a symlink to /dev/ttyAMA0 or /dev/ttyS0
```

### 7. Install the Mercury API Python library

The R200 uses the **Mercury API** protocol (not LLRP). The best Python binding is `python-mercuryapi`:

```bash
# Create a project directory
mkdir -p ~/timing && cd ~/timing
python3 -m venv venv
source venv/bin/activate

# Install mercury-api (Python wrapper for ThingMagic's Mercury API)
pip install mercury-api
```

> **Note:** If `mercury-api` fails to install (it has C dependencies), you may need to build from source. See https://github.com/gotthardp/python-mercuryapi for build instructions. You'll need `sudo apt install -y build-essential` and potentially the ThingMagic Mercury API C SDK.

### 8. Test reading tags

Create a test script `~/timing/test_read.py`:

```python
#!/usr/bin/env python3
"""Quick test: read any UHF tags in range of the R200."""

import mercury

# Option A (USB): use the USB serial device
reader = mercury.Reader("tmr:///dev/ttyUSB0")

# Option B (UART): use the hardware UART instead
# reader = mercury.Reader("tmr:///dev/serial0", baudrate=115200)

# Set the region (EU for Sweden)
reader.set_region("EU3")

# Set read power in centidBm (e.g., 2000 = 20.00 dBm)
# Start low for testing, increase for longer range
reader.set_read_plan([1], "GEN2", read_power=2000)

print("Reading tags for 5 seconds...")
tags = reader.read(timeout=5000)

for tag in tags:
    print(f"  EPC: {tag.epc.hex()}  RSSI: {tag.rssi}  Count: {tag.read_count}")

if not tags:
    print("  No tags detected. Check antenna connection and tag proximity.")

print("Done.")
```

Run it:

```bash
cd ~/timing
source venv/bin/activate
python3 test_read.py
```

### 9. Reader service (sends reads to BibTime)

This is the service that will run continuously during a race, reading tags and sending them to the BibTime server. We'll build this out in a later phase — the architecture will be:

```
R200 ──serial──► Pi (reader service) ──WiFi/HTTP──► BibTime server
                     │
                     └── local buffer (SQLite)
                         in case WiFi drops
```

The reader service will:
1. Continuously read tags from the R200
2. Deduplicate reads (same tag within N seconds = one read)
3. POST each read to BibTime's chip read API endpoint
4. Buffer reads locally if the network is unavailable, and retry when it comes back

---

## Power Button

Wire a momentary push button between **GPIO3** (physical pin 5) and **GND** (physical pin 6) on the Pi's header. These two pins are adjacent, so it's a simple two-wire connection.

```
Pi Zero 2 W GPIO header (pins 1-10):

  3V3  (1) (2)  5V
  SDA  (3) (4)  5V
  SCL  (5) (6)  GND    ◄── button wire 2
       ...
```

Pin 5 is GPIO3 (SCL). Pin 6 is GND. Connect one leg of the button to each.

The `gpio-shutdown` device tree overlay (added by the provisioning script) makes this work:

- **Press while running** — triggers a clean `shutdown -h now`
- **Press while halted** — wakes the Pi back up (GPIO3 doubles as the hardware wake pin)

No software or code changes needed. The overlay is configured in `/boot/firmware/config.txt`:

```
dtoverlay=gpio-shutdown,gpio_pin=3
```

If using a weatherproof enclosure, mount the button so it's accessible from outside the box.

---

## Troubleshooting

### Pi won't connect to WiFi
- Re-flash the SD card and double-check the WiFi credentials in Raspberry Pi Imager
- Make sure you're using 2.4 GHz WiFi — the Pi Zero 2 W does not support 5 GHz

### R200 not detected (`/dev/ttyUSB0` missing, Option A)
- Check USB cable and OTG adapter connections
- Try `dmesg | grep -i usb` to see if the device is recognized at all
- Make sure the R200 has power (LED on the dev board should be lit)
- Try a different USB cable — some micro-USB cables are charge-only (no data lines)

### R200 not responding on UART (Option B)
- Verify UART is enabled: `ls -l /dev/serial0` should exist
- Check wiring: TXD↔RXD must be **crossed** (R200 TXD to Pi RXD, and vice versa)
- Verify the R200 has power (LED on dev board lit)
- Check baud rate is 115200

### "No tags detected" when running test script
- Ensure the antenna is connected before powering on the R200
- Move a tag very close to the antenna (within 10cm) for initial testing
- Increase read power: try `read_power=2500` or `read_power=2700`
- Check that you're using UHF Gen2 / RAIN RFID tags (not HF/NFC tags)
- Verify the region setting matches your country's UHF frequency band

### Permission denied on serial port
```bash
sudo usermod -a -G dialout $USER
# Then log out and back in, or reboot
```

### R200 resets or reads fail intermittently (Option A)
This means the Pi's USB port can't supply enough current. Switch to Option B (UART + separate power).

### Power bank keeps shutting off
Some banks have a minimum current threshold. The Pi + R200 together draw ~800mA which should be enough, but if yours shuts off, look for banks with a "low-current" or "always-on" mode.

---

## Shopping List

### Minimum (to test with Option A)
- 3x USB OTG adapters (micro-USB male to USB-A female) — ~$3-5 each
- 3x microSD cards (16 GB+) — ~$5-8 each
- 1x USB power bank (10,000+ mAh, dual output) — for testing

### If switching to Option B
- 3x 4-pin male header strips (2.54mm pitch)
- 3x USB breakout boards (micro-USB or USB-C to bare pins) — ~$2-3 each
- 1x pack DuPont jumper wires (female-to-female) — ~$3
- Soldering iron + solder

### For race day deployment (3 stations)
- 3x USB power banks (10,000-20,000 mAh, dual output) — ~$15-30 each
- 3x weatherproof enclosures (IP65, big enough for Pi + R200 + power bank) — ~$10-15 each
- Mounting hardware (tripod or pole clamp for antenna) — varies
