"""Parse whoop_hist.bin using whoomp's exact parser logic.

Reads raw binary history dump and extracts HR + RR records to JSON.
"""
import struct, json, datetime, sys

# Packet types
TYPE_HISTORICAL_DATA = 47

def parse_data(file_path):
    with open(file_path, "rb") as f:
        data = f.read()
    
    print(f"Binary file size: {len(data)} bytes")
    
    records = []
    errors = 0
    dp = 0
    
    while dp < len(data):
        if dp + 3 >= len(data):
            break
        
        # Check for SOF
        if data[dp] != 0xAA:
            dp += 1
            errors += 1
            continue
        
        try:
            # Match whoomp exactly:
            # length = struct.unpack("<H", data[dp + 1:dp + 3])[0] + 4
            # This gives total packet size (header + payload + crc32)
            length = struct.unpack("<H", data[dp + 1:dp + 3])[0] + 4
            
            if dp + length > len(data):
                dp += 1
                errors += 1
                continue
            
            # Extract payload: skip SOF(1) + len(2) + crc8(1) = 4 header bytes
            # and strip CRC32(4) from end
            pkt_raw = data[dp:dp + length]
            payload = pkt_raw[4:-4]  # matches WhoopPacket.from_data: data[4:-4]
            
            if len(payload) < 3:
                dp += length
                continue
            
            ptype = payload[0]  # PacketType
            seq = payload[1]
            cmd = payload[2]
            pdata = payload[3:]  # this is pkt.data in whoomp
            
            if ptype == TYPE_HISTORICAL_DATA:
                # whoomp parser.py: 
                # unix, subsec, unk, heart = struct.unpack("<LHLB", pkt.data[4:4 + 11])
                # rrnum = pkt.data[15]
                # rr1-4 = struct.unpack("<HHHH", pkt.data[16:24])
                
                if len(pdata) >= 24:
                    unix, subsec, unk, heart = struct.unpack("<LHLB", pdata[4:15])
                    rrnum = pdata[15]
                    rr1, rr2, rr3, rr4 = struct.unpack("<HHHH", pdata[16:24])
                    
                    rr = []
                    if rrnum == 1: rr = [rr1]
                    elif rrnum == 2: rr = [rr1, rr2]
                    elif rrnum == 3: rr = [rr1, rr2, rr3]
                    elif rrnum == 4: rr = [rr1, rr2, rr3, rr4]
                    
                    records.append({
                        "unix": unix,
                        "timestamp": datetime.datetime.fromtimestamp(unix).isoformat(),
                        "heart_rate": heart,
                        "rr_intervals": rr
                    })
            
            dp += length
            
        except Exception as e:
            dp += 1
            errors += 1
    
    return records, errors

if __name__ == "__main__":
    bin_file = sys.argv[1] if len(sys.argv) > 1 else "whoop_hist.bin"
    json_file = bin_file.replace(".bin", ".json")
    
    print(f"Parsing: {bin_file}")
    records, errors = parse_data(bin_file)
    
    print(f"\nResults:")
    print(f"  Records parsed: {len(records)}")
    print(f"  Errors skipped: {errors}")
    
    if records:
        # Sort by timestamp
        records.sort(key=lambda r: r["unix"])
        
        first = records[0]
        last = records[-1]
        hrs = [r["heart_rate"] for r in records if r["heart_rate"] > 0]
        rrs = [rr for r in records for rr in r["rr_intervals"] if rr > 0]
        
        print(f"\n  Date range: {first['timestamp'][:10]} -> {last['timestamp'][:10]}")
        if hrs:
            print(f"  HR range:   {min(hrs)}-{max(hrs)} bpm (avg {sum(hrs)/len(hrs):.0f})")
        if rrs:
            print(f"  RR intervals: {len(rrs)} total")
        
        # Show first 5 records
        print(f"\n  First 5 records:")
        for r in records[:5]:
            print(f"    {r['timestamp']}  HR={r['heart_rate']}  RR={r['rr_intervals']}")
        
        print(f"\n  Last 5 records:")
        for r in records[-5:]:
            print(f"    {r['timestamp']}  HR={r['heart_rate']}  RR={r['rr_intervals']}")
        
        # Save JSON
        with open(json_file, "w") as f:
            json.dump(records, f, indent=2)
        print(f"\n  Saved to: {json_file}")
    else:
        # Debug: show first packet raw bytes
        with open(bin_file, "rb") as f:
            data = f.read()
        print(f"\n  DEBUG - First 100 bytes hex:")
        print(f"  {data[:100].hex()}")
        
        # Try to parse first packet manually
        if data[0] == 0xAA:
            length = struct.unpack("<H", data[1:3])[0] + 4
            print(f"\n  First packet length field: {struct.unpack('<H', data[1:3])[0]}")
            print(f"  Full packet size: {length}")
            payload = data[4:length-4]
            print(f"  Payload ({len(payload)} bytes): {payload.hex()}")
            print(f"  type={payload[0]} seq={payload[1]} cmd={payload[2]}")
            print(f"  data ({len(payload[3:])} bytes): {payload[3:].hex()}")
