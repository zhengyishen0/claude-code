// set-input.js - Set input values with batch support
// Usage: chrome-cli execute 'var _p={fields:[{type:"aria",selector:"Where",value:"Paris"}]}; <code>'
//        chrome-cli execute 'var _p={fields:[{type:"id",selector:"email",value:"test@example.com"}]}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};

  // Blocking sleep for delays between actions
  function sleep(ms) {
    var start = Date.now();
    while (Date.now() - start < ms) {}
  }

  // Find input element by type and selector
  function findInput(type, selector) {
    var el = null;
    var method = type;

    if (type === 'id') {
      // Universal id-like attribute matching
      var inputs = document.querySelectorAll('input, textarea, select, [contenteditable="true"]');
      for (var i = 0; i < inputs.length; i++) {
        var input = inputs[i];

        // Priority 1: Check id attribute first
        if (input.getAttribute('id') === selector) {
          el = input;
          method = 'id';
          break;
        }

        // Priority 2: Check ANY attribute ending in 'id'
        var attrs = input.attributes;
        for (var j = 0; j < attrs.length; j++) {
          var attrName = attrs[j].name;
          if (attrName.endsWith('id') && attrs[j].value === selector) {
            el = input;
            method = attrName;
            break;
          }
        }
        if (el) break;
      }

      // Fallback: Try as raw CSS selector
      if (!el) {
        el = document.querySelector(selector);
        if (el) method = 'selector';
      }
    } else if (type === 'aria') {
      // aria-label (partial, case-insensitive)
      var searchAria = selector.toLowerCase();
      var inputs = document.querySelectorAll('input, textarea, select, [contenteditable="true"]');
      for (var i = 0; i < inputs.length; i++) {
        var label = (inputs[i].getAttribute('aria-label') || '').toLowerCase();
        if (label.indexOf(searchAria) > -1) {
          el = inputs[i];
          break;
        }
      }
    } else if (type === 'text') {
      // placeholder or aria-label (partial, case-insensitive)
      var searchText = selector.toLowerCase();
      var inputs = document.querySelectorAll('input, textarea, select, [contenteditable="true"]');
      for (var i = 0; i < inputs.length; i++) {
        var placeholder = (inputs[i].placeholder || '').toLowerCase();
        var aria = (inputs[i].getAttribute('aria-label') || '').toLowerCase();
        if (placeholder.indexOf(searchText) > -1 || aria.indexOf(searchText) > -1) {
          el = inputs[i];
          break;
        }
      }
    }

    return { el: el, method: method };
  }

  // Set value on an input element (React-safe)
  function setValue(el, value, clear) {
    el.focus();
    el.click();

    // Clear if requested
    if (clear) {
      el.value = '';
      el.dispatchEvent(new Event('input', {bubbles: true}));
    }

    // Set value using native setter (for React)
    var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
    if (el.tagName === 'TEXTAREA') {
      setter = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    }

    if (setter && setter.set) {
      setter.set.call(el, value);
    } else {
      el.value = value;
    }

    // Dispatch events React listens to
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));

    return el.value === value;
  }

  // Get element info for output
  function getInfo(el) {
    var info = el.tagName.toLowerCase();
    if (el.id) info += '#' + el.id;
    var aria = el.getAttribute('aria-label');
    if (aria) info += ' aria="' + aria + '"';
    return info;
  }

  // Handle fields array
  var fields = p.fields || [];
  var clear = p.clear || false;

  if (fields.length === 0) {
    return 'FAIL:no fields specified';
  }

  var results = [];

  for (var i = 0; i < fields.length; i++) {
    var field = fields[i];
    var result = findInput(field.type, field.selector);

    if (!result.el) {
      return 'FAIL:field ' + (i + 1) + ' not found (' + field.type + '=' + field.selector + ')';
    }

    var success = setValue(result.el, field.value, clear);
    if (!success) {
      return 'WARN:field ' + (i + 1) + ' value mismatch (' + field.selector + ')';
    }

    results.push(result.method + ':' + field.selector);

    if (i < fields.length - 1) sleep(100);
  }

  if (fields.length === 1) {
    var result = findInput(fields[0].type, fields[0].selector);
    return 'OK:' + result.method + ' ' + getInfo(result.el) + ' = "' + fields[0].value.substring(0, 20) + '"';
  }
  return 'OK:filled ' + fields.length + ' fields';
})();
