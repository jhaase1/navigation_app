# Roland V-160HD LAN Control Commands

## LAN Interface

Connect via Telnet to the **LAN CONTROL port**, TCP port **8023**.

---

## Command Format

```
stx | Command code | : | Parameter , Parameter ; 
```

- **stx**: ASCII control code `02H` indicating start of command. When controlling via LAN (Telnet), stx **may be omitted**.
- **Command code**: Three single-byte alphanumeric characters.
- **Parameters**: Separated by `:` (colon) from the command code, and by `,` (comma) from each other.
- **Terminator**: `;` (semicolon) ends the command.

Control codes: stx (02H), ack (06H), xon (11H), xoff (13H).

---

## Commands

### DTH — Parameter Write (SysEx-supported)

**Transmit:** `DTH:a,b;`
- `a`: SysEx address (hexadecimal, three bytes)
- `b`: Setting value (hexadecimal)

**Response:** `ack`

**Example:**
- Setting `01H` to address `12H 34H 56H` → `DTH:123456,01;`

---

### RQH — Parameter Value Retrieve (SysEx-supported)

**Transmit:** `RQH:a,b;`
- `a`: SysEx address (hexadecimal, three bytes)
- `b`: Request size (hexadecimal, three bytes)

**Response:** `DTH:a,c;`
- `a`: SysEx address
- `c`: Setting value (hexadecimal)

---

### VER — Version Information

**Transmit:** `VER;`

**Response:** `VER:a,b;`
- `a`: Product name (`V-160HD`)
- `b`: Version number (e.g. `1.00`)

---

## Error Responses (sent spontaneously by V-160HD)

**Response:** `ERR:a;`
- `0`: Syntax error — received command contains an error
- `4`: Invalid — no effect because it is controlled by another setting
- `5`: Out of range error — an argument is out of range
- `6`: No stx error — command lacks stx prefix *(RS-232 only)*

---

## Notes

- SysEx addresses and their meaning of value are defined in the **MIDI Parameter Address Map** (see `V-160HD_Control_eng06_W.pdf`, p. 3).
- All commands are ASCII. The LAN and RS-232 interfaces share the same command set.
- Flow control: `xon` / `xoff`.
