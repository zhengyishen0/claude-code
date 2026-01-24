# WeChat Anti-Detection Checklist

Comprehensive analysis of emulator/root detection vectors and our mitigations.

## Use Case Context

| Aspect | Our Approach |
|--------|--------------|
| **Login method** | Tablet mode (phone + tablet simultaneous login) |
| **Session management** | Snapshot restore (no re-authentication) |
| **Activity** | Read-only database extraction |
| **Messaging** | None (no outbound messages) |

This is equivalent to: "User opens tablet → app syncs → user closes tablet"

---

## Detection Dimensions

### 1. System Properties

Apps read Android system properties to identify device characteristics.

| Property | Real AVD Value | Spoofed Value | How They Check | Status |
|----------|---------------|---------------|----------------|--------|
| `ro.kernel.qemu` | `1` | `0` | `getprop` or `SystemProperties.get()` | ✅ Mitigated |
| `ro.hardware` | `ranchu` | `tangorpro` | Build.HARDWARE | ✅ Mitigated |
| `ro.product.model` | `sdk_gphone64_arm64` | `Pixel Tablet` | Build.MODEL | ✅ Mitigated |
| `ro.product.device` | `emu64a` | `tangorpro` | Build.DEVICE | ✅ Mitigated |
| `ro.product.brand` | `google` | `google` | Build.BRAND | ✅ Already correct |
| `ro.build.fingerprint` | `google/sdk_...` | Real Pixel fingerprint | Build.FINGERPRINT | ✅ Mitigated |
| `ro.build.characteristics` | `default` | `tablet` | Tablet mode check | ✅ Mitigated |
| `ro.boot.qemu` | `1` | `0` | Boot property | ✅ Mitigated |
| `ro.bootimage.build.fingerprint` | SDK fingerprint | Real fingerprint | Deep fingerprint check | ⚠️ Partial |
| `ro.secure` | `1` | `1` | Security check | ✅ Already correct |

**Solution:** DeviceSpoof Magisk module + resetprop at boot

---

### 2. Root Detection

Apps check for root access which indicates device tampering.

| Check | Method | Our Mitigation | Status |
|-------|--------|----------------|--------|
| `/system/bin/su` exists | File.exists() | Shamiko hides from DenyList apps | ✅ Mitigated |
| `/system/xbin/su` exists | File.exists() | Shamiko hides | ✅ Mitigated |
| `su` command works | Runtime.exec("su") | Shamiko blocks for WeChat | ✅ Mitigated |
| Magisk app installed | PackageManager query | Shamiko hides package | ✅ Mitigated |
| SuperSU app installed | PackageManager query | Not installed | ✅ N/A |
| `/data/adb/magisk` exists | File access | Shamiko hides path | ✅ Mitigated |
| Magisk mount points | /proc/mounts parsing | Shamiko unmounts for app | ✅ Mitigated |
| SELinux context | `u:r:magisk:s0` in ps | Shamiko spoofs context | ✅ Mitigated |

**Solution:** Shamiko module with Zygisk + WeChat in DenyList

---

### 3. Emulator File System

Emulators have distinctive file paths and drivers.

| Check | Real AVD | Expected Real Device | Our Mitigation | Status |
|-------|----------|---------------------|----------------|--------|
| `/dev/qemu_pipe` | Exists | Not exists | Cannot hide | ⚠️ Not mitigated |
| `/dev/goldfish_pipe` | Exists | Not exists | Cannot hide | ⚠️ Not mitigated |
| `/system/lib/libc_malloc_debug_qemu.so` | Exists | Not exists | File doesn't exist on API 35 | ✅ N/A |
| `/sys/qemu_trace` | Exists | Not exists | May exist | ⚠️ Not mitigated |
| `/system/bin/qemu-props` | May exist | Not exists | File check | ⚠️ Not mitigated |
| `init.goldfish.rc` | Exists | Not exists | Init file | ⚠️ Not mitigated |

**Risk Level:** 🟡 Medium - These require root to hide, and hiding system files is complex.

**Reality Check:** WeChat doesn't appear to check these aggressively for tablet login.

---

### 4. Hardware & Sensors

Real devices have physical sensors with realistic data patterns.

| Sensor/Hardware | Emulator Behavior | Real Device | Our Mitigation | Status |
|-----------------|-------------------|-------------|----------------|--------|
| Accelerometer | Returns static/synthetic values | Natural movement noise | AVD config enables sensor | ⚠️ Partial |
| Gyroscope | Returns zeros or fixed | Natural drift | AVD config enables sensor | ⚠️ Partial |
| Magnetometer | Returns fixed values | Varies with orientation | AVD config enables sensor | ⚠️ Partial |
| GPS | Fixed or no location | Variable location | Can set fake location | ✅ Can mitigate |
| Camera | Virtual camera | Physical camera | Not relevant for DB sync | ✅ N/A |
| Bluetooth | Virtual/none | Real Bluetooth | Not relevant | ✅ N/A |
| NFC | None | May have NFC | Not relevant | ✅ N/A |
| Fingerprint | None | May have | Not relevant | ✅ N/A |

