// click-element.js - Simple element finding + click
// Usage: chrome-cli execute 'var _p={text:"Button"}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};
  var el = null;
  var method = '';

  // Strategy 1: CSS selector
  if (p.selector) {
    el = document.querySelector(p.selector);
    method = 'selector';
  }
  // Strategy 2: Text content (partial, case-insensitive)
  else if (p.text) {
    var searchText = p.text.toLowerCase();
    var clickables = document.querySelectorAll('button, a, [role="button"], [onclick]');
    for (var i = 0; i < clickables.length; i++) {
      var t = (clickables[i].innerText || '').toLowerCase();
      if (t.indexOf(searchText) > -1) {
        el = clickables[i];
        break;
      }
    }
    method = 'text';
  }
  // Strategy 3: aria-label (partial, case-insensitive)
  else if (p.aria) {
    var searchAria = p.aria.toLowerCase();
    var labeled = document.querySelectorAll('[aria-label]');
    for (var i = 0; i < labeled.length; i++) {
      var label = (labeled[i].getAttribute('aria-label') || '').toLowerCase();
      if (label.indexOf(searchAria) > -1) {
        el = labeled[i];
        break;
      }
    }
    method = 'aria';
  }
  // Strategy 4: data-testid (exact)
  else if (p.testid) {
    el = document.querySelector('[data-testid="' + p.testid + '"]');
    method = 'testid';
  }

  if (!el) {
    return 'FAIL:not found (' + method + ')';
  }

  // Scroll into view and click
  el.scrollIntoView({block: 'center', behavior: 'instant'});
  el.click();

  // Return success with element info
  var info = el.tagName.toLowerCase();
  if (el.id) info += '#' + el.id;
  var txt = (el.innerText || '').trim().substring(0, 25);
  if (txt) info += ' "' + txt + '"';

  return 'OK:' + method + ' ' + info;
})();
