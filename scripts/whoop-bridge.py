        self.is_streaming = False

    async def scan(self, timeout=10):
        """Scan for nearby Whoop devices."""
        print(f"Scanning for Whoop devices ({timeout}s)...")
        
        whoop_devices = []
        
        def detection_callback(device, advertisement_data):
            name = device.name or advertisement_data.local_name or ""
            if "WHOOP" in name.upper():
                rssi = advertisement_data.rssi
                whoop_devices.append((device, advertisement_data))
                print(f"  Found: {name} [{device.address}] RSSI: {rssi}")
        
        scanner = BleakScanner(detection_callback=detection_callback)
        await scanner.start()
        await asyncio.sleep(timeout)
        await scanner.stop()

        if not whoop_devices:
            print("\n  No Whoop devices found.")
            print("  Make sure your Whoop is:")
            print("    - Charged and on your wrist")
            print("    - Not connected to the Whoop app (disconnect it first!)")
            print("    - Bluetooth is enabled on this PC")
        else:
            print(f"\nFound {len(whoop_devices)} Whoop device(s).")
            print(f"\nTo connect, run:")
            for d, adv in whoop_devices:
                name = d.name or adv.local_name or "WHOOP"
                print(f'  python whoop-bridge.py connect --name "{name}"')

        return [d for d, _ in whoop_devices]
