# Panasonic AW-UE100 Preset Commands Reference

## Overview
This document contains all commands related to camera preset functionality for the Panasonic AW-UE100 HD/4K Integrated Camera.

---

## Basic Preset Operations

### Recall Preset Memory (`#R`)
**Command Type:** ptz  
**Description:** Recalls/plays back a saved preset position

- **Control:** `#R[Data]`
- **Response:** `s[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23R00&res=1`
- **Update Notification:** No

### Save Preset Memory (`#M`)
**Command Type:** ptz  
**Description:** Saves the current camera position to a preset slot

- **Control:** `#M[Data]`
- **Response:** `s[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23M00&res=1`
- **Update Notification:** No

### Delete Preset Memory (`#C`)
**Command Type:** ptz  
**Description:** Deletes a saved preset

- **Control:** `#C[Data]`
- **Response:** `s[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23C00&res=1`
- **Update Notification:** No

### Preset Completion Notification (`q`)
**Command Type:** ptz  
**Description:** Notification sent when preset playback is completed

- **Response:** `q[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Note:** This is an update notification sent automatically upon completion
- **Update Notification:** Yes

---

## Preset Status & Information

### Preset Entry Confirmation (`#PE`)
**Command Type:** ptz  
**Description:** Checks which presets have been saved

- **Request:** `#PE[Data1]`
- **Response:** `pE[Data1][Data2]`
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PE00&res=1`

**Data Format:**
- `[Data1]`: `00h-02h` (multiple, each 40 Preset No)
- `[Data2]`: `0000000000h-FFFFFFFFFFh` (40-bit field)
  - Each bit represents a preset (0=No Entry, 1=Entry)
  - bit0 = PRESET No.(Data1×40 + 1)
  - bit1 = PRESET No.(Data1×40 + 2)
  - ...
  - bit39 = PRESET No.(Data1×40 + 40)

**Update Notification:** Yes (`pE00[Data2]`, `pE01[Data2]`, `pE02[Data2]`)

### Request Latest Recall Preset No. (`#S`)
**Command Type:** ptz  
**Description:** Queries the most recently recalled preset number

- **Request:** `#S`
- **Response:** `s[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23S&res=1`
- **Update Notification:** Yes (`s[Data]`)

---

## Preset Speed Settings

### Preset Speed Unit (`OSJ:29`)
**Command Type:** cam  
**Description:** Selects whether preset speed is controlled by speed table or time

- **Control:** `OSJ:29:[Data]`
- **Response:** `OSJ:29:[Data]`
- **Request:** `QSJ:29`
- **Values:**
  - `0` - Speed Table
  - `1` - Time
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:29:0&res=1`
- **Update Notification:** Yes (`OSJ:29:[Data]`)

### Preset Speed Table (`#PST`)
**Command Type:** ptz  
**Description:** Selects the preset speed table (Slow/Fast)

- **Control:** `#PST[Data]`
- **Response:** `pST[Data]`
- **Request:** `#PST`
- **Values:**
  - `0` - Slow
  - `2` - Fast
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PST0&res=1`
- **Update Notification:** Yes (`pST[Data]`)

### Preset Speed (`#UPVS`)
**Command Type:** ptz  
**Description:** Sets the preset speed value

- **Control:** `#UPVS[Data]`
- **Response:** `uPVS[Data]`
- **Request:** `#UPVS`
- **Data Range:** `000-999`
- **Values:**
  - **Speed Unit = Speed Table:** `001-063h` (30 = MaxSpeed, 1 = Slow, 30 = Fast)
  - **Speed Unit = Time:** `1-99` seconds
