// send-key.js - Send keyboard events
// Used internally by: chrome sendkey <key>
// Parameter passed via KEY_NAME variable

(function() {
  // Key mapping: common key names to KeyboardEvent properties
  var keyMap = {
    // Common keys
    'esc': { key: 'Escape', code: 'Escape', keyCode: 27 },
    'escape': { key: 'Escape', code: 'Escape', keyCode: 27 },
    'enter': { key: 'Enter', code: 'Enter', keyCode: 13 },
    'return': { key: 'Enter', code: 'Enter', keyCode: 13 },
    'tab': { key: 'Tab', code: 'Tab', keyCode: 9 },
    'space': { key: ' ', code: 'Space', keyCode: 32 },
    'backspace': { key: 'Backspace', code: 'Backspace', keyCode: 8 },
    'delete': { key: 'Delete', code: 'Delete', keyCode: 46 },

    // Arrow keys
    'arrowup': { key: 'ArrowUp', code: 'ArrowUp', keyCode: 38 },
    'arrowdown': { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40 },
    'arrowleft': { key: 'ArrowLeft', code: 'ArrowLeft', keyCode: 37 },
    'arrowright': { key: 'ArrowRight', code: 'ArrowRight', keyCode: 39 },
    'up': { key: 'ArrowUp', code: 'ArrowUp', keyCode: 38 },
    'down': { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40 },
    'left': { key: 'ArrowLeft', code: 'ArrowLeft', keyCode: 37 },
    'right': { key: 'ArrowRight', code: 'ArrowRight', keyCode: 39 },

    // Page navigation
    'pageup': { key: 'PageUp', code: 'PageUp', keyCode: 33 },
    'pagedown': { key: 'PageDown', code: 'PageDown', keyCode: 34 },
    'home': { key: 'Home', code: 'Home', keyCode: 36 },
    'end': { key: 'End', code: 'End', keyCode: 35 },

    // Function keys
    'f1': { key: 'F1', code: 'F1', keyCode: 112 },
    'f2': { key: 'F2', code: 'F2', keyCode: 113 },
    'f3': { key: 'F3', code: 'F3', keyCode: 114 },
    'f4': { key: 'F4', code: 'F4', keyCode: 115 },
    'f5': { key: 'F5', code: 'F5', keyCode: 116 },
    'f6': { key: 'F6', code: 'F6', keyCode: 117 },
    'f7': { key: 'F7', code: 'F7', keyCode: 118 },
    'f8': { key: 'F8', code: 'F8', keyCode: 119 },
    'f9': { key: 'F9', code: 'F9', keyCode: 120 },
    'f10': { key: 'F10', code: 'F10', keyCode: 121 },
    'f11': { key: 'F11', code: 'F11', keyCode: 122 },
    'f12': { key: 'F12', code: 'F12', keyCode: 123 }
  };

  // Get key name from global variable set by shell
  var keyName = (typeof KEY_NAME !== 'undefined' ? KEY_NAME : '').toLowerCase();

  if (!keyName) {
    return 'ERROR: No key specified';
  }

  var keyProps = keyMap[keyName];
  if (!keyProps) {
    return 'ERROR: Unknown key "' + keyName + '". Supported: ' + Object.keys(keyMap).join(', ');
  }

  // Find target element
  var target = document.activeElement || document.body;

  // Create keyboard event with proper properties
  var evt = new KeyboardEvent('keydown', {
    key: keyProps.key,
    code: keyProps.code,
    keyCode: keyProps.keyCode,
    which: keyProps.keyCode,
    bubbles: true,
    cancelable: true
  });

  // Dispatch to both activeElement and document for max compatibility
  target.dispatchEvent(evt);
  document.dispatchEvent(evt);

  // Special handling for ESC key with native dialogs
  if (keyName === 'esc' || keyName === 'escape') {
    var openDialogs = document.querySelectorAll('dialog[open]');
    if (openDialogs.length > 0) {
      openDialogs[openDialogs.length - 1].close();
      return 'OK: sent ' + keyProps.key + ', closed native dialog';
    }
  }

  return 'OK: sent ' + keyProps.key + ' to ' + target.tagName;
})();