**Risk Level:** 🟢 Low for our use case - Sensor validation is for active app usage, not passive sync.

---

### 5. Graphics & Display

GPU and display characteristics can reveal emulation.

| Check | Emulator Value | Real Device | Our Mitigation | Status |
|-------|---------------|-------------|----------------|--------|
| `GL_RENDERER` | `Google SwiftShader` or `Android Emulator` | `Adreno`, `Mali`, `PowerVR` | Cannot spoof OpenGL strings | ⚠️ Not mitigated |
| `GL_VENDOR` | `Google` | `Qualcomm`, `ARM`, `Imagination` | Cannot spoof | ⚠️ Not mitigated |
| Screen density | Configured | Physical DPI | AVD set to realistic DPI | ✅ Mitigated |
| Display size | Configured | Physical size | Pixel Tablet profile | ✅ Mitigated |

**Risk Level:** 🟡 Medium - GL strings are hard to spoof, but WeChat doesn't seem to check these.

---

### 6. Network Fingerprinting

Network stack and identifiers can differ.

| Check | Emulator | Real Device | Our Mitigation | Status |
|-------|----------|-------------|----------------|--------|
| MAC address prefix | `02:00:00:*` or random | Vendor-specific OUI | Emulator randomizes | ⚠️ Partial |
| Network interface names | `eth0`, `wlan0` | `wlan0` typically | Similar names | ✅ OK |
| IP address patterns | 10.0.2.* (NAT) | Carrier/WiFi IP | Using host network | ✅ OK |
| Carrier name | None or "Android" | Real carrier | Tablet = WiFi only | ✅ N/A |
| IMEI/IMSI | Empty or fake | Real values | Tablet mode doesn't need | ✅ N/A |
| Phone number | None | Real number | Tablet mode doesn't need | ✅ N/A |

**Risk Level:** 🟢 Low - Tablet mode legitimately has no cellular identity.

---

### 7. Timing & Performance

Emulator performance patterns differ from real hardware.

| Check | Emulator | Real Device | Our Mitigation | Status |
|-------|----------|-------------|----------------|--------|
| Boot time | Slower/variable | Consistent | N/A for snapshot restore | ✅ N/A |
| App launch time | Variable | Consistent | Short sessions | ✅ Low risk |
| CPU timing | Host-dependent | Consistent | Cannot control | ⚠️ Not mitigated |
| Instruction timing | Virtualized | Native | Cannot control | ⚠️ Not mitigated |

**Risk Level:** 🟢 Low - Timing attacks require sustained measurement, our sessions are brief.

---

### 8. Battery Behavior

Emulator battery behaves differently.

| Check | Default Emulator | Real Device | Our Mitigation | Status |
|-------|-----------------|-------------|----------------|--------|
| Always charging | Yes (AC power) | Unplugged sometimes | `cmd battery unplug` | ✅ Mitigated |
| Temperature constant | 25.0°C always | Varies 25-40°C | Randomized via `cmd battery` | ✅ Mitigated |
| Level constant | Often 100% or 50% | Varies | Randomized 65-95% | ✅ Mitigated |
| Discharge pattern | Never discharges | Natural drain | Short sessions | ✅ Low exposure |

**Risk Level:** 🟢 Low - We randomize battery values and keep sessions brief.

---

### 9. Frida/Instrumentation Detection

Apps detect debugging and instrumentation tools.

| Check | Default | Our Setup | Status |
|-------|---------|-----------|--------|
| Port 27042 listening | Frida default | Using port 31337 | ✅ Mitigated |
| Port 27043 listening | Frida default | Not used | ✅ Mitigated |
| Process named `frida*` | frida-server | Renamed to `hluda-server` | ✅ Mitigated |
| `/data/local/tmp/frida*` | Common path | Using `hluda-server` | ✅ Mitigated |
| Frida gadget in memory | If injected | Only run when needed | ✅ Mitigated |
| D-Bus protocol detection | Frida uses D-Bus | Non-default port | ✅ Mitigated |
| Library injection | frida-agent.so | ZygiskFrida alternative | ⚠️ Could improve |

**Risk Level:** 🟢 Low - Frida only runs briefly to extract key, then not needed.

---

### 10. Google Play Integrity / SafetyNet

Google's device attestation framework.

