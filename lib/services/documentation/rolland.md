# Roland V-160HD Control Commands

## Command Format

Commands are formatted using ASCII code and are common to both LAN and RS-232 interfaces.

**Format:** `Command code:parameter,parameter;`

- **Command code**: Specifies the command type (single-byte alphanumeric characters)
- **Parameter**: Appended to commands requiring parameters, separated from command by colon
- **Multiple parameters**: Separated by commas
- **Terminator**: `;` (semicolon) indicates end of command
- **Response**: Product responses end with semicolon followed by carriage return code (0x0A, LF, \n)

---

## VIDEO Commands

### QVISRC - Get Video Input Source
**Transmit:** `QVISRC:a;`
- `a`: 0–51

**Response:** `VISRC:a,b;ACK;`
- `a`: 0–51
- `b`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

**Example:**
- Transmit: `QVISRC:0;` (Check zeroth Video Input Source)
- Response: `VISRC:0,HDMI1;ACK;` (Zeroth source is HDMI1)

### QVIST - Get Video Input Status
**Transmit:** `QVIST:a;`
- `a`: HDMI1–8, SDI1–8

**Response:** `VIST:a,b;ACK;`
- `a`: HDMI1–8, SDI1–8
- `b`: NOSIGNAL, DETECTED, UNSUPPORTED

**Example:**
- Transmit: `QVIST:HDMI1;` (Check HDMI1 status)
- Response: `VIST:HDMI1,DETECTED;ACK;`

### VFL - Set Video Fader Level
**Transmit:** `VFL:a;`
- `a`: 0–2047

**Response:** `ACK;`

**Example:**
- Transmit: `VFL:1024;` (Set fader level to 1024)

### QVFL - Get Video Fader Level
**Transmit:** `QVFL;`

**Response:** `VFL:a;ACK;`
- `a`: 0–2047

**Example:**
- Transmit: `QVFL;`
- Response: `VFL:1024;ACK;`

### PGM - Select PGM Video Channel
**Transmit:** `PGM:a;`
- `a`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

**Response:** `ACK;`

**Example:**
- Transmit: `PGM:INPUT2;` (Select INPUT2 for PGM)

### QPGM - Get PGM Video Channel
**Transmit:** `QPGM;`

**Response:** `PGM:a,b;ACK;`
- `a`: HDMI1–8, SDI1–8, STILL1–16
- `b`: INPUT1–20 (Only when selected as input channel)

**Example:**
- Transmit: `QPGM;`
- Response: `PGM:HDMI2,INPUT2;ACK;` (PGM is INPUT2 which is HDMI2)

### PST - Select PST Video Channel
**Transmit:** `PST:a;`
- `a`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

**Response:** `ACK;`

### QPST - Get PST Video Channel
**Transmit:** `QPST;`

**Response:** `PST:a,b;ACK;`
- `a`: HDMI1–8, SDI1–8, STILL1–16
- `b`: INPUT1–20 (Only when selected as input channel)

### AUX - Select AUX Bus Video Channel
**Transmit:** `AUX:a,b;`
- `a`: AUX1–3
- `b`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20, PGMLINK
  - PGMLINK can be set when AUX Linked PGM parameter is enabled

**Response:** `ACK;`

### QAUX - Get AUX Bus Video Channel
**Transmit:** `QAUX:a;`
- `a`: AUX1–3

**Response:** `AUX:a,b,c;ACK;`
- `a`: AUX1–3
- `b`: HDMI1–8, SDI1–8, STILL1–16
- `c`: INPUT1–20 (Only when selected as input channel)

### ATO - Auto-Switch Video (enabled when SPLIT is OFF)

**Variant 1:** `ATO;`
**Response:** `ACK;`

**Variant 2:** `ATO:a;`
- `a`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20
**Response:** `ACK;`

**Variant 3:** `ATO:a,b;`
- `a`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20
- `b`: -1, 0–40
  - -1: use Transition Time setting
  - 0–40: 0.0–4.0 sec

**Response:** `ACK;`

**Example:**
- Transmit: `ATO:INPUT1,10;` (Auto-switch INPUT1 every 1.0 sec)

### CUT - Switch Video Using CUT (enabled when SPLIT is OFF)

**Variant 1:** `CUT;`
**Response:** `ACK;`

**Variant 2:** `CUT:a;`
- `a`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20
**Response:** `ACK;`

### QATG - Get Auto Transition Status
**Transmit:** `QATG;`

**Response:** `ATG:a;ACK;`
- `a`: OFF, ON

