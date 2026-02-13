# Troubleshooting

## AVD Issues

### AVD won't start
```bash
# Check if another emulator is running
adb devices
pkill -f qemu-system-aarch64

# Restart
./bin/avd start
```

### AVD very slow
- Close other VMs (Lima, Docker Desktop)
- Check Activity Monitor for CPU usage
- Reduce AVD RAM in Android Studio settings

### Snapshot not loading
```bash
# List available snapshots
adb -s emulator-5554 emu avd snapshot list

# Create new snapshot
./bin/avd snapshot
```

## Lima/Redroid Issues

### Redroid container crashes (exit 129)
Binder module not loaded:
```bash
./bin/lima shell
sudo modprobe binder_linux
sudo mount -t binder binder /dev/binderfs
exit
./bin/redroid restart
```

### High CPU/heat from Lima
Lima VM runs at high CPU when Redroid is active. Solutions:
- Stop Lima when not in use: `./bin/lima stop`
- Use AVD instead (lower idle CPU)

### Can't connect to localhost:5556
```bash
# Check if Redroid is running
./bin/redroid status

# Check port forwarding
limactl list
lsof -i :5556
```

### WeChat shows "tablet only" login
Device not recognized as tablet. Check:
```bash
adb -s localhost:5556 shell getprop ro.build.characteristics
# Should show: tablet

adb -s localhost:5556 shell getprop ro.product.brand
# Should show: google
```

If not, restart Redroid:
```bash
./bin/redroid restart
```

## WeChat Issues

### WeChat won't install
```bash
# Check ADB connection
adb devices

# Install manually
adb -s <device> install /path/to/wechat.apk
```

### WeChat crashes on launch
- Try older WeChat version
- Check Android version compatibility
- Clear app data: `adb shell pm clear com.tencent.mm`

### Can't log in (QR code issues)
1. Make sure phone WeChat is logged in
2. Scan QR from phone's WeChat (not camera)
3. Choose "Log in" not "Log in only on tablet"

## Database Issues

### Can't pull database
```bash
# Need root access
adb root
adb pull /data/data/com.tencent.mm/MicroMsg/*/EnMicroMsg.db
```

### Database is encrypted
Database requires decryption key. See `lib/extract-key.js` for key extraction.

## General Tips

### Check all statuses
```bash
./bin/avd status
./bin/lima status
./bin/redroid status
./bin/view status
```

### Complete reset
```bash
# Stop everything
./bin/avd kill
./bin/redroid stop
./bin/lima stop

# Start fresh
./bin/avd start  # or ./bin/redroid start
```
