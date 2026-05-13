"""Quick Whoop BLE scan test - uses correct bleak API."""
import asyncio
from bleak import BleakScanner

async def main():
    print("Scanning for Whoop devices (15s)...")
    print("Make sure phone Bluetooth is OFF so the strap is advertising.\n")
    
    found = []
    
    def callback(device, adv_data):
        name = device.name or adv_data.local_name or ""
        if "WHOOP" in name.upper():
            rssi = adv_data.rssi
            found.append((device, adv_data))
            print(f"  FOUND: {name} [{device.address}] RSSI: {rssi} dBm")
            print(f"         Services: {adv_data.service_uuids}")
    
    scanner = BleakScanner(detection_callback=callback)
    await scanner.start()
    await asyncio.sleep(15)
    await scanner.stop()
    
    if not found:
        print("\nNo Whoop devices found.")
        print("Tips:")
        print("  1. Turn OFF Bluetooth on your phone first")
        print("  2. Make sure the Whoop is charged and on your wrist")
        print("  3. Try again - sometimes it takes a few scans")
    else:
        print(f"\nFound {len(found)} Whoop device(s)!")
        for d, adv in found:
            name = d.name or adv.local_name or "WHOOP"
            print(f"\nDevice: {name}")
            print(f"Address: {d.address}")
            print(f"RSSI: {adv.rssi} dBm")
            print(f"Services: {adv.service_uuids}")
            print(f"\nYou can now connect with:")
            print(f'  python whoop-connect-test.py "{d.address}"')

if __name__ == "__main__":
    asyncio.run(main())