**Example:**
- Transmit: `QATG;`
- Response: `ATG:ON;ACK;` (Auto Transition in use)

### FRZ - Freeze Control

**Toggle:** `FRZ;`
**Response:** `ACK;`

**Set:** `FRZ:a;`
- `a`: OFF, ON
**Response:** `ACK;`

**Get:** `QFRZ;`
**Response:** `FRZ:a;ACK;`
- `a`: OFF, ON

### FTB - Output Fade Control

**Toggle:** `FTB;`
**Response:** `ACK;`

**Set:** `FTB:a;`
- `a`: OFF, ON
**Response:** `ACK;`

**Get:** `QFTB;`
**Response:** `FTB:a;ACK;`
- `a`: OFF, ON, FADEIN, FADEOUT

### VIS - Set Video Input Assign
**Transmit:** `VIS:a,b;`
- `a`: INPUT1–20
- `b`: HDMI1–8, SDI1–8, STILL1–16, N/A

**Response:** `ACK;`

**Example:**
- Transmit: `VIS:INPUT1,HDMI1;` (Assign HDMI1 to INPUT1)

### QVIS - Get Video Input Assign
**Transmit:** `QVIS:a;`
- `a`: INPUT1–20

**Response:** `VIS:a,b;ACK;`
- `a`: INPUT1–20
- `b`: HDMI1–8, SDI1–8, STILL1–16, N/A

**Example:**
- Transmit: `QVIS:INPUT1;`
- Response: `VIS:INPUT1,HDMI1;ACK;`

### VOS - Set Video Output Assign
**Transmit:** `VOS:a,b;`
- `a`: HDMI1–3, SDI1–3, USB
- `b`: PGM, SUB, PVW, AUX1–3, DSK1–2, MULTI, INPUT1, STILL
  - MULTI: Multi-View
  - INPUT1: 16 Input-View
  - STILL: 16 Still-View

**Response:** `ACK;`

### QVOS - Get Video Output Assign
**Transmit:** `QVOS:a;`
- `a`: HDMI1–3, SDI1–3, USB

**Response:** `VOS:a,b;ACK;`
- `a`: HDMI1–3, SDI1–3, USB
- `b`: PGM, SUB, PVW, AUX1–3, DSK1–2, MULTI, INPUT1, STILL

### TRS - Set Transition Type
**Transmit:** `TRS:a;`
- `a`: MIX, WIPE

**Response:** `ACK;`

### QTRS - Get Transition Type
**Transmit:** `QTRS;`

**Response:** `TRS:a;ACK;`
- `a`: MIX, WIPE

### TIM - Set Transition Time
**Transmit:** `TIM:a,b;`
- `a`: MIX, WIPE, PinP1–4, DSK1–2, OUTPUTFADE
- `b`: 0–40 (Transition Time: 0.0–4.0 sec)

**Response:** `ACK;`

**Example:**
- Transmit: `TIM:MIX,10;` (Set MIX transition to 1.0 sec)

### QTIM - Get Transition Time
**Transmit:** `QTIM:a;`
- `a`: MIX, WIPE, PinP1–4, DSK1–2, OUTPUTFADE

**Response:** `TIM:a,b;ACK;`
- `a`: MIX, WIPE, PinP1–4, DSK1–2, OUTPUTFADE
- `b`: 0–40 (Transition Time: 0.0–4.0 sec)

**Example:**
- Transmit: `QTIM:MIX;`
- Response: `TIM:MIX,10;ACK;` (MIX time is 1.0 sec)

### PIS - Set PinP Source
**Transmit:** `PIS:a,b;`
- `a`: PinP1–4
- `b`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

**Response:** `ACK;`

### QPIS - Get PinP Source
**Transmit:** `QPIS:a;`
- `a`: PinP1–4

**Response:** `PIS:a,b;ACK;`
- `a`: PinP1–4
- `b`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

### PPS - PinP PGM Control

**Toggle:** `PPS:a;`
- `a`: PinP1–4
**Response:** `ACK;`

**Set:** `PPS:a,b;`
- `a`: PinP1–4
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QPPS:a;`
- `a`: PinP1–4
**Response:** `PPS:a,b;ACK;`
- `a`: PinP1–4
- `b`: OFF, ON

### PPW - PinP PVW Control

**Toggle:** `PPW:a;`
- `a`: PinP1–4
**Response:** `ACK;`

**Set:** `PPW:a,b;`
- `a`: PinP1–4
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QPPW:a;`
- `a`: PinP1–4
**Response:** `PPW:a,b;ACK;`
- `a`: PinP1–4
- `b`: OFF, ON

