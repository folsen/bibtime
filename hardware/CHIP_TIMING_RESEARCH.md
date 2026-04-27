# Chip Timing Systems Research — BibTime

Research into available timing hardware for integration with BibTime, focusing on systems suitable for small-to-medium triathlon and endurance race organizers in Sweden/Nordics. Covers both professional RFID systems and low-cost alternative approaches.

---

## Summary & Recommendation

The right system depends on budget and accuracy needs. For professional-grade timing, the **UHF RFID / LLRP route** remains the strongest fit — open protocol, pluggable adapter architecture, thriving ecosystem. For small events where ±1–3 second accuracy is acceptable and budget is tight, **BLE beacons with ESP32 scanners** offer the best cost-to-value ratio with a fully DIY-friendly stack.

### Professional RFID Systems

| Priority | System | Est. Cost | Protocol | BibTime Fit |
|----------|--------|-----------|----------|-------------|
| 1st | UHF RFID (Impinj/LLRP) | ~$1,500–2,750 | LLRP (open) | Excellent — open standard, cheap tags |
| 2nd | Race Result | ~$5,000+ | TCP/IP + HTTP API | Very good — documented API, active transponders |
| 3rd | DIY / AliExpress UHF | ~$200–500 | Varies (often LLRP) | Good for prototyping, quality varies |
| 4th | MYLAPS BibTag | ~$4,000+ | Proprietary TCP/IP | Decent — industry standard but closed protocol |
| 5th | ChronoTrack | Contact vendor | Proprietary | Moderate — ecosystem is more service-oriented |
| 6th | Innovative Timing (Jaguar) | ~$3,999+ | Proprietary | Moderate — self-contained, less open |
| 7th | J-Chip | Scarce availability | Serial/TCP | Low — legacy, hard to source |

### Low-Cost Alternatives (outside RFID)

| Priority | System | Est. Cost (100 athletes, 5 splits) | Accuracy | BibTime Fit |
|----------|--------|-------------------------------------|----------|-------------|
| 1st | BLE Beacons + ESP32 | ~$1,000–1,650 | ±1–3s | Excellent — WiFi/MQTT to GenServer adapter |
| 2nd | Camera + CV Bib OCR | ~$200–500 | ±1–5s | Good — batch or near-real-time post-processing |
| 3rd | NFC/QR Tap + Phones | ~$10–50 | ±2–5s | Good — zero infrastructure, needs volunteers |
| 4th | LoRa GPS Trackers | ~$2,700–5,200 | ±5–20s | Moderate — better as live tracking supplement |
| 5th | Hybrid (BLE + Manual) | ~$900–1,700 | ±1–3s (auto), exact (finish) | Excellent — practical best-of-both approach |

---

## 1. UHF RFID with LLRP (Impinj, Zebra)

**Best choice for BibTime integration.** LLRP (Low Level Reader Protocol) is an open RAIN RFID standard, meaning your adapter code works across hardware vendors.

### How it works
Passive UHF RFID tags (860–960 MHz) are attached to bibs or shoes. Readers with ground mat antennas detect tags as athletes pass over them. Reads are timestamped by the reader and streamed to software via LLRP over Ethernet.

### Hardware

| Component | Options | Approx. Price |
|-----------|---------|---------------|
| Reader (4-port) | Impinj Speedway R420 (legacy), Impinj R700 (current) | $1,000–2,000 |
| Reader (2-port) | Impinj R220 (budget/clearance) | $500–1,000 |
| Reader (budget) | Zebra FX9600 (formerly Motorola) | $1,000–1,500 |
| Ground mat antenna | Times-7 SlimLine RTAS, or panel antennas on tripods | $130–500 each |
| Passive UHF tags | Disposable bib tags or shoe tags | $0.10–0.50 per tag |
| Cables & mounts | RF cables, tripods, pole mount brackets | ~$100–200 per antenna |

**Minimum viable system:** 1 reader + 2 antennas + tags ≈ **$1,500–2,000**
**Full triathlon setup (5 split points):** Multiple readers + antennas ≈ **$8,000–15,000**

### Where to buy
- **Atlas RFID Store** (atlasrfidstore.com) — US-based, ships internationally, partners with timing software vendors
- **RFID4U Store** (rfid4ustore.com) — Impinj readers and accessories
- **AliExpress** — Budget readers and antennas (search "UHF RFID race timing")
- **Times-7** (times-7.com) — Professional race timing antennas (SlimLine RTAS)

