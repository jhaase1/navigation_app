# Panasonic AW-UE100 Camera Control API

## Communication Setup

### IP Communication Format

**Pan/Tilt Commands:**
```
http://[IP_Address]/cgi-bin/aw_ptz?cmd=[Command]&res=1
```

**Camera Commands:**
```
http://[IP_Address]/cgi-bin/aw_cam?cmd=[Command]&res=1
```

**Note:** In IP communication, `#` must be URL encoded as `%23`

### Response Format
```
200 OK "[Command Response]"
```

### Command Type Reference
- **ptz** — Pan/Tilt control commands (use `/cgi-bin/aw_ptz`)
- **cam** — Camera control commands (use `/cgi-bin/aw_cam`)

### Data Notation
- Hexadecimal values are indicated with 'h' suffix (e.g., `00h-99h`)
- Data ranges shown as `0x[Data]` in responses indicate hexadecimal format

---

## 1. Power & System Control

### Power On/Off
```
Command: #O[Data]
- Data: 0 = Standby, 1 = Power On
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23O1&res=1
Response: p1 (Power On) or p0 (Standby)
```

### Get Camera Info
```
Request: QID
Response: OID:AW-UE100
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=QID&res=1
```

### Get Version
```
Request: QSV
Response: OSV:[Version]
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=QSV&res=1
```

---

## 2. Pan/Tilt Control

### Pan Speed Control
```
Command: #P[Speed]
- Speed: 01-49 (Left), 50 (Stop), 51-99 (Right)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23P75&res=1
Response: pS75
```

### Tilt Speed Control
```
Command: #T[Speed]
- Speed: 01-49 (Down), 50 (Stop), 51-99 (Up)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23T25&res=1
Response: tS25
```

### Pan/Tilt Combined Speed Control
```
Command: #PTS[PanSpeed][TiltSpeed]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PTS5075&res=1
- Pan: 50 (stop), Tilt: 75 (up)
```

### Absolute Position Control
```
Command: #APC[PanPos][TiltPos]
- Pan: 0000-FFFF (CCW Limit to CW Limit, 8000 = Center)
- Tilt: 0000-FFFF (Up Limit to Down Limit, 8000 = Center)
- Pan Range: 2D09 (-175°) to D2F5 (+175°)
- Tilt Range: 5555 (-30°) to 8E38 (+90°)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23APC80008000&res=1
```

### Absolute Position with Speed
```
Command: #APS[PanPos][TiltPos][Speed][SpeedTable]
- Speed: 00-1D (1-30)
- SpeedTable: 0=SLOW, 1=MID, 2=FAST
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23APS800080001D0&res=1
```

### Install Position (Flip)
```
Command: #INS[Data]
- Data: 0 = Desktop, 1 = Hanging
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23INS1&res=1
```

---

## 3. Zoom Control

### Zoom Speed Control
```
Command: #Z[Speed]
- Speed: 01-49 (Wide), 50 (Stop), 51-99 (Tele)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23Z75&res=1
Response: zS75
```

### Zoom Position Control
```
Command: #AXZ[Position]
- Position: 555-FFF (Wide to Tele)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23AXZ555&res=1
Response: axz555
```

### Digital Zoom
```
Control: OSE:70:[Data]
- Data: 0 = Disable, 1 = Enable
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:70:1&res=1
```

### Digital Zoom Magnification
```
Control: OSE:76:[Data]
- Data: 0100-9999 (x1.00 to x99.99)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:76:0200&res=1
```

---

## 4. Focus Control

### Focus Mode
```
Command: OAF:[Data] or #D1[Data]
- Data: 0 = Manual, 1 = Auto
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OAF:1&res=1
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23D11&res=1
```

### Focus Speed Control (Manual Mode)
```
Command: #F[Speed]
- Speed: 01-49 (Near), 50 (Stop), 51-99 (Far)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23F75&res=1
```

### Focus Position Control
```
Command: #AXF[Position]
- Position: 555-FFF (Near to Far)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23AXF800&res=1
```

### Push Auto Focus
```
Control: OSE:69:1
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:69:1&res=1
```

---

## 5. Iris Control

### Iris Mode
```
Command: ORS:[Data] or #D3[Data]
- Data: 0 = Manual, 1 = Auto
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=ORS:1&res=1
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23D31&res=1
```

### Iris Position Control (Manual Mode)
```
Command: #AXI[Position]
- Position: 555-FFF (Close to Open)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23AXI800&res=1
```

### Iris Speed Control
```
Command: #I[Speed]
- Speed: 01-99 (Close to Open)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23I50&res=1
```

---

## 6. Preset Management

### Recall Preset (`#R`)
```
Command: #R[PresetNum]
- PresetNum: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23R07&res=1
Response: s07 (immediate), then q07 (on completion via update notification)
```

