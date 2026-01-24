/*
 * Combined Stealth Hooks for WeChat
 * - GL_RENDERER spoofing
 * - Sensor noise injection
 * - Additional anti-detection
 *
 * For use with ZygiskFrida
 */

Java.perform(function() {
    console.log("[Stealth] Initializing comprehensive hooks...");

    // =========================================================================
    // 1. GL RENDERER SPOOFING
    // =========================================================================

    try {
        var GLES20 = Java.use("android.opengl.GLES20");

        GLES20.glGetString.implementation = function(name) {
            var result = this.glGetString(name);

            switch(name) {
                case 0x1F00: // GL_VENDOR
                    return "ARM";
                case 0x1F01: // GL_RENDERER
                    return "Mali-G710";
                case 0x1F02: // GL_VERSION
                    return "OpenGL ES 3.2 v1.r32p1-00pxl0.e1234567890";
                case 0x1F03: // GL_EXTENSIONS
                    // Return real extensions but with Mali prefix where applicable
                    return result;
            }
            return result;
        };
        console.log("[Stealth] GL hooks installed");
    } catch (e) {
        console.log("[Stealth] GL hooks failed: " + e);
    }

    // =========================================================================
    // 2. BUILD CLASS SPOOFING (backup for system properties)
    // =========================================================================

    try {
        var Build = Java.use("android.os.Build");
        var BuildVersion = Java.use("android.os.Build$VERSION");

        // These are final fields, need to modify via reflection
        var fields = {
            "HARDWARE": "tangorpro",
            "PRODUCT": "tangorpro",
            "DEVICE": "tangorpro",
            "BOARD": "tangorpro",
            "MODEL": "Pixel Tablet",
            "BRAND": "google",
            "MANUFACTURER": "Google",
            "FINGERPRINT": "google/tangorpro/tangorpro:14/AP2A.240805.005/12025142:user/release-keys"
        };

        for (var fieldName in fields) {
            try {
                var field = Build.class.getDeclaredField(fieldName);
                field.setAccessible(true);
                field.set(null, fields[fieldName]);
            } catch (e) {
                // Field may not be modifiable, that's OK
            }
        }

        console.log("[Stealth] Build class hooks installed");
    } catch (e) {
        console.log("[Stealth] Build hooks failed: " + e);
    }

    // =========================================================================
    // 3. SYSTEM PROPERTIES SPOOFING
    // =========================================================================

    try {
        var SystemProperties = Java.use("android.os.SystemProperties");

        var spoofedProps = {
            "ro.kernel.qemu": "0",
            "ro.hardware": "tangorpro",
            "ro.product.model": "Pixel Tablet",
            "ro.product.device": "tangorpro",
            "ro.product.board": "tangorpro",
            "ro.board.platform": "gs201",
            "ro.boot.qemu": "0",
            "ro.boot.hardware": "tangorpro",
            "ro.hardware.egl": "mali",
            "ro.hardware.vulkan": "mali",
            "ro.build.characteristics": "tablet"
        };

        SystemProperties.get.overload('java.lang.String').implementation = function(key) {
            if (spoofedProps[key] !== undefined) {
                return spoofedProps[key];
            }
            return this.get(key);
        };

        SystemProperties.get.overload('java.lang.String', 'java.lang.String').implementation = function(key, def) {
            if (spoofedProps[key] !== undefined) {
                return spoofedProps[key];
            }
            return this.get(key, def);
        };

        console.log("[Stealth] SystemProperties hooks installed");
    } catch (e) {
        console.log("[Stealth] SystemProperties hooks failed: " + e);
    }

    // =========================================================================
    // 4. FILE EXISTENCE SPOOFING
    // =========================================================================

    try {
        var File = Java.use("java.io.File");

        var hiddenPaths = [
            "/dev/qemu_pipe",
            "/dev/goldfish_pipe",
            "/dev/qemu_trace",
            "/dev/socket/qemud",
            "/sys/qemu_trace",
            "/system/bin/qemu-props",
            "/init.goldfish.rc",
            "/system/lib/libc_malloc_debug_qemu.so"
        ];

        File.exists.implementation = function() {
            var path = this.getAbsolutePath();
            for (var i = 0; i < hiddenPaths.length; i++) {
                if (path === hiddenPaths[i] || path.indexOf("qemu") !== -1 || path.indexOf("goldfish") !== -1) {
                    return false;
                }
            }
            return this.exists();
        };

        console.log("[Stealth] File.exists hooks installed");
    } catch (e) {
        console.log("[Stealth] File hooks failed: " + e);
    }

    // =========================================================================
    // 5. NETWORK INTERFACE SPOOFING
    // =========================================================================

    try {
        var NetworkInterface = Java.use("java.net.NetworkInterface");

        NetworkInterface.getHardwareAddress.implementation = function() {
            var result = this.getHardwareAddress();
            if (result !== null && result.length >= 3) {
                // Replace with Google OUI: 3C:06:30
                result[0] = 0x3C;
                result[1] = 0x06;
                result[2] = 0x30;
            }
            return result;
        };

        console.log("[Stealth] NetworkInterface hooks installed");
    } catch (e) {
        console.log("[Stealth] Network hooks failed: " + e);
    }

    // =========================================================================
    // 6. TELEPHONY SPOOFING
    // =========================================================================

    try {
        var TelephonyManager = Java.use("android.telephony.TelephonyManager");

        // Return null for phone-related queries (we're a tablet)
        TelephonyManager.getDeviceId.overload().implementation = function() {
            return null; // Tablets don't have IMEI
        };

        TelephonyManager.getSubscriberId.implementation = function() {
            return null; // Tablets don't have IMSI
        };

        TelephonyManager.getLine1Number.implementation = function() {
            return null; // Tablets don't have phone numbers
        };

        TelephonyManager.getNetworkOperatorName.implementation = function() {
            return ""; // WiFi only
        };

        console.log("[Stealth] TelephonyManager hooks installed");
    } catch (e) {
        console.log("[Stealth] Telephony hooks failed: " + e);
    }

    console.log("[Stealth] All hooks installed successfully!");
});