### Software compatibility
- **CrossMgr** — Open-source, explicit LLRP support via CrossMgrImpinj module
- **PikaTimer** — Open-source race timing (GitHub)
- **Webscorer PRO** — Commercial, works with Impinj R420 via LLRP
- **BibTime (your adapter)** — LLRP is well-documented; Elixir can speak TCP to the reader

### Pros
- Open protocol — no vendor lock-in
- Cheapest per-tag cost ($0.10–0.50 disposable)
- Large ecosystem of compatible hardware
- Well-suited to BibTime's GenServer adapter pattern

### Cons
- Passive tags have lower accuracy (~0.2s) vs active systems (~0.004s)
- Requires more setup and tuning (antenna placement, reader sensitivity)
- Ground mats need protection from vehicles/weather

---

## 2. Race Result

**Premium option with the best-documented API.** Used at professional events worldwide, with both active and passive transponder options.

### How it works
Active transponders transmit their own signal to a decoder (now called "Ubidium"). The decoder timestamps reads and pushes data via TCP/IP or HTTP API to scoring software in real time.

### Hardware

| Component | Notes | Approx. Price |
|-----------|-------|---------------|
| Ubidium decoder | Replaces the older Decoder 5000S. 3.6 kg, foldable ground antenna, hot-swappable batteries (up to 32h) | Contact vendor |
| ActiveBasic transponder | Budget active transponder, no tracking/store mode | Contact vendor (est. $15–30 each) |
| ActivePro transponder | High accuracy, store mode, tracking. Recommended for most events | Contact vendor (est. $30–50 each) |
| Passive transponders | Lower cost, ~0.2s accuracy | Contact vendor |
| Complete active system | Decoder + antenna + transponders | ~$5,400+ |

### Where to buy
- **Race Result direct** (raceresult.com/en/shop) — Active transponder shop and system shop
- Contact Race Result sales for a tailored quote — they advise personally based on event needs

### Pros
- Extremely high accuracy (0.004s with active transponders)
- 100% waterproof active transponders — ideal for triathlon swim legs
- Well-documented HTTP API — strong fit for BibTime's adapter
- Active transponders are reusable for years
- Built-in 4G connectivity on decoder

### Cons
- Higher upfront cost (~$5,000+ for a starter system)
- Active transponders are expensive per-unit (need to collect and reuse)
- Pricing not publicly listed — must contact sales

---

## 3. MYLAPS BibTag

**Industry standard for large running events.** Proprietary but extremely reliable with >99.8% detection rate.

### How it works
Disposable "ThinTag" UHF chips are integrated into race bibs. BibTag Smart Decoders with detection mats read the chips as athletes cross timing points. Data streams via proprietary TCP/IP protocol.

### Hardware

| Component | Notes | Approx. Price |
|-----------|-------|---------------|
| BibTag Smart Decoder | 7.2 kg, 0.01s resolution, >99.8% detection | ~$4,000+ (used/resale) |
| Detection mat | Modular, 1–8m per decoder | ~$400+ each |
| ThinTags (disposable) | Single-use UHF tags for bibs | Contact vendor |

### Where to buy
- **MYLAPS SpeedHive Shop** (speedhiveshop.mylaps.com) — Official accessories and transponders
- **MYLAPS direct** (mylaps.com) — Contact for decoder pricing and proposals
- **FinishLynx** (finishlynx.com) — Resells MYLAPS BibTag decoders
- **TimingGuys** (timingguys.com) — Occasionally lists used systems for sale
- **HS Sports UK** (hssports.co.uk) — European reseller

### Pros
- Industry standard with huge install base
- Very high detection rate (>99.8%)
- Scales from small 5K to major marathons
- Disposable tags — no collection logistics

### Cons
- Proprietary protocol — will require reverse-engineering or documentation request for BibTime adapter
- Expensive decoder hardware
- Per-race tag costs add up
- Less transparent pricing

---

## 4. ChronoTrack (Athlinks)

**Service-oriented ecosystem** primarily aimed at timing companies rather than DIY race organizers.

### How it works
Passive UHF B-tags (bib), D-tags (shoe), or Tri Tags are read by ChronoTrack controllers and ground antennas. Data flows into their proprietary scoring software.