### Save Preset (`#M`)
```
Command: #M[PresetNum]
- PresetNum: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23M07&res=1
Response: s07
```

### Delete Preset (`#C`)
```
Command: #C[PresetNum]
- PresetNum: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23C07&res=1
Response: s07
```

### Preset Completion Notification (`q`)
Sent automatically as an update notification when preset playback completes.
```
Response: q[Data]
- Data: 00-99 (Preset 1-100)
Update Notification: Yes
```

### Preset Entry Confirmation (`#PE`)
Checks which preset slots have saved data.
```
Request: #PE[Data1]
Response: pE[Data1][Data2]
- Data1: 00h-02h (each covers 40 presets)
- Data2: 0000000000h-FFFFFFFFFFh (40-bit field; bit0 = first preset in range, 0=empty, 1=saved)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PE00&res=1
Update Notification: Yes (pE00[Data2], pE01[Data2], pE02[Data2])
```

### Request Latest Recall Preset No. (`#S`)
```
Request: #S
Response: s[Data]
- Data: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23S&res=1
Update Notification: Yes
```

### Preset Speed Unit (`OSJ:29`)
Selects whether preset speed is controlled by speed table or time.
```
Control: OSJ:29:[Data]
Request: QSJ:29
- Data: 0 = Speed Table, 1 = Time
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:29:0&res=1
Response: OSJ:29:[Data]
Update Notification: Yes
```

### Preset Speed Table (`#PST`)
Selects the speed table (Slow/Fast).
```
Control: #PST[Data]
Request: #PST
- Data: 0 = Slow, 2 = Fast
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PST0&res=1
Response: pST[Data]
Update Notification: Yes
```

### Preset Speed (`#UPVS`)
```
Control: #UPVS[Data]
Request: #UPVS
- Data: 000-999
  - Speed Table mode: 001-063h (1=Slow, 30=Fast)
  - Time mode: 1-99 seconds
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23UPVS250&res=1
Response: uPVS[Data]
Update Notification: Yes
```

### Preset Acceleration (`OSJ:A8`)
```
Control: OSJ:A8:[Data]
Request: QSJ:A8
- Data: 0 = Manual, 1 = Auto
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:A8:0&res=1
Response: OSJ:A8:[Data]
Update Notification: Yes
```

### Preset Rise S-Curve (`OSJ:A9`)
Available when Preset Acceleration is Manual.
```
Control: OSJ:A9:[Data]
Request: QSJ:A9
- Data: 00h-1Eh (0-30)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:A9:00&res=1
Response: OSJ:A9:0x[Data]
Update Notification: Yes
```

### Preset Fall S-Curve (`OSJ:AA`)
Available when Preset Acceleration is Manual.
```
Control: OSJ:AA:[Data]
Request: QSJ:AA
- Data: 00h-1Eh (0-30)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AA:00&res=1
Response: OSJ:AA:0x[Data]
Update Notification: Yes
```

### Preset Rise Acceleration (`OSJ:AB`)
Available when Preset Acceleration is Manual AND Speed Unit is Speed.
```
Control: OSJ:AB:[Data]
Request: QSJ:AB
- Data: 01h-FFh (1-255)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AB:01&res=1
Response: OSJ:AB:0x[Data]
Update Notification: Yes
```

### Preset Fall Acceleration (`OSJ:AC`)
Available when Preset Acceleration is Manual AND Speed Unit is Speed.
```
Control: OSJ:AC:[Data]
Request: QSJ:AC
- Data: 01h-FFh (1-255)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AC:01&res=1
Response: OSJ:AC:0x[Data]
Update Notification: Yes
```

### Preset Rise Ramp Time (`OSJ:AD`)
Available when Preset Acceleration is Manual AND Speed Unit is Time.
```
Control: OSJ:AD:[Data]
Request: QSJ:AD
- Data: 01h-64h (0.1s - 10.0s)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AD:01&res=1
Response: OSJ:AD:0x[Data]
Update Notification: Yes
```

### Preset Fall Ramp Time (`OSJ:AE`)
Available when Preset Acceleration is Manual AND Speed Unit is Time.
```
Control: OSJ:AE:[Data]
Request: QSJ:AE
- Data: 01h-64h (0.1s - 10.0s)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AE:01&res=1
Response: OSJ:AE:0x[Data]
Update Notification: Yes
```

### Preset Scope (`OSE:71`)
Determines which camera settings are saved/recalled with presets.
```
Control: OSE:71:[Data]
Request: QSE:71
- Data: 0 = MODE A, 1 = MODE B, 2 = MODE C
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:71:0&res=1
Response: OSE:71:[Data]
Update Notification: Yes
```

### Preset Digital Extender (`OSE:7C`)
```
Control: OSE:7C:[Data]
Request: QSE:7C
- Data: 0 = Off, 1 = On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:7C:0&res=1
Response: OSE:7C:[Data]
Update Notification: Yes
```

