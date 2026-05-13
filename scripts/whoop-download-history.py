"""Download all historical HR + RR data from Whoop strap via BLE.

Saves raw binary to whoop_hist.bin and parsed records to whoop_history.json.
Uses the exact whoomp protocol.
"""
import asyncio
import sys
import struct
import zlib
import json
import datetime
from bleak import BleakClient

# UUIDs
WHOOP_SERVICE = "61080001-8d6d-82b8-614a-1c8cb0f8dcc6"
CMD_TO_STRAP = "61080002-8d6d-82b8-614a-1c8cb0f8dcc6"
CMD_FROM_STRAP = "61080003-8d6d-82b8-614a-1c8cb0f8dcc6"
EVENTS_CHAR = "61080004-8d6d-82b8-614a-1c8cb0f8dcc6"
DATA_CHAR = "61080005-8d6d-82b8-614a-1c8cb0f8dcc6"

# Packet types
TYPE_COMMAND = 35
TYPE_COMMAND_RESPONSE = 36
TYPE_HISTORICAL_DATA = 47
TYPE_EVENT = 48
TYPE_METADATA = 49

# Commands
CMD_SEND_HISTORICAL_DATA = 22
CMD_HISTORICAL_DATA_RESULT = 23

# Metadata types
META_HISTORY_START = 1
META_HISTORY_END = 2
META_HISTORY_COMPLETE = 3

# CRC8 table
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
    crc = 0
    for b in buf:
        crc = crc8tab[crc ^ b]
    return crc

def make_packet(ptype, cmd, data=b""):
    seq = 10
    payload = struct.pack("<BBB", ptype, seq, cmd) + data
    blen = struct.pack("<H", len(payload) + 4)
    crc32 = zlib.crc32(payload) & 0xFFFFFFFF
    return struct.pack("<B", 0xAA) + blen + struct.pack("<B", crc8(blen)) + payload + struct.pack("<L", crc32)

def parse_packet(raw):
    if len(raw) < 7 or raw[0] != 0xAA:
        return None
    length = struct.unpack("<H", raw[1:3])[0]
    pkt = raw[4:4+length-4]
    if len(pkt) < 3:
        return None
    return {"type": pkt[0], "seq": pkt[1], "cmd": pkt[2], "data": pkt[3:] if len(pkt) > 3 else b"", "raw": raw}

def parse_historical_records(file_path):
    """Parse the raw binary history dump into records."""
    with open(file_path, "rb") as f:
        data = f.read()
    
    records = []
    dp = 0
    errors = 0
    
    while dp < len(data):
        if dp + 3 > len(data):
            break
        
        if data[dp] != 0xAA:
            dp += 1
            errors += 1
            continue
        
        try:
            length = struct.unpack("<H", data[dp+1:dp+3])[0] + 4  # +4 for crc32 at end? 
            # Actually whoomp does: length = struct.unpack("<H", data[dp + 1:dp + 3])[0] + 4
            # But the length field already includes crc32 in the payload count
            # Let me match whoomp parser exactly
            pkt_end = dp + 4 + length  # SOF(1) + len(2) + crc8(1) + length bytes
            
            if pkt_end > len(data):
                break
            
            # Parse packet
            pkt = parse_packet(data[dp:pkt_end])
            if pkt and pkt["type"] == TYPE_HISTORICAL_DATA:
                pdata = struct.pack("<B", pkt["cmd"]) + pkt["data"]
                
                if len(pdata) >= 11:
                    unix, subsec, unk, heart = struct.unpack("<LHLB", pdata[0:11])
                    
                    # RR intervals
                    rr = []
                    if len(pdata) > 12:
                        rrnum = pdata[11] if len(pdata) > 11 else 0
                        for i in range(min(rrnum, 4)):
                            if len(pdata) >= 14 + i*2:
                                rr_val = struct.unpack("<H", pdata[12+i*2:14+i*2])[0]
                                if rr_val > 0:
                                    rr.append(rr_val)
                    
                    if unix > 1600000000 and unix < 2000000000:  # sanity check
                        records.append({
                            "unix": unix,
                            "timestamp": datetime.datetime.fromtimestamp(unix).isoformat(),
                            "heart_rate": heart,
                            "rr_intervals": rr
                        })
            
            dp = pkt_end
        except Exception as e:
            dp += 1
            errors += 1
    
    print(f"  Parsed {len(records)} records ({errors} errors skipped)")
    return records