### Hardware
- Controllers, mats, and antennas available through ChronoTrack
- Passive tags are disposable and weather-resistant
- AeroTrack is their newest controller

### Where to buy
- **ChronoTrack / Athlinks Services** (services.athlinks.com, chronotrack.com) — Direct sales, primarily to timing companies

### Pros
- Proven at massive events (LA Marathon, etc.)
- Tri-specific tag options
- Professional support ecosystem

### Cons
- More of a "timing company" product than a self-hosted tool
- Proprietary software ecosystem — harder to integrate with BibTime
- Pricing not publicly available

---

## 5. Innovative Timing Systems (Jaguar)

**All-in-one system** with integrated timing clock + RFID reader.

### Hardware

| Component | Notes | Approx. Price |
|-----------|-------|---------------|
| Jaguar G4 | Integrated system, weatherproof (-25F to +140F), ideal for smaller events | Starting at $3,999 |

### Where to buy
- **Innovative Timing Systems** (innovativetimingsystems.com) — Direct purchase

### Pros
- Rugged, all-weather design
- All-in-one simplicity
- Good for smaller events

### Cons
- Proprietary system
- Less suited to multi-split triathlon setups
- Limited integration documentation for custom software

---

## 6. DIY / Budget UHF RFID (AliExpress, Arduino)

**Cheapest entry point** for prototyping and small events.

### Options

| Approach | Components | Approx. Price |
|----------|-----------|---------------|
| AliExpress complete kit | UHF reader + ground mat antenna + tags + free software | ~$200–500 |
| SparkFun Simultaneous RFID | Reader board + antennas + Arduino/Raspberry Pi | ~$200–400 |
| Used enterprise readers | Motorola XR series, Impinj R1000 (discontinued) | ~$150–300 |

### Where to buy
- **AliExpress** — Search "RFID race timing system UHF" or "sports timing RFID"
- **SparkFun** (sparkfun.com) — Simultaneous RFID Reader + breakout boards
- **eBay** — Used/refurbished enterprise readers

### Pros
- Extremely low cost
- Good for learning and prototyping your BibTime adapter
- Some kits include basic timing software

### Cons
- Variable quality and documentation
- Lower read reliability than professional systems
- May not support LLRP (some use proprietary protocols)
- Not suitable for serious race operations without extensive testing

---

## 7. J-Chip

**Legacy system**, still seen in Nordic countries but increasingly hard to source.

### How it works
Active RFID chips communicate with receivers over serial or TCP. Older technology but proven in Nordic ski and running events.

### Where to buy
- **Jon Rosen Systems** (jonrosensystems.com) — Special order, limited availability
- Contact Nordic timing companies that may have used equipment

### Pros
- Proven in Nordic conditions
- Active chip accuracy

### Cons
- Essentially discontinued / scarce
- Limited documentation for custom integration
- Not recommended for new projects

---

---

# Part 2 — Low-Cost Alternatives (Outside RFID)

For small venues where ±1–5 second accuracy is acceptable and budget is limited, several approaches avoid the cost and complexity of traditional RFID infrastructure entirely. These are particularly relevant for community triathlons, club events, and training races where the top finishers can be verified by a judge at the finish line.

---

## 8. BLE Beacons + ESP32 Scanners

**Best low-cost automated option.** Each athlete wears a small BLE beacon; cheap ESP32 microcontrollers at each timing point listen for beacon advertisements and timestamp them.

### How it works
A BLE beacon (such as an ESP32-C3 or nRF52-based tag) continuously broadcasts its unique ID at a configurable interval (e.g., every 200ms–1s). At each timing point, an ESP32 running in scanner mode detects the beacon's advertisement, records the tag ID and a timestamp, and reports the read to BibTime over WiFi, MQTT, or local storage.

The detection zone is roughly 10–30 meters depending on transmit power, so athletes are "seen" as they pass through a zone rather than crossing a precise line. For ±1–3 second accuracy at a triathlon split point, this is more than sufficient.

### Hardware