### Preset Crop (`OSJ:2A`)
Available when Format is 2160/○○ AND UHD Crop is Crop(1080)/Crop(720).
```
Control: OSJ:2A:[Data]
Request: QSJ:2A
- Data: 0 = Off, 1 = On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:2A:0&res=1
Response: OSJ:2A:0x[Data]
Update Notification: Yes
```

### Preset Iris (`OSJ:5B`)
Available when Preset Scope is Mode A/Mode B.
```
Control: OSJ:5B:[Data]
Request: QSJ:5B
- Data: 0 = Off, 1 = On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:5B:0&res=1
Response: OSJ:5B:[Data]
Update Notification: Yes
```

### Preset Zoom Mode (`OSE:7D`)
```
Control: OSE:7D:[Data]
Request: QSE:7D
- Data: 0 = Mode A, 1 = Mode B
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:7D:0&res=1
Response: OSE:7D:[Data]
Update Notification: Yes
```

### Freeze During Preset (`#PRF`)
Freezes video output during preset playback.
```
Control: #PRF[Data]
Request: #PRF
- Data: 0 = Off, 1 = On
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PRF0&res=1
Response: pRF[Data]
Update Notification: Yes
```

### Save Preset Name (`OSJ:35`)
```
Control: OSJ:35:[Data1]:[Data2]
Request: QSJ:35:[Data1]
- Data1: 00h-99h (Preset 1-100)
- Data2: Preset Name (fixed 15 ASCII characters)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:35:00:MyPresetName123&res=1
Response: OSJ:35:[Data1]:[Data2]
Update Notification: No
```

### Delete Preset Name — Single (`OSJ:36`)
```
Control: OSJ:36:[Data1]
- Data1: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:36:00&res=1
Response: OSJ:36:[Data]
Update Notification: No
```

### Delete Preset Name — All (`OSJ:37`)
```
Control: OSJ:37
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:37&res=1
Response: OSJ:37
Update Notification: No
```

### Preset Thumbnail Auto-Update (`OSJ:2B`)
```
Control: OSJ:2B:[Data]
Request: QSJ:2B
- Data: 0 = Off, 1 = On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:2B:0&res=1
Response: OSJ:2B:0x[Data]
Update Notification: Yes
```

### Update Preset Thumbnail (`OSJ:39`)
```
Control: OSJ:39:[Data1]
- Data1: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:39:00&res=1
Response: OSJ:39:[Data]
Update Notification: No
```

### Delete Preset Thumbnail — Single (`OSJ:3A`)
```
Control: OSJ:3A:[Data1]
- Data1: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:3A:00&res=1
Response: OSJ:3A:[Data]
Update Notification: No
```

### Delete Preset Thumbnail — All (`OSJ:3B`)
```
Control: OSJ:3B
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:3B&res=1
Response: OSJ:3B
Update Notification: No
```

### Preset Name/Thumbnail Status Counter (`OSJ:3C`)
Queries name and thumbnail status for a range of presets.
```
Request: QSJ:3C:[Data1]
Response: OSJ:3C:[Data1]:[Data2]
- Data1 ranges:
  00h = Preset 001-009 | 01h = Preset 010-018 | 02h = Preset 019-027
  03h = Preset 028-036 | 04h = Preset 037-045 | 05h = Preset 046-054
  06h = Preset 055-063 | 07h = Preset 064-072 | 08h = Preset 073-081
  09h = Preset 082-090 | 0Ah = Preset 091-099 | 0Bh = Preset 100
- Data2: 000000000h-FFFFFFFFFh (status bits)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=QSJ:3C:00&res=1
Update Notification: No
```

### Power On Position (`OSJ:45`)
```
Control: OSJ:45:[Data]
Request: QSJ:45
- Data: 1 = Standby, 2 = Home, 3 = Preset
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:45:1&res=1
Response: OSJ:45:[Data]
Update Notification: Yes
```

### Power On Preset Number (`OSJ:46`)
Available when Power On Position is set to Preset.
```
Control: OSJ:46:[Data]
Request: QSJ:46
- Data: 00-99 (Preset 1-100)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:46:00&res=1
Response: OSJ:46:[Data]
Update Notification: Yes
```

---

## 7. Exposure Control

### Gain
```
Control: OGU:[Data]
- Data: 08-32 (0dB to 42dB), 80 (AGC Auto)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OGU:10&res=1
```

### Shutter Mode
```
Control: OSJ:03:[Data]
- Data: 0=Off, 1=Step, 2=Synchro, 3=ELC
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:03:1&res=1
```

### Shutter Speed (Step Mode)
```
Control: OSJ:06:[Data]
- Data: Hexadecimal denominator (e.g., 003C = 1/60)
- Available: 1/60, 1/100, 1/120, 1/250, 1/500, 1/1000, 1/2000, 1/4000, 1/8000, 1/10000
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:06:003C&res=1
```

