"""Whoop BLE connect + battery + realtime HR test (v3 - matching whoomp protocol exactly)."""
import asyncio
import sys
import struct
import zlib
from bleak import BleakClient

# Whoop BLE UUIDs
WHOOP_SERVICE = "61080001-8d6d-82b8-614a-1c8cb0f8dcc6"
CMD_TO_STRAP = "61080002-8d6d-82b8-614a-1c8cb0f8dcc6"
CMD_FROM_STRAP = "61080003-8d6d-82b8-614a-1c8cb0f8dcc6"
EVENTS_CHAR = "61080004-8d6d-82b8-614a-1c8cb0f8dcc6"
DATA_CHAR = "61080005-8d6d-82b8-614a-1c8cb0f8dcc6"

# Packet types
TYPE_COMMAND = 35
TYPE_COMMAND_RESPONSE = 36
TYPE_REALTIME_DATA = 40
TYPE_HISTORICAL_DATA = 47
TYPE_EVENT = 48
TYPE_METADATA = 49

# Commands
CMD_TOGGLE_REALTIME_HR = 3
CMD_GET_CLOCK = 11
CMD_SEND_HISTORICAL_DATA = 22
CMD_GET_BATTERY_LEVEL = 26
CMD_GET_HELLO_HARVARD = 35

# CRC8 lookup table (exact copy from whoomp)
crc8tab = [
    0x00, 0x07, 0x0E, 0x09, 0x1C, 0x1B, 0x12, 0x15, 0x38, 0x3F, 0x36, 0x31, 0x24, 0x23, 0x2A, 0x2D,
    0x70, 0x77, 0x7E, 0x79, 0x6C, 0x6B, 0x62, 0x65, 0x48, 0x4F, 0x46, 0x41, 0x54, 0x53, 0x5A, 0x5D,
    0xE0, 0xE7, 0xEE, 0xE9, 0xFC, 0xFB, 0xF2, 0xF5, 0xD8, 0xDF, 0xD6, 0xD1, 0xC4, 0xC3, 0xCA, 0xCD,
    0x90, 0x97, 0x9E, 0x99, 0x8C, 0x8B, 0x82, 0x85, 0xA8, 0xAF, 0xA6, 0xA1, 0xB4, 0xB3, 0xBA, 0xBD,
    0xC7, 0xC0, 0xC9, 0xCE, 0xDB, 0xDC, 0xD5, 0xD2, 0xFF, 0xF8, 0xF1, 0xF6, 0xE3, 0xE4, 0xED, 0xEA,
    0xB7, 0xB0, 0xB9, 0xBE, 0xAB, 0xAC, 0xA5, 0xA2, 0x8F, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9D, 0x9A,
    0x27, 0x20, 0x29, 0x2E, 0x3B, 0x3C, 0x35, 0x32, 0x1F, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0D, 0x0A,
    0x57, 0x50, 0x59, 0x5E, 0x4B, 0x4C, 0x45, 0x42, 0x6F, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7D, 0x7A,
    0x89, 0x8E, 0x87, 0x80, 0x95, 0x92, 0x9B, 0x9C, 0xB1, 0xB6, 0xBF, 0xB8, 0xAD, 0xAA, 0xA3, 0xA4,
    0xF9, 0xFE, 0xF7, 0xF0, 0xE5, 0xE2, 0xEB, 0xEC, 0xC1, 0xC6, 0xCF, 0xC8, 0xDD, 0xDA, 0xD3, 0xD4,
    0x69, 0x6E, 0x67, 0x60, 0x75, 0x72, 0x7B, 0x7C, 0x51, 0x56, 0x5F, 0x58, 0x4D, 0x4A, 0x43, 0x44,
    0x19, 0x1E, 0x17, 0x10, 0x05, 0x02, 0x0B, 0x0C, 0x21, 0x26, 0x2F, 0x28, 0x3D, 0x3A, 0x33, 0x34,
    0x4E, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5C, 0x5B, 0x76, 0x71, 0x78, 0x7F, 0x6A, 0x6D, 0x64, 0x63,
    0x3E, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2C, 0x2B, 0x06, 0x01, 0x08, 0x0F, 0x1A, 0x1D, 0x14, 0x13,
    0xAE, 0xA9, 0xA0, 0xA7, 0xB2, 0xB5, 0xBC, 0xBB, 0x96, 0x91, 0x98, 0x9F, 0x8A, 0x8D, 0x84, 0x83,
    0xDE, 0xD9, 0xD0, 0xD7, 0xC2, 0xC5, 0xCC, 0xCB, 0xE6, 0xE1, 0xE8, 0xEF, 0xFA, 0xFD, 0xF4, 0xF3
]