| Check | Emulator Result | Real Device | Our Mitigation | Status |
|-------|----------------|-------------|----------------|--------|
| BASIC integrity | ❌ Fails | ✅ Passes | None possible | ❌ Cannot fix |
| DEVICE integrity | ❌ Fails | ✅ Passes | None possible | ❌ Cannot fix |
| STRONG integrity | ❌ Fails | ✅ Passes | None possible | ❌ Cannot fix |

**Why This Doesn't Matter for WeChat:**

| Reason | Explanation |
|--------|-------------|
| **No GMS in China** | Google Play Services blocked; 1B+ users have no GMS |
| **Chinese phones** | Xiaomi, Oppo, Vivo, Huawei ship without Google framework |
| **WeChat distribution** | Via Tencent servers, not Play Store |
| **Would break market** | Requiring Play Integrity = locking out China |

**Risk Level:** ❌ **Impossible for WeChat to use** - Would exclude entire domestic market.

---

### 11. Behavioral Analysis

Server-side analysis of usage patterns.

| Pattern | Suspicious | Our Behavior | Risk |
|---------|------------|--------------|------|
| Frequent login/logout | Bot activity | Snapshot restore (same session) | ✅ None |
| Multiple device switches | Account selling | Single consistent device | ✅ None |
| Bulk messaging | Marketing bot | No outbound messages | ✅ None |
| 24/7 online | Bot | Brief sync sessions | ✅ None |
| Instant message responses | Automation | No responses | ✅ None |
| Login from new location | Account takeover | Consistent IP | ✅ None |
| Rapid friend additions | Spam | No friend activity | ✅ None |

**Risk Level:** 🟢 None - Our read-only DB sync triggers zero behavioral flags.

---

## Summary Matrix

| Category | Coverage | Risk Level | Notes |
|----------|----------|------------|-------|
| System Properties | 95% | 🟢 Low | All major props spoofed |
| Root Detection | 100% | 🟢 None | Shamiko fully hides |
| Emulator Files | 30% | 🟡 Medium | Some qemu files visible, but unchecked |
| Hardware/Sensors | 60% | 🟢 Low | Enabled but synthetic; irrelevant for sync |
| Graphics | 20% | 🟡 Medium | GL strings exposed, but unchecked |
| Network | 90% | 🟢 Low | Tablet mode = WiFi only is normal |
| Timing | 0% | 🟢 Low | Can't control, but brief sessions |
| Battery | 100% | 🟢 None | Fully randomized |
| Frida Detection | 95% | 🟢 Low | Renamed, different port, brief usage |
| Play Integrity | 0% | ❌ N/A | **WeChat cannot use this** |
| Behavioral | 100% | 🟢 None | Read-only, no suspicious patterns |

---

## What We Don't Cover (And Why It's OK)

| Gap | Why It's Acceptable |
|-----|---------------------|
| `/dev/qemu_pipe` visible | WeChat doesn't check low-level device files for tablet login |
| GL_RENDERER shows emulator | Graphics checks are for games/3D apps, not messaging |
| Sensor data is synthetic | Sensor validation is for active usage, not background sync |
| CPU timing artifacts | Would require sustained measurement; our sessions are < 1 min |

---

## Workflow Risk Profile

```
┌─────────────────────────────────────────────────────────────────┐
│  RESTORE SNAPSHOT                                               │
│  └─ WeChat session already authenticated                        │
│  └─ No login event triggered                                    │
│  └─ Device fingerprint unchanged                                │
├─────────────────────────────────────────────────────────────────┤
│  APP SYNCS MESSAGES                                             │
│  └─ Normal background sync behavior                             │
│  └─ No user-initiated actions                                   │
│  └─ Read-only database access                                   │
├─────────────────────────────────────────────────────────────────┤
│  COPY DATABASE                                                  │
│  └─ Uses root (hidden by Shamiko)                               │
│  └─ WeChat unaware of file access                               │
│  └─ No network traffic to Tencent                               │
├─────────────────────────────────────────────────────────────────┤
│  SHUTDOWN                                                       │
│  └─ Clean exit                                                  │
│  └─ Next session restores same snapshot                         │
│  └─ No state accumulation                                       │
└─────────────────────────────────────────────────────────────────┘

OVERALL RISK: 🟢 VERY LOW
```

---

## Recommendations

1. **Keep sessions brief** - Restore → sync → copy → exit
2. **Don't modify anything** - Read-only operations only
3. **Use consistent snapshots** - Same device fingerprint every time
4. **Don't automate messaging** - That's what triggers bans
5. **Extract key once** - Cache it, don't run Frida repeatedly

---

## Version History

| Date | Changes |
|------|---------|
| 2026-01-24 | Initial comprehensive checklist |