### PIP - Change PinP Window Position
**Transmit:** `PIP:a,h,v;`
- `a`: PinP1–4
- `h`: -1000–0–1000 (Position H: -100.0–0.0–100.0%)
- `v`: -1000–0–1000 (Position V: -100.0–0.0–100.0%)

**Response:** `ACK;`

### QPIP - Get PinP Window Position
**Transmit:** `QPIP:a;`
- `a`: PinP1–4

**Response:** `PIP:a,h,v;ACK;`
- `a`: PinP1–4
- `h`: -1000–0–1000 (Position H: -100.0–0.0–100.0%)
- `v`: -1000–0–1000 (Position V: -100.0–0.0–100.0%)

### DSK - DSK PGM Control

**Toggle:** `DSK:a;`
- `a`: DSK1–2
**Response:** `ACK;`

**Set:** `DSK:a,b;`
- `a`: DSK1–2
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QDSK:a;`
- `a`: DSK1–2
**Response:** `DSK:a,b;ACK;`
- `a`: DSK1–2
- `b`: OFF, ON

### DVW - DSK PVW Control

**Toggle:** `DVW:a;`
- `a`: DSK1–2
**Response:** `ACK;`

**Set:** `DVW:a,b;`
- `a`: DSK1–2
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QDVW:a;`
- `a`: DSK1–2
**Response:** `DVW:a,b;ACK;`
- `a`: DSK1–2
- `b`: OFF, ON

### DSS - Change DSK Fill Source
**Transmit:** `DSS:a,b;`
- `a`: DSK1–2
- `b`: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

**Response:** `ACK;`

### QDSS - Get DSK Fill Source
**Transmit:** `QDSS:a;`
- `a`: DSK1–2

**Response:** `DSS:a,b,c;ACK;`
- `a`: DSK1–2
- `b`: HDMI1–8, SDI1–8, STILL1–16
- `c`: INPUT1–20

### KYL - Change DSK Level
**Transmit:** `KYL:a,b;`
- `a`: DSK1–2
- `b`: 0–255

**Response:** `ACK;`

### QKYL - Get DSK Level
**Transmit:** `QKYL:a;`
- `a`: DSK1–2

**Response:** `KYL:a,b;ACK;`
- `a`: DSK1–2
- `b`: 0–255

### KYG - Change DSK Gain
**Transmit:** `KYG:a,b;`
- `a`: DSK1–2
- `b`: 0–255

**Response:** `ACK;`

### QKYG - Get DSK Gain
**Transmit:** `QKYG:a;`
- `a`: DSK1–2

**Response:** `KYG:a,b;ACK;`
- `a`: DSK1–2
- `b`: 0–255

### SPS - SPLIT Control

**Toggle:** `SPS:a;`
- `a`: SPLIT1–2
**Response:** `ACK;`

**Set:** `SPS:a,b;`
- `a`: SPLIT1–2
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QSPS:a;`
- `a`: SPLIT1–2
**Response:** `SPS:a,b;ACK;`
- `a`: SPLIT1–2
- `b`: OFF, ON

### SPT - Set SPLIT Positions

**Variant 1:** `SPT:a,b,c;`
- `a`: SPLIT1–2
- `b`: -500–0–500 (PGM/A-Center: -50.0–0.0–50.0%)
- `c`: -500–0–500 (PST/B-Center: -50.0–0.0–50.0%)
**Response:** `ACK;`

**Variant 2:** `SPT:a,b,c,d;`
- `a`: SPLIT1–2
- `b`: -500–0–500 (PGM/A-Center: -50.0–0.0–50.0%)
- `c`: -500–0–500 (PST/B-Center: -50.0–0.0–50.0%)
- `d`: -500–0–500 (Center Position: -50.0–0.0–50.0%)
**Response:** `ACK;`

### QSPT - Get SPLIT Positions
**Transmit:** `QSPT:a;`
- `a`: SPLIT1–2

**Response:** `SPT:a,b,c,d;ACK;`
- `a`: SPLIT1–2
- `b`: -500–0–500 (PGM/A-Center: -50.0–0.0–50.0%)
- `c`: -500–0–500 (PST/B-Center: -50.0–0.0–50.0%)
- `d`: -500–0–500 (Center Position: -50.0–0.0–50.0%)

### STO - Set Still Image Output
**Transmit:** `STO:a;`
- `a`: OFF, STILL1–16

**Response:** `ACK;`

### QSTO - Get Still Image Output
**Transmit:** `QSTO;`

**Response:** `STO:a;ACK;`
- `a`: OFF, STILL1–16

---

## AUDIO Commands

### AOS - Set Audio Output Assign
**Transmit:** `AOS:a,b;`
- `a`: HDMI1–3, SDI1–3, XLR1, RCA1, USB, PHONES
- `b`: 
  - AUTO, MAIN, AUX1–3 (for HDMI1–3, SDI1–3, USB)
  - MAIN, AUX1–3 (for XLR1, RCA1, PHONES)

**Response:** `ACK;`

### QAOS - Get Audio Output Assign
**Transmit:** `QAOS:a;`
- `a`: HDMI1–3, SDI1–3, XLR1, RCA1, USB, PHONES

**Response:** `AOS:a,b;ACK;`
- `a`: HDMI1–3, SDI1–3, XLR1, RCA1, USB, PHONES
- `b`:
  - AUTO, MAIN, AUX1–3 (for HDMI1–3, SDI1–3, USB)
  - MAIN, AUX1–3 (for XLR1, RCA1, PHONES)

### IAL - Set Audio Input Level
**Transmit:** `IAL:a,b;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: -INF, -800–0–100 (Level: -INF, -80.0–0.0–10.0 dB)