def crc8(buf):
    """CRC8 using whoomp lookup table."""
    crc = 0
    for b in buf:
        crc = crc8tab[crc ^ b]
    return crc

def make_packet(ptype, cmd, data=b""):
    """Build a framed Whoop BLE packet — exact whoomp format.
    
    Payload: [type(1), seq(1), cmd(1), data(...)]
    Frame: SOF(1) + length(2 LE) + crc8(1) + payload + crc32(4 LE)
    """
    seq = 10  # whoomp uses fixed seq=10
    payload = struct.pack("<BBB", ptype, seq, cmd) + data
    blen = struct.pack("<H", len(payload) + 4)  # +4 for crc32
    crc32 = zlib.crc32(payload) & 0xFFFFFFFF
    return struct.pack("<B", 0xAA) + blen + struct.pack("<B", crc8(blen)) + payload + struct.pack("<L", crc32)

def parse_packet(raw):
    """Parse a framed Whoop BLE packet."""
    if len(raw) < 7 or raw[0] != 0xAA:
        return None
    length = struct.unpack("<H", raw[1:3])[0]
    pkt = raw[4:4+length-4]  # payload without crc32
    if len(pkt) < 3:
        return None
    return {
        "type": pkt[0],
        "seq": pkt[1],
        "cmd": pkt[2],
        "data": pkt[3:] if len(pkt) > 3 else b"",
        "raw": raw
    }