async def main():
    address = sys.argv[1] if len(sys.argv) > 1 else "F4:5E:FC:CF:87:EF"
    output_bin = "whoop_hist.bin"
    output_json = "whoop_history.json"
    
    print(f"Whoop Historical Data Download")
    print(f"Address: {address}")
    print(f"Output:  {output_bin} (raw) + {output_json} (parsed)\n")
    
    cmd_queue = asyncio.Queue()
    meta_queue = asyncio.Queue()
    hist_packets = []
    
    fp = open(output_bin, "wb")
    
    async def handle_cmd(sender, data):
        pkt = parse_packet(bytes(data))
        if pkt:
            await cmd_queue.put(pkt)
            print(f"  [CMD] cmd={pkt['cmd']} data={pkt['data'].hex()[:40]}")
    
    def handle_events(sender, data):
        pkt = parse_packet(bytes(data))
        if pkt:
            event_names = {9: "WRIST_ON", 10: "WRIST_OFF", 33: "HR_ON", 34: "HR_OFF"}
            name = event_names.get(pkt["cmd"], f"EVT_{pkt['cmd']}")
            print(f"  📡 {name}")
    
    async def handle_data(sender, data):
        pkt = parse_packet(bytes(data))
        if not pkt:
            return
        
        if pkt["type"] == TYPE_HISTORICAL_DATA:
            fp.write(data)
            fp.flush()
            hist_packets.append(pkt)
            if len(hist_packets) % 100 == 0:
                print(f"  📦 {len(hist_packets)} history packets received...")
        
        elif pkt["type"] == TYPE_METADATA:
            await meta_queue.put(pkt)
            meta_names = {1: "HISTORY_START", 2: "HISTORY_END", 3: "HISTORY_COMPLETE"}
            name = meta_names.get(pkt["cmd"], f"META_{pkt['cmd']}")
            print(f"  📋 Metadata: {name}")
    
    try:
        async with BleakClient(address, timeout=15) as client:
            print(f"✅ Connected! MTU: {client.mtu_size}\n")
            
            await client.start_notify(CMD_FROM_STRAP, handle_cmd)
            await client.start_notify(EVENTS_CHAR, handle_events)
            await client.start_notify(DATA_CHAR, handle_data)
            print("Subscribed to all notifications.\n")
            
            # Send SEND_HISTORICAL_DATA command
            print("--- Requesting Historical Data ---")
            pkt = make_packet(TYPE_COMMAND, CMD_SEND_HISTORICAL_DATA, b"\x00")
            await client.write_gatt_char(CMD_TO_STRAP, pkt)
            
            # Wait for command response
            try:
                resp = await asyncio.wait_for(cmd_queue.get(), timeout=10)
                print(f"  Command acknowledged: cmd={resp['cmd']}")
            except asyncio.TimeoutError:
                print("  ⚠️  No command response (continuing anyway...)")
            
            # Process metadata batches
            print("\n--- Downloading History ---")
            batch = 0
            
            while True:
                try:
                    # Wait for metadata
                    metapkt = await asyncio.wait_for(meta_queue.get(), timeout=60)
                except asyncio.TimeoutError:
                    print("\n  ⏱️  Timeout waiting for metadata (download may be complete)")
                    break
                
                # Process metadata until we get HISTORY_END or HISTORY_COMPLETE
                while metapkt["cmd"] != META_HISTORY_END and metapkt["cmd"] != META_HISTORY_COMPLETE:
                    print(f"  Batch {batch}: START metadata")
                    try:
                        metapkt = await asyncio.wait_for(meta_queue.get(), timeout=60)
                    except asyncio.TimeoutError:
                        print("  ⏱️  Timeout")
                        break
                
                # HISTORY_COMPLETE = we're done
                if metapkt["cmd"] == META_HISTORY_COMPLETE:
                    print(f"\n  ✅ HISTORY_COMPLETE — all data received!")
                    break
                
                # HISTORY_END — acknowledge and request next batch
                if metapkt["cmd"] == META_HISTORY_END:
                    mdata = metapkt["data"]
                    if len(mdata) >= 14:
                        unix, subsec, unk0, trim = struct.unpack("<LHLL", mdata[:14])
                        ts = datetime.datetime.fromtimestamp(unix).strftime("%Y-%m-%d %H:%M")
                        print(f"  Batch {batch}: END at {ts} (trim={trim})")
                        
                        # Acknowledge and request next batch
                        ack_data = struct.pack("<BLL", 1, trim, 0)
                        ack_pkt = make_packet(TYPE_COMMAND, CMD_HISTORICAL_DATA_RESULT, ack_data)
                        await client.write_gatt_char(CMD_TO_STRAP, ack_pkt)
                        batch += 1
                    else:
                        print(f"  Batch {batch}: END (short metadata: {mdata.hex()})")
                        break
            
            fp.close()
            
            # Summary
            print(f"\n{'='*50}")
            print(f"DOWNLOAD COMPLETE")
            print(f"{'='*50}")
            print(f"  Raw packets:  {len(hist_packets)}")
            print(f"  Binary file:  {output_bin}")
            
            # Parse the binary data
            if len(hist_packets) > 0:
                print(f"\n--- Parsing Records ---")
                records = parse_historical_records(output_bin)
                
                if records:
                    # Save as JSON
                    with open(output_json, "w") as jf:
                        json.dump(records, jf, indent=2)
                    
                    first = records[0]
                    last = records[-1]
                    hrs = [r["heart_rate"] for r in records if r["heart_rate"] > 0]
                    rrs = [rr for r in records for rr in r["rr_intervals"] if rr > 0]
                    
                    print(f"\n  Total records: {len(records)}")
                    print(f"  Date range:   {first['timestamp'][:10]} → {last['timestamp'][:10]}")
                    if hrs:
                        print(f"  HR range:     {min(hrs)}-{max(hrs)} bpm (avg {sum(hrs)/len(hrs):.0f})")
                    if rrs:
                        print(f"  RR intervals: {len(rrs)} total")
                    print(f"\n  Saved to: {output_json}")
                else:
                    print("  No valid records parsed from binary data.")
            else:
                print("  No history packets received.")
                print("  The strap may not have stored data, or the download didn't start.")
    
    except Exception as e:
        fp.close()
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(main())