**Response:** `ACK;`

**Example:**
- Transmit: `IAL:XLR1,-60;` (Set XLR1 to -6.0 dB)

### QIAL - Get Audio Input Level
**Transmit:** `QIAL:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8

**Response:** `IAL:a,b;ACK;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: -INF, -800–0–100 (Level: -INF, -80.0–0.0–10.0 dB)

**Example:**
- Transmit: `QIAL:XLR1;`
- Response: `IAL:XLR1,-60;ACK;` (XLR1 is -6.0 dB)

### IAM - Audio Input Mute Control

**Toggle:** `IAM:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
**Response:** `ACK;`

**Set:** `IAM:a,b;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QIAM:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
**Response:** `IAM:a,b;ACK;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON

### IAS - Audio Input Solo Control

**Toggle:** `IAS:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
**Response:** `ACK;`

**Set:** `IAS:a,b;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QIAS:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
**Response:** `IAS:a,b;ACK;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON

### ADT - Set Audio Input Delay Time
**Transmit:** `ADT:a,b;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: 0–5000 (0.0–500.0 msec)

**Response:** `ACK;`

### QADT - Get Audio Input Delay Time
**Transmit:** `QADT:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8

**Response:** `ADT:a,b;ACK;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: 0–5000 (0.0–500.0 msec)

### HPF - High Pass Filter Control

**Set:** `HPF:a,b;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QHPF:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
**Response:** `HPF:a,b;ACK;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON

### GATE - Gate Control

**Set:** `GATE:a,b;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QGATE:a;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
**Response:** `GATE:a,b;ACK;`
- `a`: XLR1–2, RCA1, USB, BLUETOOTH, HDMI1–8, SDI1–8
- `b`: OFF, ON

### STLK - Stereo Link Control

**Toggle:** `STLK:a;`
- `a`: XLR1–2
**Response:** `ACK;`

**Set:** `STLK:a,b;`
- `a`: XLR1–2
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QSTLK:a;`
- `a`: XLR1–2
**Response:** `STLK:a,b;ACK;`
- `a`: XLR1–2
- `b`: OFF, ON

### VOCH - Voice Changer Control

**Toggle:** `VOCH:a;`
- `a`: XLR1–2
**Response:** `ACK;`

**Set:** `VOCH:a,b;`
- `a`: XLR1–2
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QVOCH:a;`
- `a`: XLR1–2
**Response:** `VOCH:a,b;ACK;`
- `a`: XLR1–2
- `b`: OFF, ON

### OAL - Set Audio Output Level
**Transmit:** `OAL:a,b;`
- `a`: MAIN, AUX1–3, USB
- `b`: -INF, -800–0–100 (Level: -INF, -80.0–0.0–10.0 dB)

**Response:** `ACK;`

### QOAL - Get Audio Output Level
**Transmit:** `QOAL:a;`
- `a`: MAIN, AUX1–3, USB

**Response:** `OAL:a,b;ACK;`
- `a`: MAIN, AUX1–3, USB
- `b`: -INF, -800–0–100 (Level: -INF, -80.0–0.0–10.0 dB)

### OAM - Set Audio Output Mute
**Transmit:** `OAM:a,b;`
- `a`: MAIN, AUX1–3, USB
- `b`: OFF, ON

**Response:** `ACK;`

### QOAM - Get Audio Output Mute Status
**Transmit:** `QOAM:a;`
- `a`: MAIN, AUX1–3, USB