### ND Filter
```
Control: OFT:[Data]
- Data: 0=Through, 1=1/4 ND, 2=1/16 ND, 3=1/64 ND
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OFT:1&res=1
```

---

## 8. White Balance

### White Balance Mode
```
Control: OAW:[Data]
- Data: 0=ATW, 1=AWC A, 2=AWC B, 4=3200K, 5=5600K, 9=VAR
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OAW:1&res=1
```

### Auto White Balance Execute
```
Control: OWS
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OWS&res=1
Response: OWS (immediate), then OWS (on completion)
```

### Color Temperature (VAR Mode)
```
Control: OSI:20:[Temp]:[Status]
- Temp: 007D0-03A98 (2000K-15000K in hex)
- Status: 0=Valid, 1=Under, 2=Over
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSI:20:0157C:0&res=1
```

### R/B Gain
```
Control: OSG:39:[Data] (R Gain)
Control: OSG:3A:[Data] (B Gain)
- Data: 738-8C8 (-200 to +200, 800 = 0)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=OSG:39:800&res=1
```

---

## 9. Scene Files

### Scene Selection
```
Control: XSF:[Data]
- Data: 0-4 (Scene 1-5, 0=-)
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=XSF:1&res=1
```

---

## 10. Output & Display

### Color Bar
```
Control: DCB:[Data]
- Data: 0=Camera, 1=Color Bar
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=DCB:1&res=1
```

### Tally Control
```
Command: #TAE[Data] (Enable/Disable)
- Data: 0=Disable, 1=Enable
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23TAE1&res=1

Control: TLR:[Data] (Red Tally)
- Data: 0=Off, 1=On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=TLR:1&res=1

Control: TLG:[Data] (Green Tally)
- Data: 0=Off, 1=On
Example: http://192.168.0.10/cgi-bin/aw_cam?cmd=TLG:1&res=1
```

---

## 11. Status Query Commands

### Get Pan/Tilt/Zoom/Focus/Iris
```
Request: #PTV
Response: pTV[Pan][Tilt][Zoom][Focus][Iris]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PTV&res=1
```

### Get Zoom Position
```
Request: #GZ
Response: gz[Position]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23GZ&res=1
```

### Get Focus Position
```
Request: #GF
Response: gf[Position]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23GF&res=1
```

### Get Iris Position
```
Request: #GI
Response: gi[Position][Mode]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23GI&res=1
```

### Lens Position Information (Continuous)
```
Control: #LPC[Data]
- Data: 0=Off, 1=On (sends updates every 300ms)
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23LPC1&res=1
Response: lPI[Zoom][Focus][Iris] (3 digits each)
```

### Error Status
```
Request: #RER
Response: rER[ErrorCode]
Example: http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23RER&res=1
```

---

## 12. Update Notifications (Event System)

### Start Receiving Notifications
```
http://[IP]/cgi-bin/event?connect=start&my_port=[Port]&uid=0
Response: 204 No Content
```

### Stop Receiving Notifications
```
http://[IP]/cgi-bin/event?connect=stop&my_port=[Port]&uid=0
Response: 204 No Content
```

### Notification Format (TCP)
Notifications are sent to the specified TCP port:
```
[CR][LF][Command Response][CR][LF]
```

---

## 13. Batch Information Retrieval

### Get All Camera Data
```
http://[IP]/live/camdata.html
Response: 200 OK with complete camera status
```

---

## Error Responses

- **ER1**: Unsupported command
- **ER2**: Busy status (e.g., camera in standby)
- **ER3**: Parameter outside acceptable range

---

## Important Restrictions

1. **Pan/Tilt Commands**: Send with 40ms gap between commands
2. **HTTP Keep-Alive**: Not supported — connect/disconnect each time
3. **URL Encoding**: `#` must be encoded as `%23` in IP communication
4. **Command Rate**: Only send setting changes when needed, not at regular intervals

---

## Common Use Case Examples

### Basic Camera Setup
```bash
# Power on
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23O1&res=1

# Set auto focus
http://192.168.0.10/cgi-bin/aw_cam?cmd=OAF:1&res=1

# Set auto iris
http://192.168.0.10/cgi-bin/aw_cam?cmd=ORS:1&res=1

# Set white balance to auto
http://192.168.0.10/cgi-bin/aw_cam?cmd=OAW:0&res=1
```

### Simple PTZ Control
```bash
# Pan right at medium speed
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23P75&res=1

# Stop pan
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23P50&res=1

# Zoom in
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23Z75&res=1

# Zoom stop
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23Z50&res=1
```

### Preset Workflow
```bash
# Move to position
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23APC80008000&res=1

# Save as preset 1
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23M00&res=1

# Recall preset 1
http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23R00&res=1
```