- **Speed Mapping (Speed Table Mode):**
  - 001-275: Speed 1
  - 276-301: Speed 2
  - 302-327: Speed 3
  - ... (continues in increments)
  - 974-998: Speed 29
  - 999-000: Speed 30
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23UPVS250&res=1`
- **Update Notification:** Yes (`uPVS[Data]`)

---

## Preset Acceleration Settings

### Preset Acceleration (`OSJ:A8`)
**Command Type:** cam  
**Description:** Enables/disables manual acceleration control

- **Control:** `OSJ:A8:[Data]`
- **Response:** `OSJ:A8:[Data]`
- **Request:** `QSJ:A8`
- **Values:**
  - `0` - Manual
  - `1` - Auto
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:A8:0&res=1`
- **Update Notification:** Yes (`OSJ:A8:[Data]`)

### Preset Rise S-Curve (`OSJ:A9`)
**Command Type:** cam  
**Description:** Sets the acceleration curve at the start of preset movement
**Available When:** Preset Acceleration is Manual

- **Control:** `OSJ:A9:[Data]`
- **Response:** `OSJ:A9:[Data]`
- **Request:** `QSJ:A9`
- **Data Range:** `00h-1E` (0-30)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:A9:00&res=1`
- **Update Notification:** Yes (`OSJ:A9:0x[Data]`)

### Preset Fall S-Curve (`OSJ:AA`)
**Command Type:** cam  
**Description:** Sets the deceleration curve at the end of preset movement
**Available When:** Preset Acceleration is Manual

- **Control:** `OSJ:AA:[Data]`
- **Response:** `OSJ:AA:[Data]`
- **Request:** `QSJ:AA`
- **Data Range:** `00h-1E` (0-30)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AA:00&res=1`
- **Update Notification:** Yes (`OSJ:AA:0x[Data]`)

### Preset Rise Acceleration (`OSJ:AB`)
**Command Type:** cam  
**Description:** Sets the acceleration value at the start of preset movement
**Available When:** Preset Acceleration is Manual AND Preset Speed Unit is Speed

- **Control:** `OSJ:AB:[Data]`
- **Response:** `OSJ:AB:[Data]`
- **Request:** `QSJ:AB`
- **Data Range:** `01h-FFh` (1-255)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AB:01&res=1`
- **Update Notification:** Yes (`OSJ:AB:0x[Data]`)

### Preset Fall Acceleration (`OSJ:AC`)
**Command Type:** cam  
**Description:** Sets the deceleration value at the end of preset movement
**Available When:** Preset Acceleration is Manual AND Preset Speed Unit is Speed

- **Control:** `OSJ:AC:[Data]`
- **Response:** `OSJ:AC:[Data]`
- **Request:** `QSJ:AC`
- **Data Range:** `01h-FFh` (1-255)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AC:01&res=1`
- **Update Notification:** Yes (`OSJ:AC:0x[Data]`)

### Preset Rise Ramp Time (`OSJ:AD`)
**Command Type:** cam  
**Description:** Sets the acceleration time at the start of preset movement
**Available When:** Preset Acceleration is Manual AND Preset Speed Unit is Time

- **Control:** `OSJ:AD:[Data]`
- **Response:** `OSJ:AD:[Data]`
- **Request:** `QSJ:AD`
- **Data Range:** `01h-64h` (0.1s - 10.0s)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AD:01&res=1`
- **Update Notification:** Yes (`OSJ:AD:0x[Data]`)

### Preset Fall Ramp Time (`OSJ:AE`)
**Command Type:** cam  
**Description:** Sets the deceleration time at the end of preset movement
**Available When:** Preset Acceleration is Manual AND Preset Speed Unit is Time

- **Control:** `OSJ:AE:[Data]`
- **Response:** `OSJ:AE:[Data]`
- **Request:** `QSJ:AE`
- **Data Range:** `01h-64h` (0.1s - 10.0s)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:AE:01&res=1`
- **Update Notification:** Yes (`OSJ:AE:0x[Data]`)

---

## Preset Behavior Settings

### Preset Scope (`OSE:71`)
**Command Type:** cam  
**Description:** Determines which camera settings are saved/recalled with presets