**Response:** `OAM:a,b;ACK;`
- `a`: XLR1–2
- `b`: OFF, ON

### RVB - Reverb Control

**Toggle:** `RVB;`
**Response:** `ACK;`

**Set:** `RVB:a;`
- `a`: OFF, ON
**Response:** `ACK;`

**Get:** `QRVB;`
**Response:** `RVB:a;ACK;`
- `a`: OFF, ON

### ATM - Audio Auto Mixing Control

**Toggle:** `ATM;`
**Response:** `ACK;`

**Set:** `ATM:a;`
- `a`: OFF, ON
**Response:** `ACK;`

**Get:** `QATM;`
**Response:** `ATM:a;ACK;`
- `a`: OFF, ON

---

## METER Commands

### MTRSW - Set Auto-Transmit for Audio Level Meter
**Transmit:** `MTRSW:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QMTRSW - Get Auto-Transmit Status for Audio Level Meter
**Transmit:** `QMTRSW;`

**Response:** `MTRSW:a;ACK;`
- `a`: OFF, ON

### MTRLV - Get Audio Level Meter Information
**Transmit:** `MTRLV:a;`
- `a`: PFL, AFL

**Response:** `MTRLV:a0,a1,…;ACK;`
- Values: -INF, -80–0–10 (Level: -INF, -80–0–10 dB)
- a0–a53: IN-XLR1–2, IN-RCA1-L–1-R, IN-USB-L–R, IN-BLUETOOTH-L–R, IN-HDMI1-L–8-R, IN-SDI1-L–8-R, OUT-MAIN-L–R, OUT-AUX1-L–3-R, OUT-USB-L–R, OUT-DSK1-L–2-R

**Example:**
- Transmit: `MTRLV:PFL;` (Check PFL meter)
- Response: `MTRLV:-INF,-80,…,10;ACK;` (Levels joined with commas)

### MTRCH - Get Audio Level Meter Channel Information
**Transmit:** `MTRCH:a;`
- `a`: 0–53

**Response:** `MTRCH:a,b;ACK;`
- `a`: 0–53
- `b`: IN-XLR1–2, IN-RCA1-L–1-R, IN-USB-L–R, IN-BLUETOOTH-L–R, IN-HDMI1-L–8-R, IN-SDI1-L–8-R, OUT-MAIN-L–R, OUT-AUX1-L–3-R, OUT-USB-L–R, OUT-DSK1-L–2-R

**Example:**
- Transmit: `MTRCH:0;`
- Response: `MTRCH:0,IN-XLR1;ACK;`

### GRSW - Set Auto-Transmit for Comp GR Level
**Transmit:** `GRSW:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QGRSW - Get Auto-Transmit Status for Comp GR Level
**Transmit:** `QGRSW;`

**Response:** `GRSW:a;ACK;`
- `a`: OFF, ON

### GRLV - Get Comp GR Level Information
**Transmit:** `GRLV;`

**Response:** `GRLV:a0,a1,…;ACK;`
- Values: -INF, -80–0–10 (Level: -INF, -80–0–10 dB)
- a0–a23: IN-XLR1–2, IN-RCA1, IN-USB, IN-BLUETOOTH, IN-HDMI1–8, IN-SDI1–8, OUT-MAIN-LO, OUT-MAIN-MID, OUT-MAIN-HIGH

### GRCH - Get Comp GR Channel Information
**Transmit:** `GRCH:a;`
- `a`: 0–23

**Response:** `GRCH:a,b;`
- `a`: 0–23
- `b`: IN-XLR1–2, IN-RCA1, IN-USB, IN-BLUETOOTH, IN-HDMI1–8, IN-SDI1–8, OUT-MAIN-LO, OUT-MAIN-MID, OUT-MAIN-HIGH

### AMSW - Set Auto-Transmit for Auto Mixing Level
**Transmit:** `AMSW:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QAMSW - Get Auto-Transmit Status for Auto Mixing Level
**Transmit:** `QAMSW;`

**Response:** `AMSW:a;ACK;`
- `a`: OFF, ON

### AMLV - Get Auto Mixing Level Information
**Transmit:** `AMLV;`

**Response:** `AMLV:a0,a1,…;ACK;`
- Values: -INF, -80–0–10 (Level: -INF, -80–0–10 dB)
- a0–a20: IN-XLR1–2, IN-RCA1, IN-USB, IN-BLUETOOTH, IN-HDMI1–8, IN-SDI1–8

### AMCH - Get Auto Mixing Channel Information
**Transmit:** `AMCH:a;`
- `a`: 0–20

**Response:** `AMCH:a,b;`
- `a`: 0–20
- `b`: IN-XLR1–2, IN-RCA1, IN-USB, IN-BLUETOOTH, IN-HDMI1–8, IN-SDI1–8

### SPSW - Set Auto-Transmit for Sig/Peak Level
**Transmit:** `SPSW:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QSPSW - Get Auto-Transmit Status for Sig/Peak Level
**Transmit:** `QSPSW;`

