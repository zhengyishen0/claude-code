// click-element.js - Smart element finding + click
// Accepts recon format: [text@aria](#testid) or individual params
// Usage: chrome-cli execute 'var _p={auto:"[@Search](#search-btn)"}; <code>'
//        chrome-cli execute 'var _p={testid:"search-btn"}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};
  var el = null;
  var method = '';

  // Parse auto format: [text@aria](#testid) or [@aria](#testid) or [text](#testid)
  // If not recon format, treat as CSS selector
  if (p.auto) {
    var match = p.auto.match(/^\[([^\]]*)\]\(([^)]+)\)$/);
    if (match) {
      var label = match[1];  // text@aria or @aria or text
      var target = match[2]; // #testid or /href

      // Parse label for text and aria
      if (label.startsWith('@')) {
        // [@aria] - aria only
        p.aria = label.substring(1);
      } else if (label.indexOf('@') > 0) {
        // [text@aria] - both
        var parts = label.split('@');
        p.text = parts[0];
        p.aria = parts[1];
      } else {
        // [text] - text only
        p.text = label;
      }

      // Parse target for testid or href
      if (target.startsWith('#') && target !== '#button') {
        p.testid = target.substring(1);
      } else if (target.startsWith('/')) {
        p.href = target;
      }
    } else {
      // Not recon format - treat as CSS selector
      p.selector = p.auto;
    }
  }

  // Priority: testid > aria > text > href > selector

  // Strategy 1: data-testid (most reliable)
  if (!el && p.testid) {
    el = document.querySelector('[data-testid="' + p.testid + '"]');
    if (el) method = 'testid';
  }

  // Strategy 2: aria-label (partial, case-insensitive)
  if (!el && p.aria) {
    var searchAria = p.aria.toLowerCase();
    var labeled = document.querySelectorAll('[aria-label]');
    for (var i = 0; i < labeled.length; i++) {
      var label = (labeled[i].getAttribute('aria-label') || '').toLowerCase();
      if (label.indexOf(searchAria) > -1) {
        el = labeled[i];
        method = 'aria';
        break;
      }
    }
  }

  // Strategy 3: Text content (partial, case-insensitive)
  if (!el && p.text) {
    var searchText = p.text.toLowerCase();
    var clickables = document.querySelectorAll('button, a, [role="button"], [onclick]');
    for (var i = 0; i < clickables.length; i++) {
      var t = (clickables[i].innerText || '').toLowerCase();
      if (t.indexOf(searchText) > -1) {
        el = clickables[i];
        method = 'text';
        break;
      }
    }
  }

  // Strategy 4: href for links
  if (!el && p.href) {
    el = document.querySelector('a[href^="' + p.href + '"]');
    if (el) method = 'href';
  }

  // Strategy 5: CSS selector (fallback)
  if (!el && p.selector) {
    el = document.querySelector(p.selector);
    if (el) method = 'selector';
  }

  if (!el) {
    var tried = [];
    if (p.testid) tried.push('testid=' + p.testid);
    if (p.aria) tried.push('aria=' + p.aria);
    if (p.text) tried.push('text=' + p.text);
    if (p.href) tried.push('href=' + p.href);
    if (p.selector) tried.push('selector=' + p.selector);
    return 'FAIL:not found (' + tried.join(', ') + ')';
  }

  // Scroll into view and click
  el.scrollIntoView({block: 'center', behavior: 'instant'});

  // For <a> tags with href, navigate directly (click() doesn't work in SPAs)
  if (el.tagName === 'A' && el.href) {
    window.location.href = el.href;
  } else {
    el.click();
  }

  // Return success with element info
  var info = el.tagName.toLowerCase();
  if (el.id) info += '#' + el.id;
  var txt = (el.innerText || '').trim().substring(0, 25);
  if (txt) info += ' "' + txt + '"';

  return 'OK:' + method + ' ' + info;
})();