- **Control:** `OSE:71:[Data]`
- **Response:** `OSE:71:[Data]`
- **Request:** `QSE:71`
- **Values:**
  - `0` - MODE A
  - `1` - MODE B
  - `2` - MODE C
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:71:0&res=1`
- **Update Notification:** Yes (`OSE:71:[Data]`)

### Preset Digital Extender (`OSE:7C`)
**Command Type:** cam  
**Description:** Enables/disables saving digital extender setting with presets

- **Control:** `OSE:7C:[Data]`
- **Response:** `OSE:7C:[Data]`
- **Request:** `QSE:7C`
- **Values:**
  - `0` - Off
  - `1` - On
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:7C:0&res=1`
- **Update Notification:** Yes (`OSE:7C:[Data]`)

### Preset Crop (`OSJ:2A`)
**Command Type:** cam  
**Description:** Enables/disables saving crop settings with presets
**Available When:** Format is 2160/○○ AND UHD Crop is Crop(1080)/Crop(720)

- **Control:** `OSJ:2A:[Data]`
- **Response:** `OSJ:2A:[Data]`
- **Request:** `QSJ:2A`
- **Values:**
  - `0` - Off
  - `1` - On
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:2A:0&res=1`
- **Update Notification:** Yes (`OSJ:2A:0x[Data]`)

### Preset Iris (`OSJ:5B`)
**Command Type:** cam  
**Description:** Enables/disables saving iris setting with presets
**Available When:** Preset Scope is Mode A/Mode B

- **Control:** `OSJ:5B:[Data]`
- **Response:** `OSJ:5B:[Data]`
- **Request:** `QSJ:5B`
- **Values:**
  - `0` - Off
  - `1` - On
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:5B:0&res=1`
- **Update Notification:** Yes (`OSJ:5B:[Data]`)

### Preset Zoom Mode (`OSE:7D`)
**Command Type:** cam  
**Description:** Selects the zoom mode for preset operation

- **Control:** `OSE:7D:[Data]`
- **Response:** `OSE:7D:[Data]`
- **Request:** `QSE:7D`
- **Values:**
  - `0` - Mode A
  - `1` - Mode B
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSE:7D:0&res=1`
- **Update Notification:** Yes (`OSE:7D:[Data]`)

### Freeze During Preset (`#PRF`)
**Command Type:** ptz  
**Description:** Freezes the video output during preset playback

- **Control:** `#PRF[Data]`
- **Response:** `pRF[Data]`
- **Request:** `#PRF`
- **Values:**
  - `0` - Off
  - `1` - On
- **Example:** `http://192.168.0.10/cgi-bin/aw_ptz?cmd=%23PRF0&res=1`
- **Update Notification:** Yes (`pRF[Data]`)

---

## Preset Names

### Save Preset Name (`OSJ:35`)
**Command Type:** cam  
**Description:** Assigns a custom name to a preset