async def main():
    address = sys.argv[1] if len(sys.argv) > 1 else "F4:5E:FC:CF:87:EF"
    
    print(f"Connecting to Whoop at {address}...")
    print("(Make sure phone Bluetooth is OFF)\n")
    
    hr_values = []
    rr_values = []
    
    def handle_cmd(sender, data):
        """CMD_FROM_STRAP: battery, version, clock responses."""
        pkt = parse_packet(bytes(data))
        if not pkt:
            print(f"  [CMD raw] {data.hex()}")
            return
        
        cmd = pkt["cmd"]
        pdata = pkt["data"]
        
        if cmd == CMD_GET_BATTERY_LEVEL and len(pdata) >= 4:
            level = struct.unpack("<H", pdata[2:4])[0] / 10.0
            print(f"  🔋 Battery: {level:.1f}%")
        elif cmd == CMD_GET_CLOCK and len(pdata) >= 6:
            unix = struct.unpack("<L", pdata[2:6])[0]
            import datetime
            ts = datetime.datetime.fromtimestamp(unix).strftime("%Y-%m-%d %H:%M:%S")
            print(f"  🕐 Clock: {ts}")
        elif cmd == CMD_GET_HELLO_HARVARD and len(pdata) > 116:
            charging = bool(pdata[7])
            worn = bool(pdata[116])
            print(f"  📱 Worn: {worn}, Charging: {charging}")
        else:
            print(f"  [CMD] cmd={cmd} len={len(pdata)} hex={pdata.hex()[:80]}")
    
    def handle_events(sender, data):
        """EVENTS: wrist on/off, charging, double tap."""
        pkt = parse_packet(bytes(data))
        if not pkt:
            return
        
        event_names = {
            3: "BATTERY", 7: "CHARGING_ON", 8: "CHARGING_OFF",
            9: "WRIST_ON", 10: "WRIST_OFF", 14: "DOUBLE_TAP",
            33: "REALTIME_HR_ON", 34: "REALTIME_HR_OFF"
        }
        cmd = pkt["cmd"]
        name = event_names.get(cmd, f"EVENT_{cmd}")
        print(f"  📡 {name}")
    
    def handle_data(sender, data):
        """DATA: realtime HR, historical data, metadata."""
        pkt = parse_packet(bytes(data))
        if not pkt:
            print(f"  [DATA raw] {data.hex()[:80]}")
            return
        
        ptype = pkt["type"]
        cmd = pkt["cmd"]
        pdata = pkt["data"]
        
        if ptype == TYPE_REALTIME_DATA:
            # Whoomp format: cmd byte is part of the data structure
            # Reconstruct: [cmd] + data[:7] -> unpack as <LHBB
            recon = struct.pack("<B", cmd) + pdata[:7]
            if len(recon) >= 8:
                unix, subsec, heart, rrnum = struct.unpack("<LHBB", recon)
                
                if heart > 0:
                    hr_values.append(heart)
                    bar = "█" * (heart // 3)
                    print(f"  ❤️  HR: {heart} bpm  {bar}")
                
                # Extract RR intervals
                if rrnum > 0 and len(pdata) >= 7 + rrnum * 2:
                    rrs = []
                    for i in range(min(rrnum, 4)):
                        rr = struct.unpack("<H", pdata[7 + i*2 : 9 + i*2])[0]
                        if rr > 0:
                            rrs.append(rr)
                            rr_values.append(rr)
                    if rrs:
                        print(f"       RR: {rrs} ms")
        
        elif ptype == TYPE_EVENT:
            # Events can also come on DATA char
            event_names = {9: "WRIST_ON", 10: "WRIST_OFF", 33: "HR_ON", 34: "HR_OFF"}
            name = event_names.get(cmd, f"EVT_{cmd}")
            print(f"  📡 {name} (via DATA)")
        
        else:
            print(f"  [DATA] type={ptype} cmd={cmd} hex={pdata.hex()[:60]}")
    
    try:
        async with BleakClient(address, timeout=15) as client:
            print(f"✅ Connected! MTU: {client.mtu_size}")
            
            # Subscribe to notifications
            print("\nSubscribing...")
            await client.start_notify(CMD_FROM_STRAP, handle_cmd)
            await client.start_notify(EVENTS_CHAR, handle_events)
            await client.start_notify(DATA_CHAR, handle_data)
            print("  ✓ All subscribed\n")
            
            # --- Battery ---
            print("--- Battery ---")
            pkt = make_packet(TYPE_COMMAND, CMD_GET_BATTERY_LEVEL, b"\x00")
            print(f"  Sending: {pkt.hex()}")
            await client.write_gatt_char(CMD_TO_STRAP, pkt)
            await asyncio.sleep(2)
            
            # --- Clock ---
            print("\n--- Clock ---")
            pkt = make_packet(TYPE_COMMAND, CMD_GET_CLOCK, b"\x00")
            await client.write_gatt_char(CMD_TO_STRAP, pkt)
            await asyncio.sleep(1)
            
            # --- Hello Harvard (wrist status) ---
            print("\n--- Device Status ---")
            pkt = make_packet(TYPE_COMMAND, CMD_GET_HELLO_HARVARD, b"\x00")
            await client.write_gatt_char(CMD_TO_STRAP, pkt)
            await asyncio.sleep(2)
            
            # --- Start Realtime HR ---
            print("\n--- Starting Realtime HR (data=0x01) ---")
            pkt = make_packet(TYPE_COMMAND, CMD_TOGGLE_REALTIME_HR, b"\x01")
            print(f"  Sending: {pkt.hex()}")
            await client.write_gatt_char(CMD_TO_STRAP, pkt)
            
            # Stream for 30 seconds
            print("\nStreaming for 30 seconds...\n")
            for i in range(30):
                await asyncio.sleep(1)
                if i % 10 == 9:
                    print(f"  [{i+1}s] {len(hr_values)} HR readings so far")
            
            # --- Stop Realtime HR ---
            print("\n--- Stopping Realtime HR (data=0x00) ---")
            pkt = make_packet(TYPE_COMMAND, CMD_TOGGLE_REALTIME_HR, b"\x00")
            await client.write_gatt_char(CMD_TO_STRAP, pkt)
            await asyncio.sleep(1)
            
            # Summary
            print("\n" + "="*50)
            print("SESSION SUMMARY")
            print("="*50)
            
            if hr_values:
                avg = sum(hr_values) / len(hr_values)
                print(f"  HR Readings:  {len(hr_values)}")
                print(f"  Avg HR:       {avg:.0f} bpm")
                print(f"  Min HR:       {min(hr_values)} bpm")
                print(f"  Max HR:       {max(hr_values)} bpm")
            else:
                print("  No HR readings received.")
                print("  (Make sure strap is on wrist with good skin contact)")
            
            if rr_values:
                avg_rr = sum(rr_values) / len(rr_values)
                diffs = [abs(rr_values[i+1] - rr_values[i]) for i in range(len(rr_values)-1)]
                if diffs:
                    import math
                    rmssd = (sum(d**2 for d in diffs) / len(diffs)) ** 0.5
                    hrv_score = (math.log(rmssd) / 6.5) * 100 if rmssd > 0 else 0
                    print(f"  RR Intervals: {len(rr_values)}")
                    print(f"  RMSSD:        {rmssd:.1f} ms")
                    print(f"  HRV Score:    {hrv_score:.0f}")
            
            print(f"\n🎉 JAILBREAK TEST COMPLETE")
            print(f"   Address: {address}")
    
    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(main())