**Response:** `SPSW:a;ACK;`
- `a`: OFF, ON

### SPLV - Get Sig/Peak Level Information
**Transmit:** `SPLV;`

**Response:** `SPLV:a0,a1,…;ACK;`
- Values: -INF, -80–0–10 (Level: -INF, -80–0–10 dB)
- a0–a27: IN-XLR1–2, IN-RCA1, IN-USB, IN-BLUETOOTH, IN-HDMI1–8, IN-SDI1–8, OUT-MAIN, OUT-AUX1–3, OUT-USB, OUT-DSK1–2

### SPCH - Get Sig/Peak Channel Information
**Transmit:** `SPCH:a;`
- `a`: 0–27

**Response:** `SPCH:a,b;`
- `a`: 0–27
- `b`: IN-XLR1–2, IN-RCA1, IN-USB, IN-BLUETOOTH, IN-HDMI1–8, IN-SDI1–8, OUT-MAIN, OUT-AUX1–3, OUT-USB, OUT-DSK1–2

### AUXSW - Set Auto-Transmit for AUX Level
**Transmit:** `AUXSW:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QAUXSW - Get Auto-Transmit Status for AUX Level
**Transmit:** `QAUXSW;`

**Response:** `AUXSW:a;ACK;`
- `a`: OFF, ON

### AUXLV - Get AUX Meter Level Information
**Transmit:** `AUXLV:a;`
- `a`: AUX1–3

**Response:** `QAUXLV:a0,a1,…;ACK;`
- Values: -INF, -80–0–10 (Level: -INF, -80–0–10 dB)
- a0–a39: IN-XLR1–2, IN-RCA1-L–1-R, IN-USB-L–R, IN-BLUETOOTH-L–R, IN-HDMI1-L–8-R, IN-SDI1-L–8-R

### AUXCH - Get AUX Meter Channel Information
**Transmit:** `AUXCH:a;`
- `a`: 0–39

**Response:** `QAUXCH:a,b;`
- `a`: 0–39
- `b`: IN-XLR1–2, IN-RCA1-L–1-R, IN-USB-L–R, IN-BLUETOOTH-L–R, IN-HDMI1-L–8-R, IN-SDI1-L–8-R

---

## CONTROL Commands

### MEM - Recall Scene Memory
**Transmit:** `MEM:a;`
- `a`: MEMORY1–30

**Response:** `ACK;`

### QMEM - Get Selected Scene Memory
**Transmit:** `QMEM;`

**Response:** `MEM:a;ACK;`
- `a`: N/A, MEMORY1–30

### GPO - Output GPO

**One Shot:** `GPO:a;`
- `a`: GPO1–16
**Response:** `ACK;`

**Alternate:** `GPO:a,b;`
- `a`: GPO1–16
- `b`: OFF, ON
**Response:** `ACK;`

**Get Status:** `QGPO:a;`
- `a`: GPO1–16
**Response:** `GPO:a,b;ACK;`
- `a`: GPO1–16
- `b`: OFF, ON

### TLY - Get Tally Status
**Transmit:** `TLY;`

**Response:** `TLY:a0,a1,…;ACK;`
- Values: 0–3
  - 0: OFF
  - 1: PGM
  - 2: PST
  - 3: PGM & PST
- a0–a51: HDMI1–8, SDI1–8, STILL1–16, INPUT1–20

**Example:**
- Transmit: `TLY;`
- Response: `TLY:0,1,2,0…,0;ACK;` (Status as numbers joined with commas)

### ASW - Auto Switching Control

**Toggle:** `ASW;`
**Response:** `ACK;`

**Set:** `ASW:a;`
- `a`: OFF, ON
**Response:** `ACK;`

**Get:** `QASW;`
**Response:** `ASW:a;ACK;`
- `a`: OFF, ON

### INSC - Execute Input Scan
**Transmit:** `INSC:a;`
- `a`: NORMAL, REVERSE, RANDOM

**Response:** `ACK;`

### MEMSC - Execute Scene Memory Scan
**Transmit:** `MEMSC:a;`
- `a`: NORMAL, REVERSE, RANDOM

**Response:** `ACK;`

### PPSC - Execute PinP Source Scan
**Transmit:** `PPSC:a,b;`
- `a`: PinP1–4
- `b`: NORMAL, REVERSE, RANDOM

**Response:** `ACK;`

### DSKSC - Execute DSK Source Scan
**Transmit:** `DSKSC:a,b;`
- `a`: DSK1–2
- `b`: NORMAL, REVERSE, RANDOM

**Response:** `ACK;`

---

## CAMERA Commands

### CAMPT - Operate Pan and Tilt for PTZ Camera
**Transmit:** `CAMPT:a,b,c;`
- `a`: CAMERA1–16
- `b`: LEFT, STOP, RIGHT
- `c`: DOWN, STOP, UP

**Response:** `ACK;`

### CAMPTS - Set Pan and Tilt Speed for PTZ Camera
**Transmit:** `CAMPTS:a,b;`
- `a`: CAMERA1–16
- `b`: 1–24

**Response:** `ACK;`

### QCAMPTS - Get Pan and Tilt Speed for PTZ Camera
**Transmit:** `QCAMPTS:a;`
- `a`: CAMERA1–16

**Response:** `CPTS:a,b;ACK;`
- `a`: CAMERA1–16
- `b`: 1–24

### CAMZM - Operate Zoom for PTZ Camera
**Transmit:** `CAMZM:a,b;`
- `a`: CAMERA1–16
- `b`: WIDE_FAST, WIDE_SLOW, STOP, TELE_SLOW, TELE_FAST

**Response:** `ACK;`

### CAMZMR - Reset Zoom for PTZ Camera
**Transmit:** `CAMZMR:a;`
- `a`: CAMERA1–16

**Response:** `ACK;`

### CAMFC - Operate Focus for PTZ Camera
**Transmit:** `CAMFC:a,b;`
- `a`: CAMERA1–16
- `b`: NEAR, STOP, FAR

**Response:** `ACK;`

### CAMAFC - Set Auto Focus for PTZ Camera

**Set:** `CAMAFC:a,b;`
- `a`: CAMERA1–16
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QCAMAFC:a;`
- `a`: CAMERA1–16
**Response:** `CAFC:a,b;ACK;`
- `a`: CAMERA1–16
- `b`: OFF, ON

