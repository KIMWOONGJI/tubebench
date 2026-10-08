# HBK LAN-XI Open API — verified reference used by `tim.instr.LanXi` / `tim.instr.LanXiStreamParser`

Sources (checked 2026-10-08):

* **[M]** BE 1872-15 *LAN-XI Open API User Guide* (https://www.bksv.com/-/media/literature/Manuals/be1872.ashx)
* **[K]** `src/kaitai/openapi_message.ksy` in https://github.com/hbkworld/open-api-tutorials (no LICENSE file in that repo — only the *format description* is used, no code is copied)
* **[P]** `src/streaming_single_module.py` in the same repository (official single-module example)
* **[R]** https://github.com/hbkworld/open-api-time-data-recorder — official MATLAB GUI, MIT licence, © 2021 HBK, developed with firmware 2.10.0.501. Used as a behavioural reference; this project re-implements the protocol and does not copy its files (several of its parser quirks are listed below).
* **[D]** Type 3676/3677 data sheet BP 2586.

Real module (read-only query 2026-10-08, saved in `tests/fixtures/`): Type 3676-B-040, serial 110283,
firmware **2.10.0.610**, `supportedSampleRates` = [65536 32768 16384 8192 4096],
`supportedRanges` = ["1 Vpeak", "10 Vpeak"], `supportedFilters` = ["DC", "0.1 Hz 10%", "0.7 Hz",
"1.0 Hz 10%", "7.0 Hz", "22.4 Hz", "Intensity"], destinations ["sd","socket","multiSocket","socketUdp"],
`ptpStatus` "Locked", moduleState "Idle".

## 1. REST state machine (single module)

| Step | Request | Body | State transition |
|---|---|---|---|
| info | GET `/rest/rec/module/info` | – | any |
| status | GET `/rest/rec/onchange[?last=<tag>]` | – | any; with `last` = current tag it long-polls up to 30 s |
| time | PUT `/rest/rec/module/time` | ASCII ms since 1970 | (module has no RTC) |
| open | PUT `/rest/rec/open` | `{"performTransducerDetection":false}` | Idle → RecorderOpened |
| create | PUT `/rest/rec/create` | – | RecorderOpened → RecorderConfiguring |
| TEDS detect | POST `/rest/rec/channels/input/all/transducers/detect` | – | any; wait `transducerDetectionActive == false` |
| TEDS result | GET `/rest/rec/channels/input/all/transducers` | – | array, `null` per channel without TEDS |
| default setup | GET `/rest/rec/channels/input/default` | – | |
| apply setup | PUT `/rest/rec/channels/input` | setup JSON | RecorderConfiguring → RecorderStreaming |
| port | GET `/rest/rec/destination/socket` | → `{"tcpPort":N}` | RecorderStreaming |
| start | POST `/rest/rec/measurements` | – | RecorderStreaming → RecorderRecording |
| stop | PUT `/rest/rec/measurements/stop` | – | RecorderRecording → RecorderStreaming |
| finish | PUT `/rest/rec/finish` | – | RecorderStreaming → RecorderOpened |
| close | PUT `/rest/rec/close` | – | RecorderOpened → Idle |
| cancel | PUT `/rest/rec/cancel` | – | RecorderConfiguring → RecorderOpened |

HTTP: 200 = state change completed; 202 = pending; 403 = not allowed in current state; 503 = >10
connections. The [P] order is: connect stream socket **before** POST `/measurements`; PUT
`/measurements/stop` **before** closing the socket (otherwise the module reports data loss).
LAN-XI Light (3676) is single-module only; `/syncmode` is not needed ([P] does not touch it).
Only one Open API client at a time; BK Connect must not be connected simultaneously.

Channel setup fields used: `bandwidth` (sample rate = 2.56 × bandwidth; same for all channels;
strings "1.6 kHz", "3.2 kHz", "6.4 kHz", "12.8 kHz", "25.6 kHz"), `ccld` (bool), `destinations`
(["socket"]), `enabled`, `filter` (high-pass), `range`, `transducer` (sensitivity in V per unit,
serialNumber, type{number,…}, unit, requiresCcld), `name`, `floating`, `polVolt`.

## 2. Stream message format (little endian)

Header, 28 bytes [M §5.2.2, K]:

| Offset | Type | Field |
|---|---|---|
| 0 | char[2] | magic "BK" (0x42 0x4B) |
| 2 | u16 | headerLength (= 20, bytes between this field and messageLength) |
| 4 | u16 | messageType: 1 SignalData, 2 DataQuality, 8 Interpretation, 11 AuxSequenceData |
| 6 | u16 | reserved1 |
| 8 | u32 | reserved2 |
| 12 | u8×4 | time family k,l,m,n — ticks/s = 2^k 3^l 5^m 7^n |
| 16 | u64 | time count (ticks since 1970-01-01) |
| 24 | u32 | messageLength (content bytes) |

Content starts at `4 + headerLength + 4` (= 28).

* **SignalData (1)**: u16 numberOfSignals, u16 reserved, then per signal: s16 signalId, s16
  numberOfValues, numberOfValues × int24 LE (b0 + b1·2⁸ + s8(b2)·2¹⁶). No padding.
* **DataQuality (2)**: u16 numberOfSignals, then per signal: u16 signalId, u16 validity, u16 reserved.
  Validity bits: 2 = clipped/overload, 8 = invalid (cable fault / CCLD / common-mode / analog
  overload), 16 = overrun (gap in data). Sent only when the state changes.
* **Interpretation (8)**: repeated until end of content: u16 signalId, u16 descriptorType, u16
  reserved, u16 valueLength, value, padding to a 4-byte boundary (position measured from content
  start). Descriptor types: 1 DataType (u16, 3 = Int24), 2 ScaleFactor (f64), 3 Offset (f64),
  4 PeriodTime (time, 12 bytes), 5 Unit (u16 count + UTF-8), 6 VectorLength (u16), 7 ChannelType (u16).

signalId: 1..N consecutively over the **enabled** channels.

Scaling: `value = int24 / 2^23 * ScaleFactor + Offset` [M ch.7, tutorials]. The module computes
ScaleFactor = range × headroom / sensitivity, using the transducer sensitivity of the channel setup,
and reports the engineering unit in the Unit descriptor. **Consequently**: if a sensitivity (V/Pa)
is put in the setup the stream is already in Pa — the driver must NOT divide by the sensitivity again.
This project sends sensitivity 1 V/V with unit "V" by default, and converts to Pa in software
(`tim.acq.voltsToPascal`), so the TEDS/certificate values are applied exactly once and are recorded
in the metadata. The parser checks the Unit descriptor and refuses a mismatch.

## 3. Unverified items (driver treats them defensively)

* Whether the header timestamp equals the time of the first sample of a SignalData message
  (only used as a continuity diagnostic, never for synchronisation with the generator).
* Whether `valueLength` of the Unit descriptor includes the 2-byte count — the parser parses by
  type and uses `valueLength` only as a sanity bound.
* `/measurements/start` alias mentioned once in [M] — not used.

## 4. Quirks in [R] avoided in this implementation

* Interpretation parser in [R] keeps only the last descriptor and ignores padding.
* [R] posts `/measurements` before connecting the socket.
* [R] wait loops have no timeout; here every wait has a timeout and reports the last state.
* [R] reboots the module on disconnect; this driver never reboots automatically.