| Component | Options | Approx. Price |
|-----------|---------|---------------|
| Athlete beacon | Seeed XIAO ESP32-C3, or nRF52832-based BLE beacon (e.g., Minew C6/C8) | $5–15 each |
| Checkpoint scanner | ESP32-DevKitC or ESP32-S3 board | $7–15 each |
| Battery for beacon | CR2032 coin cell (months of life) or small LiPo | $0.50–3 each |
| Battery for scanner | USB power bank (10,000 mAh lasts a full race day) | $10–20 each |
| Weatherproof enclosure | Small IP65 box for scanner + power bank | $5–10 each |
| Networking (per scanner) | Phone hotspot (free), or GL.iNet 4G travel router | $0–40 each |

**Per-athlete cost:** ~$8–15 (reusable beacon + coin cell)
**Per-checkpoint cost:** ~$25–80 (scanner + power + enclosure + networking)
**Full triathlon (100 athletes, 5 splits):** ~$1,000–1,650

### Where to buy
- **Seeed Studio** (seeedstudio.com) — XIAO ESP32-C3 (~$5), ESP32-S3 (~$8)
- **AliExpress** — ESP32-DevKitC boards (~$4–7), BLE beacon tags (~$3–8)
- **Minew** (minew.com) — Professional BLE beacons (C6, C8 series) with cases and batteries included
- **Mouser / DigiKey** — nRF52 modules, ESP32 boards, coin cell holders
- **Amazon** — USB power banks, IP65 enclosures, USB cables

### Open-source references
- **BLE_Timing_System** (github.com/omrijsharon/BLE_Timing_System) — ESP32-based BLE race timing
- **ESPresense** (espresense.com) — ESP32 BLE presence detection framework, adaptable for timing

### BibTime adapter concept
An ESP32 scanner could push reads to BibTime via HTTP POST or MQTT. The adapter (`BibTime.Timing.Adapters.BLE`) would run a small MQTT subscriber or HTTP listener GenServer, receiving JSON payloads like `{"beacon_id": "AA:BB:CC:DD:EE:FF", "rssi": -45, "timestamp": 1710500000123}` and converting them into standard `%ChipRead{}` structs. Duplicate filtering would discard repeated reads of the same beacon within a configurable window (e.g., 30 seconds).

### Pros
- Extremely low cost — both per-athlete and per-checkpoint
- No coax cables, no expensive decoders, no ground mats
- ESP32 is well-documented with a huge community
- Beacons are reusable for hundreds of races
- Scanners can report over WiFi to a phone hotspot — no special networking infrastructure
- Well-suited to BibTime's GenServer adapter pattern

### Cons
- ±1–3 second accuracy (detection zone, not a line)
- Beacons need battery management (charging/replacing coin cells)
- Must assign and collect beacons from athletes (like reusable RFID chips)
- DIY assembly and firmware required
- Less proven at scale than RFID — needs thorough testing

---

## 9. NFC/QR Tap + Smartphone at Checkpoints

**Zero-infrastructure option.** Athletes carry a bib with an NFC sticker or printed QR code. A volunteer at each timing point taps or scans the bib with a phone.

### How it works
NFC stickers ($0.05–0.20 each) are attached to race bibs, each programmed with the athlete's bib number. At each timing point, a volunteer holds a phone with an NFC reader app. As each athlete arrives, they tap their bib to the phone. The app records the bib number and timestamp. Alternatively, a printed QR code on the bib is scanned with the phone's camera.

NFC has the advantage of working with the phone locked (background reading on Android), while QR requires the camera app to be open and pointed at the bib.

### Hardware

| Component | Options | Approx. Price |
|-----------|---------|---------------|
| NFC stickers (NTAG215) | Pre-programmed or bulk blank | $0.05–0.20 each |
| QR codes | Printed on bib (free) | $0 |
| Phones at checkpoints | Volunteer-owned or cheap Android phones | $0–80 each |

**Per-athlete cost:** ~$0.05–0.20 (NFC sticker) or $0 (QR on bib)
**Per-checkpoint cost:** ~$0 (volunteer phones)
**Full triathlon (100 athletes, 5 splits):** ~$10–50

### Software
- **Webscorer PRO** (webscorer.com) — Supports NFC and QR barcode scanning, integrates with results platform
- **OpenRaceTiming** (openracetiming.org) — Free, open-source NFC timing app

### BibTime adapter concept
A lightweight phone app (or PWA) could POST scan events to BibTime's HTTP API. The adapter would be a simple webhook receiver GenServer — the phone is the "reader" and BibTime just ingests timestamped bib reads.