### CAMAEP - Auto Exposure Control for PTZ Camera

**Set:** `CAMAEP:a,b;`
- `a`: CAMERA1–16
- `b`: OFF, ON
**Response:** `ACK;`

**Get:** `QCAMAEP:a;`
- `a`: CAMERA1–16
**Response:** `CAEP:a,b;ACK;`
- `a`: CAMERA1–16
- `b`: OFF, ON

### CAMPR - Execute Preset Recall for PTZ Camera
**Transmit:** `CAMPR:a,b;`
- `a`: CAMERA1–16
- `b`: PRESET1–10

**Response:** `ACK;`

### QCAMPR - Get Current Preset Number of PTZ Camera
**Transmit:** `QCAMPR:a;`
- `a`: CAMERA1–16

**Response:** `CPR:a,b;ACK;`
- `a`: CAMERA1–16
- `b`: N/A, PRESET1–10

---

## Macro, Sequencer, Graphics Presenter Commands

### MCREX - Execute Macro
**Transmit:** `MCREX:a;`
- `a`: MACRO1–100

**Response:** `ACK;`

### QMCRST - Check If Macro Is Being Executed
**Transmit:** `QMCRST:a;`
- `a`: MACRO1–100

**Response:** `MCRST:a,b;ACK;`
- `a`: MACRO1–100
- `b`: OFF, ON

### SEQSW - Set Sequencer ON/OFF
**Transmit:** `SEQSW:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QSEQSW - Get Sequencer Status
**Transmit:** `QSEQSW;`

**Response:** `SQS:a;ACK;`
- `a`: OFF, ON

### SEQAS - Set Sequencer Auto Sequence ON/OFF
**Transmit:** `SEQAS:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QSEQAS - Get Sequencer Auto Sequence Status
**Transmit:** `QSEQAS;`

**Response:** `SQA:a;ACK;`
- `a`: OFF, ON

### SEQPV - Set Sequencer to Previous

**Variant 1:** `SEQPV;`
**Response:** `ACK;`

**Variant 2:** `SEQPV:a;`
- `a`: 0–1
  - 0: set sequence back one
  - 1: set sequence to beginning
**Response:** `ACK;`

