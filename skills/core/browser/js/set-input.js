// set-input.js - Set input value by CSS selector (React-safe)
// Used internally by: chrome input SELECTOR VALUE

(function() {
  var el = document.querySelector(SELECTOR);
  if (!el) return 'FAIL: element not found';

  el.focus();
  el.click();

  // Use native setter for React compatibility
  var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement : HTMLInputElement;
  var setter = Object.getOwnPropertyDescriptor(proto.prototype, 'value');
  if (setter && setter.set) {
    setter.set.call(el, VALUE);
  } else {
    el.value = VALUE;
  }

  // Dispatch events React listens to
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));

  var tag = el.tagName.toLowerCase();
  return 'OK: set ' + tag + ' = "' + VALUE.substring(0, 20) + '"';
})();
