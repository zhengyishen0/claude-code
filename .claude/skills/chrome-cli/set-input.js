// set-input.js - Simple input value setting
// Usage: chrome-cli execute 'var _p={selector:"#email",value:"test@example.com"}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};

  if (!p.selector) return 'FAIL:no selector';
  if (p.value === undefined) return 'FAIL:no value';

  var el = document.querySelector(p.selector);
  if (!el) return 'FAIL:not found ' + p.selector;

  // Focus and click
  el.focus();
  el.click();

  // Clear if requested
  if (p.clear) {
    el.value = '';
    el.dispatchEvent(new Event('input', {bubbles: true}));
  }

  // Set value using native setter (for React)
  var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
  if (el.tagName === 'TEXTAREA') {
    setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
  }

  if (setter && setter.set) {
    setter.set.call(el, p.value);
  } else {
    el.value = p.value;
  }

  // Dispatch events React listens to
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));

  // Verify
  if (el.value === p.value) {
    return 'OK:' + p.selector + ' = "' + p.value.substring(0, 20) + '"';
  } else {
    return 'WARN:value is "' + el.value + '" not "' + p.value + '"';
  }
})();