### SEQNX - Advance Sequencer by One
**Transmit:** `SEQNX;`

**Response:** `ACK;`

### SEQJP - Set Sequencer Number
**Transmit:** `SEQJP:a;`
- `a`: START, SEQ1–1000

**Response:** `ACK;`

### GPNC - Graphics Presenter: Select Next Content
**Transmit:** `GPNC;`

**Response:** `ACK;`

### GPSC - Graphics Presenter: Select Content
**Transmit:** `GPSC:a;`
- `a`: CONTENT1–124

**Response:** `ACK;`

### GPHF - Graphics Presenter: Hide Front Content
**Transmit:** `GPHF;`

**Response:** `ACK;`

### GPHB - Graphics Presenter: Hide Background Content
**Transmit:** `GPHB;`

**Response:** `ACK;`

### GPOA - Graphics Presenter: Toggle ON AIR
**Transmit:** `GPOA;`

**Response:** `ACK;`

---

## SYSTEM Commands

### ACS - Return ACK
**Transmit:** `ACS;`

**Response:** `ACK;`

### VER - Get Model Name and Version Number
**Transmit:** `VER;`

**Response:** `VER:a,b;ACK;`
- `a`: V-160HD (Model name)
- `b`: 1.00– (Version number)

**Example:**
- Transmit: `VER;`
- Response: `VER:V-160HD,2.00;ACK;` (V-160HD version 2.00)

### QBSY - Get Busy Status
**Transmit:** `QBSY;`

**Response:** `BSY:a;`
- `a`: OFF, ON

### HDCP - Set HDCP ON/OFF
**Transmit:** `HDCP:a;`
- `a`: OFF, ON

**Response:** `ACK;`

### QHDCP - Get HDCP Status
**Transmit:** `QHDCP;`

**Response:** `HCP:a;ACK;`
- `a`: OFF, ON

### TPT - Set Test Pattern
**Transmit:** `TPT:a;`
- `a`: OFF, COLORBAR75, COLORBAR100, RAMP, STEP, HATCH, DIAMOND, CIRCLE, COLORBAR75-SP, COLORBAR100-SP, RAMP-SP, STEP-SP, HATCH-SP

**Response:** `ACK;`

### QTPT - Get Test Pattern Status
**Transmit:** `QTPT;`

**Response:** `TPT:a;ACK;`
- `a`: OFF, COLORBAR75, COLORBAR100, RAMP, STEP, HATCH, DIAMOND, CIRCLE, COLORBAR75-SP, COLORBAR100-SP, RAMP-SP, STEP-SP, HATCH-SP

### TTN - Set Test Tone

**Variant 1:** `TTN:a;`
- `a`: OFF, -20, -10, 0dB
**Response:** `ACK;`

**Variant 2:** `TTN:a,b,c;`
- `a`: OFF, -20, -10, 0dB (Test Tone Level)
- `b`: 500, 1k, 2kHz (Test Tone Frequency L)
- `c`: 500, 1k, 2kHz (Test Tone Frequency R)
**Response:** `ACK;`

### QTTN - Get Test Tone Level
**Transmit:** `QTTN;`

**Response:** `TTN:a,b,c;ACK;`
- `a`: OFF, -20, -10, 0dB (Test Tone Level)
- `b`: 500, 1k, 2kHz (Test Tone Frequency L)
- `c`: 500, 1k, 2kHz (Test Tone Frequency R)

---

## Notes for Implementation

1. **Command Termination**: All commands end with semicolon (`;`). Responses include `ACK;` followed by carriage return (0x0A, LF, `\n`).

2. **Parameter Encoding**:
   - Decimal values represent tenths (e.g., 10 = 1.0 seconds, -60 = -6.0 dB)
   - Negative infinity for audio levels is represented as `-INF`

3. **Input Channels**: V-160HD supports INPUT1–20 as logical input assignments that map to physical inputs (HDMI1–8, SDI1–8, STILL1–16).

4. **PinP/DSK Count**: V-160HD supports 4 PinP layers (PinP1–4) and 2 DSK layers (DSK1–2).

5. **AUX Buses**: V-160HD has 3 AUX buses (AUX1–3).

6. **SPLIT**: V-160HD supports 2 SPLIT configurations (SPLIT1–2).

7. **Camera Control**: V-160HD supports up to 16 PTZ cameras (CAMERA1–16) with 10 presets each (PRESET1–10).

8. **Scene Memory**: V-160HD has 30 scene memory slots (MEMORY1–30).

9. **Response Format**: Query commands (starting with Q) return their corresponding set command format with `;ACK;` appended.