### Pros
- Near-zero cost
- No hardware to buy, charge, or maintain
- NFC stickers are waterproof and disposable
- Extremely simple to set up

### Cons
- Requires a volunteer at every timing point
- NFC needs near-contact distance (~4 cm) — athletes must actively tap
- QR scanning takes a few seconds per athlete — breaks down with large packs arriving simultaneously
- Not automated — human bottleneck at busy split points
- Phone battery life can be an issue over a long race day

---

## 10. LoRa GPS Trackers

**Long-range live tracking** with minimal infrastructure, but too coarse for precise split timing.

### How it works
Each athlete carries a small LoRa GPS tracker that periodically transmits its GPS coordinates. LoRa gateways (with range of 1–15 km depending on terrain) receive these transmissions. Software geofences the timing points and records a split time when a tracker enters a defined zone.

LoRa's low data rate means trackers typically transmit every 5–30 seconds, which directly limits timing accuracy to ±5–20 seconds.

### Hardware

| Component | Options | Approx. Price |
|-----------|---------|---------------|
| LoRa GPS tracker | LilyGo T-Beam (ESP32 + LoRa + GPS), RAK WisBlock | $20–50 each |
| LoRa gateway | RAK7268 (indoor), RAK7289 (outdoor), or Dragino LPS8 | $100–200 each |
| Antenna | Fiberglass omnidirectional for gateway | $20–50 |

**Per-athlete cost:** ~$25–50 (reusable tracker)
**Per-gateway cost:** ~$120–250
**Full triathlon (100 athletes, 1–2 gateways):** ~$2,700–5,200

### Where to buy
- **RAKwireless** (rakwireless.com) — Gateways, tracker modules, WisBlock ecosystem
- **LilyGo** (lilygo.cc) — T-Beam boards (ESP32 + SX1276 LoRa + GPS)
- **Dragino** (dragino.com) — Budget LoRa gateways
- **AliExpress** — LilyGo T-Beam (~$25), generic LoRa modules

### BibTime adapter concept
A LoRa gateway forwards packets to a network server (e.g., ChirpStack, open-source). BibTime's adapter subscribes to the MQTT feed from ChirpStack, decodes GPS coordinates from tracker payloads, and checks them against geofenced timing zones. When a tracker enters a zone, a split time is recorded.

### Pros
- Incredible range — one gateway can cover an entire race course
- Enables live athlete tracking on a map (great for spectators)
- Trackers are reusable
- Minimal infrastructure — potentially just one or two gateways for the whole venue

### Cons
- Poor timing accuracy (±5–20 seconds) — unsuitable as primary split timer
- GPS fix can be slow or unreliable under tree cover or near buildings
- Higher per-athlete cost than BLE or NFC
- Tracker battery life depends on transmission interval (more frequent = less battery)
- Better suited as a supplementary tracking layer than a timing system

---

## 11. Computer Vision — Camera + Bib Number OCR

**No wearable tech required.** A camera at each timing point records video, and software detects bib numbers from the footage to assign timestamps.

### How it works
A camera (webcam, action camera, or smartphone) is positioned at each timing point with a clear view of athletes' chests/bibs. Video is processed either in near-real-time or as a batch after the race. A YOLO-based object detection model locates the bib region, then OCR reads the number. The frame timestamp gives the split time.

Current open-source models achieve ~83% precision on bib detection. Accuracy improves significantly with consistent bib design (large numbers, high contrast, standardized placement).

### Hardware

| Component | Options | Approx. Price |
|-----------|---------|---------------|
| Camera | Logitech C920 webcam, GoPro, or old smartphone | $0–80 each |
| Processing | Laptop with GPU, Raspberry Pi 5 (slower), or cloud | $0–200 |
| Tripod / mount | Standard camera tripod | $15–30 each |

**Per-athlete cost:** $0 (uses existing bibs)
**Per-checkpoint cost:** ~$50–100 (camera + mount)
**Full triathlon (5 splits):** ~$200–500 (cameras) + processing hardware

### Open-source tools
- **bib-detector** (github.com/ericBayless/bib-detector) — YOLOv4-tiny model for bib detection
- **Roboflow** (roboflow.com) — Pre-trained bib detection models and labeled datasets for fine-tuning
- **PaddleOCR** — High-accuracy open-source OCR for reading detected bib numbers

