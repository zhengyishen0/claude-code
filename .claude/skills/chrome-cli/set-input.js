// set-input.js - React-compatible form input
// Usage: chrome-cli execute "const selector='SELECTOR'; const value='VALUE'; $(cat set-input.js)"
// Returns: "set: <element> = <value>" or "failed: <reason>"

(function() {
  const sel = typeof selector !== 'undefined' ? selector : null;
  const val = typeof value !== 'undefined' ? value : null;

  if (!sel) return 'failed: no selector provided';
  if (val === null) return 'failed: no value provided';

  const el = document.querySelector(sel);
  if (!el) return 'failed: element not found: ' + sel;

  const tagName = el.tagName.toLowerCase();
  const inputType = el.type || 'text';

  // Check if it's an input-like element
  if (!['input', 'textarea', 'select'].includes(tagName)) {
    // Could be a contenteditable
    if (el.contentEditable === 'true') {
      el.focus();
      el.textContent = val;
      el.dispatchEvent(new Event('input', { bubbles: true }));
      return 'set: contenteditable = "' + val + '"';
    }
    return 'failed: element is not an input, textarea, select, or contenteditable';
  }

  // Focus the element first
  el.focus();

  // For React: Get the native value setter to bypass React's synthetic system
  const nativeInputValueSetter = Object.getOwnPropertyDescriptor(
    window.HTMLInputElement.prototype, 'value'
  )?.set;
  const nativeTextareaValueSetter = Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, 'value'
  )?.set;

  // Set value using native setter (bypasses React's getter/setter)
  if (tagName === 'input' && nativeInputValueSetter) {
    nativeInputValueSetter.call(el, val);
  } else if (tagName === 'textarea' && nativeTextareaValueSetter) {
    nativeTextareaValueSetter.call(el, val);
  } else if (tagName === 'select') {
    el.value = val;
  } else {
    el.value = val;
  }

  // Dispatch events that React listens to
  // React 16+ uses these events
  el.dispatchEvent(new Event('input', { bubbles: true, cancelable: true }));
  el.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));

  // Also try KeyboardEvent for some stubborn inputs
  el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
  el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));

  // Blur to trigger validation
  el.dispatchEvent(new Event('blur', { bubbles: true }));

  // Get element description
  const desc = tagName +
    (el.name ? '[name="' + el.name + '"]' : '') +
    (el.id ? '#' + el.id : '') +
    (el.placeholder ? '[placeholder="' + el.placeholder.substring(0, 20) + '"]' : '');

  // Verify the value was set
  if (el.value !== val) {
    return 'warning: value may not have persisted. Current: "' + el.value + '", expected: "' + val + '"';
  }

  return 'set: ' + desc + ' = "' + val.substring(0, 50) + '"';
})();
