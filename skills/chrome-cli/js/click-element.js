// click-element.js - Smart element finding + click
// Accepts recon format: [text@aria](#testid) or individual params
// Usage: chrome-cli execute 'var _p={auto:"[@Search](#search-btn)"}; <code>'
//        chrome-cli execute 'var _p={testid:"search-btn"}; <code>'
//        chrome-cli execute 'var _p={auto:"[@Close](#button)", section:"Provide feedback"}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};
  var el = null;
  var method = '';
  var root = document;  // default: search entire document

  // If section specified, find the container first
  if (p.section) {
    var sectionLower = p.section.toLowerCase();

    // Strategy 1: Match aria-label of semantic containers
    var containers = document.querySelectorAll('dialog,[role=dialog],section,article,form,header,main,nav,aside,footer,[aria-label]');
    for (var i = 0; i < containers.length; i++) {
      var label = (containers[i].getAttribute('aria-label') || '').toLowerCase();
      if (label && label.indexOf(sectionLower) > -1) {
        root = containers[i];
        break;
      }
    }

    // Strategy 2: Match heading text inside semantic containers
    if (root === document) {
      var headings = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
      for (var i = 0; i < headings.length; i++) {
        var hText = (headings[i].textContent || '').toLowerCase();
        if (hText.indexOf(sectionLower) > -1) {
          root = headings[i].closest('dialog,[role=dialog],section,article,form,header,main,nav,aside,footer') || headings[i].parentElement;
          break;
        }
      }
    }

    // Strategy 3: Direct tag/selector match (e.g., "main", "header", "#my-form")
    if (root === document) {
      var direct = document.querySelector(p.section);
      if (direct) root = direct;
    }

    // If still not found, return error
    if (root === document) {
      return 'FAIL:section not found (' + p.section + ')';
    }
  }

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

  // Strategy 1: data-testid OR id (try both with single query)
  if (!el && p.testid) {
    // Try data-testid first, then id - works for both React and traditional sites
    el = root.querySelector('[data-testid="' + p.testid + '"], #' + p.testid);
    if (el) method = el.getAttribute('data-testid') ? 'testid' : 'id';
  }

  // Strategy 2: aria-label (partial, case-insensitive)
  if (!el && p.aria) {
    var searchAria = p.aria.toLowerCase();
    var labeled = root.querySelectorAll('[aria-label]');
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
  // Supports literal \n in search text (from recon output)
  if (!el && p.text) {
    var searchText = p.text.replace(/\\n/g, '\n').toLowerCase();
    var clickables = root.querySelectorAll('button, a, [role="button"], [onclick]');
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
    el = root.querySelector('a[href^="' + p.href + '"]');
    if (el) method = 'href';
  }

  // Strategy 5: CSS selector (fallback)
  if (!el && p.selector) {
    el = root.querySelector(p.selector);
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