- **Control:** `OSJ:35:[Data1]:[Data2]`
- **Response:** `OSJ:35:[Data1]:[Data2]`
- **Request:** `QSJ:35:[Data1]`
- **Data Format:**
  - `[Data1]`: `00h-99h` (Preset001 - Preset100)
  - `[Data2]`: Preset Name (Fixed 15 Characters)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:35:00:xxxxxxxxxxxxxxx&res=1`
- **Update Notification:** No

### Delete Preset Name (Single) (`OSJ:36`)
**Command Type:** cam  
**Description:** Deletes the name of a specific preset

- **Control:** `OSJ:36:[Data1]`
- **Response:** `OSJ:36:[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:36:00&res=1`
- **Update Notification:** No

### Delete Preset Name (All) (`OSJ:37`)
**Command Type:** cam  
**Description:** Deletes all preset names

- **Control:** `OSJ:37`
- **Response:** `OSJ:37`
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:37&res=1`
- **Update Notification:** No

---

## Preset Thumbnails

### Preset Thumbnail Update (`OSJ:2B`)
**Command Type:** cam  
**Description:** Enables/disables automatic thumbnail update when saving presets

- **Control:** `OSJ:2B:[Data]`
- **Response:** `OSJ:2B:[Data]`
- **Request:** `QSJ:2B`
- **Values:**
  - `0` - Off
  - `1` - On
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:2B:0&res=1`
- **Update Notification:** Yes (`OSJ:2B:0x[Data]`)

### Update Preset Thumbnail (`OSJ:39`)
**Command Type:** cam  
**Description:** Manually updates the thumbnail for a specific preset

- **Control:** `OSJ:39:[Data1]`
- **Response:** `OSJ:39:[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:39:00&res=1`
- **Update Notification:** No

### Delete Preset Thumbnail (Single) (`OSJ:3A`)
**Command Type:** cam  
**Description:** Deletes the thumbnail of a specific preset

- **Control:** `OSJ:3A:[Data1]`
- **Response:** `OSJ:3A:[Data]`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:3A:00&res=1`
- **Update Notification:** No

### Delete Preset Thumbnail (All) (`OSJ:3B`)
**Command Type:** cam  
**Description:** Deletes all preset thumbnails

- **Control:** `OSJ:3B`
- **Response:** `OSJ:3B`
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:3B&res=1`
- **Update Notification:** No

### Preset Name/Preset Thumbnail Counter (`OSJ:3C`)
**Command Type:** cam  
**Description:** Queries the status of preset names and thumbnails for a range of presets

- **Request:** `QSJ:3C:[Data1]`
- **Response:** `OSJ:3C:[Data1]:[Data2]`
- **Data Format:**
  - `[Data1]`: Preset range selector
    - `00h` - Preset 001-009
    - `01h` - Preset 010-018
    - `02h` - Preset 019-027
    - `03h` - Preset 028-036
    - `04h` - Preset 037-045
    - `05h` - Preset 046-054
    - `06h` - Preset 055-063
    - `07h` - Preset 064-072
    - `08h` - Preset 073-081
    - `09h` - Preset 082-090
    - `0Ah` - Preset 091-099
    - `0Bh` - Preset 100
  - `[Data2]`: `000000000h-FFFFFFFFFh` (status bits)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=QSJ:3C:00&res=1`
- **Update Notification:** No

---

## Power-On Preset Settings

### Power On Position (`OSJ:45`)
**Command Type:** cam  
**Description:** Determines camera position behavior when powered on

- **Control:** `OSJ:45:[Data]`
- **Response:** `OSJ:45:[Data]`
- **Request:** `QSJ:45`
- **Values:**
  - `1` - Standby
  - `2` - Home
  - `3` - Preset
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:45:1&res=1`
- **Update Notification:** Yes (`OSJ:45:[Data]`)

### Power On Preset Number (`OSJ:46`)
**Command Type:** cam  
**Description:** Selects which preset to recall on power-on
**Available When:** Power On Position is set to Preset

- **Control:** `OSJ:46:[Data]`
- **Response:** `OSJ:46:[Data]`
- **Request:** `QSJ:46`
- **Data Range:** `00-99` (Preset001 - Preset100)
- **Example:** `http://192.168.0.10/cgi-bin/aw_cam?cmd=OSJ:46:00&res=1`
- **Update Notification:** Yes (`OSJ:46:[Data]`)

---

## Notes

### Preset Playback Sequence
When a preset is recalled (e.g., #R07 for preset 08):
1. As soon as the command is received, the camera returns `s07` as the HTTP response
2. After the preset playback is completed, `q07` is posted as an update notification

### Command Type Reference
- **ptz** - Pan/Tilt control commands (use `/cgi-bin/aw_ptz`)
- **cam** - Camera control commands (use `/cgi-bin/aw_cam`)

### Data Notation
- Hexadecimal values are indicated with 'h' suffix (e.g., `00h-99h`)
- Data ranges shown as 0x[Data] in camdata.html indicate hexadecimal format

### Update Notifications
Commands marked with "Update Notification: Yes" will send automatic notifications to registered clients when the value changes. See Chapter 5 of the specification for details on setting up update notification reception.