// set-input.js - Simple input value setting with multiple selector strategies
// Usage: chrome-cli execute 'var _p={selector:"#email",value:"test@example.com"}; <code>'
//        chrome-cli execute 'var _p={aria:"Where",value:"New York"}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};

  if (p.value === undefined) return 'FAIL:no value';

  var el = null;
  var method = '';

  // Strategy 1: CSS selector
  if (p.selector) {
    el = document.querySelector(p.selector);
    method = 'selector';
  }
  // Strategy 2: aria-label (partial, case-insensitive)
  else if (p.aria) {
    var searchAria = p.aria.toLowerCase();
    var inputs = document.querySelectorAll('input, textarea, select, [contenteditable="true"]');
    for (var i = 0; i < inputs.length; i++) {
      var label = (inputs[i].getAttribute('aria-label') || '').toLowerCase();
      if (label.indexOf(searchAria) > -1) {
        el = inputs[i];
        break;
      }
    }
    method = 'aria';
  }
  // Strategy 3: placeholder text (partial, case-insensitive)
  else if (p.text) {
    var searchText = p.text.toLowerCase();
    var inputs = document.querySelectorAll('input, textarea');
    for (var i = 0; i < inputs.length; i++) {
      var placeholder = (inputs[i].placeholder || '').toLowerCase();
      if (placeholder.indexOf(searchText) > -1) {
        el = inputs[i];
        break;
      }
    }
    method = 'text';
  }
  // Strategy 4: data-testid (exact)
  else if (p.testid) {
    el = document.querySelector('input[data-testid="' + p.testid + '"], textarea[data-testid="' + p.testid + '"]');
    method = 'testid';
  }

  if (!el) return 'FAIL:not found (' + method + ')';

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
  var info = el.tagName.toLowerCase();
  if (el.id) info += '#' + el.id;
  var aria = el.getAttribute('aria-label');
  if (aria) info += ' aria="' + aria + '"';

  if (el.value === p.value) {
    return 'OK:' + method + ' ' + info + ' = "' + p.value.substring(0, 20) + '"';
  } else {
    return 'WARN:' + method + ' value is "' + el.value + '" not "' + p.value + '"';
  }
})();