### BibTime adapter concept
A CV pipeline (Python service) processes video feeds or image frames, detects bibs, reads numbers, and POSTs results to BibTime's HTTP API. The adapter (`BibTime.Timing.Adapters.CV`) would receive these as timestamped bib reads. This naturally pairs with other timing methods — use CV as a verification layer alongside BLE or manual entry.

### Pros
- No wearable hardware cost — athletes just need standard bibs
- Can process existing race footage retroactively
- Useful as a verification/audit layer alongside other timing methods
- Improving rapidly with modern ML models

### Cons
- ~83% precision means ~17% of reads will be missed or wrong — not standalone-reliable
- Requires good lighting, camera angle, and bib visibility (hard in rain, crowds, or dark conditions)
- Processing requires a capable computer (GPU recommended for real-time)
- Athletes with obscured, folded, or muddy bibs will be missed
- Swim leg is nearly impossible (bibs not visible in water)

---

## 12. Hybrid Approach: BLE + Manual Finish Verification

**Recommended for small triathlons on a budget.** Combines automated tracking across the course with human precision where it matters most.

### How it works
BLE beacons on athletes provide automated split detection at swim exit, T1, bike finish, and T2. At the finish line — where a judge is already present — timing is done manually (BibTime's manual entry interface or a camera + CV system). The top finishers are verified by the judge, while the bulk of the field gets automated times that are accurate within a few seconds.

### Setup

| Timing Point | Method | Equipment |
|--------------|--------|-----------|
| Swim finish | BLE scanner | 1x ESP32 + power bank |
| T1 out | BLE scanner | 1x ESP32 + power bank |
| Bike finish | BLE scanner | 1x ESP32 + power bank |
| T2 out | BLE scanner | 1x ESP32 + power bank |
| Run finish | Manual entry + judge | Laptop running BibTime |

### Cost estimate (100 athletes)
- 100x BLE beacons: ~$500–1,000
- 4x ESP32 scanners with enclosures and power: ~$120–300
- 4x phone hotspots for connectivity: $0 (volunteer phones)
- Manual entry at finish: $0 (laptop running BibTime)
- **Total: ~$620–1,300**

### Pros
- Best cost-to-capability ratio for small events
- Automated tracking for most of the course
- Human precision at the finish where it matters
- Falls back gracefully — if a scanner fails, you still have manual entry
- All methods feed into the same BibTime adapter pipeline

### Cons
- Still requires beacon management (assign, collect, charge)
- BLE scanners are DIY — need firmware and testing
- Mixed-method approach adds complexity to the timing workflow

---

## Integration Strategy for BibTime

Based on this research, here's a suggested adapter development order:

### Professional RFID path

1. **LLRP adapter (Phase 3, first)** — Covers Impinj, Zebra, and any LLRP-compliant reader. Open protocol with good documentation. Build and test with an Impinj R420 (~$1,000 used).

2. **Race Result adapter (Phase 3, second)** — Their HTTP API is well-documented. Contact Race Result for API docs and a development unit.

3. **MYLAPS adapter (Phase 3, optional)** — Only if there's demand from organizers already owning MYLAPS hardware. Protocol is proprietary but may be documentable.

4. **Generic serial/TCP adapter** — Covers J-Chip and other legacy systems with a configurable protocol parser.

### Low-cost alternative path

1. **BLE adapter (can start early)** — ESP32 scanners pushing reads over WiFi/MQTT. Simple protocol, easy to prototype alongside Phase 1 manual entry. A good first hardware adapter since the ESP32 ecosystem is cheap and accessible.

2. **Webhook/HTTP adapter** — Generic receiver for phone-based timing apps (NFC/QR), CV pipelines, or any external system that can POST a timestamped bib read. Covers multiple alternative methods with a single adapter.

3. **LoRa adapter (optional)** — For live tracking overlay. Subscribes to ChirpStack MQTT feed, geofences timing zones, and feeds coarse split times into BibTime. Best as a supplementary data source rather than primary timing.

Both paths feed into the same `%ChipRead{}` pipeline and PubSub broadcast, so they can be mixed and matched at a single event — e.g., LLRP at the finish line, BLE at transition points, and LoRa for live map tracking.
