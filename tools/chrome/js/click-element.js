// click-element.js - Smart element finding + click with batch support
// Usage: chrome-cli execute 'var _p={targets:["[@Search](#btn)"], times:1}; <code>'
//        chrome-cli execute 'var _p={targets:["[a]","[b]"], times:1}; <code>'
//        chrome-cli execute 'var _p={targets:["[+]"], times:5}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};
  var root = document;

  // Blocking sleep for delays between actions
  function sleep(ms) {
    var start = Date.now();
    while (Date.now() - start < ms) {}
  }

  // If section specified, find the container first
  if (p.section) {
    var sectionLower = p.section.toLowerCase();

    // Strategy 1: Match aria-label of semantic containers only
    var containers = document.querySelectorAll('dialog,[role=dialog],section,article,form,header,main,nav,aside,footer');
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

  // Parse recon format and find element
  function findElement(auto) {
    var params = {};

    // Parse auto format: [text@aria](#testid) or [@aria](#testid) or [text](#testid)
    var match = auto.match(/^\[([^\]]*)\]\(([^)]+)\)$/);
    if (match) {
      var label = match[1];  // text@aria or @aria or text
      var target = match[2]; // #testid or /href

      // Parse label for text and aria
      if (label.indexOf('@') === 0) {
        // [@aria] - aria only
        params.aria = label.substring(1);
      } else if (label.indexOf('@') > 0) {
        // [text@aria] - both
        var parts = label.split('@');
        params.text = parts[0];
        params.aria = parts[1];
      } else {
        // [text] - text only
        params.text = label;
      }

      // Parse target for testid or href
      if (target.indexOf('#') === 0 && target !== '#button') {
        params.testid = target.substring(1);
      } else if (target.indexOf('/') === 0) {
        params.href = target;
      }
    } else {
      // Not recon format - treat as CSS selector
      params.selector = auto;
    }

    var el = null;
    var method = '';

    // Strategy 1: data-testid OR id OR class
    if (!el && params.testid && params.testid !== 'button') {
      el = root.querySelector('[data-testid="' + params.testid + '"], #' + params.testid + ', .' + params.testid);
      if (el) {
        method = el.getAttribute('data-testid') === params.testid ? 'testid' :
                 el.id === params.testid ? 'id' : 'class';
      }
    }

    // Strategy 2: aria-label (partial, case-insensitive)
    if (!el && params.aria) {
      var searchAria = params.aria.toLowerCase();
      var labeled = root.querySelectorAll('[aria-label]');
      for (var i = 0; i < labeled.length; i++) {
        var ariaLabel = (labeled[i].getAttribute('aria-label') || '').toLowerCase();
        if (ariaLabel.indexOf(searchAria) > -1) {
          el = labeled[i];
          method = 'aria';
          break;
        }
      }
    }

    // Strategy 3: Text content (partial, case-insensitive)
    if (!el && params.text) {
      var searchText = params.text.replace(/\\n/g, '\n').toLowerCase();
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
    if (!el && params.href) {
      el = root.querySelector('a[href^="' + params.href + '"]');
      if (el) method = 'href';
    }

    // Strategy 5: CSS selector (fallback)
    if (!el && params.selector) {
      el = root.querySelector(params.selector);
      if (el) method = 'selector';
    }

    return { el: el, method: method, params: params };
  }

  // Click an element
  function clickElement(el) {
    el.scrollIntoView({block: 'center', behavior: 'instant'});
    // For <a> tags with href, navigate directly (click() doesn't work in SPAs)
    if (el.tagName === 'A' && el.href) {
      window.location.href = el.href;
    } else {
      el.click();
    }
  }

  // Get element info for output
  function getInfo(el) {
    var info = el.tagName.toLowerCase();
    if (el.id) info += '#' + el.id;
    var txt = (el.innerText || '').trim().substring(0, 25);
    if (txt) info += ' "' + txt + '"';
    return info;
  }

  // Handle targets array
  var targets = p.targets || [];
  var times = p.times || 1;
  var delay = p.delay || 100;

  if (targets.length === 0) {
    return 'FAIL:no targets specified';
  }

  // Single target with times > 1: click same element multiple times
  // Re-find element each time for React components that re-render after state change
  if (targets.length === 1 && times > 1) {
    for (var i = 0; i < times; i++) {
      var result = findElement(targets[0]);
      if (!result.el) {
        var tried = [];
        if (result.params.testid) tried.push('testid=' + result.params.testid);
        if (result.params.aria) tried.push('aria=' + result.params.aria);
        if (result.params.text) tried.push('text=' + result.params.text);
        if (result.params.href) tried.push('href=' + result.params.href);
        if (result.params.selector) tried.push('selector=' + result.params.selector);
        return 'FAIL:click ' + (i + 1) + ' not found (' + tried.join(', ') + ')';
      }
      clickElement(result.el);
      if (i < times - 1) sleep(delay);
    }
    var lastResult = findElement(targets[0]);
    return 'OK:clicked ' + times + ' times ' + getInfo(lastResult.el);
  }

  // Multiple targets or single target with times=1: click each once
  for (var i = 0; i < targets.length; i++) {
    var result = findElement(targets[i]);
    if (!result.el) {
      var tried = [];
      if (result.params.testid) tried.push('testid=' + result.params.testid);
      if (result.params.aria) tried.push('aria=' + result.params.aria);
      if (result.params.text) tried.push('text=' + result.params.text);
      if (result.params.href) tried.push('href=' + result.params.href);
      if (result.params.selector) tried.push('selector=' + result.params.selector);
      return 'FAIL:target ' + (i + 1) + ' not found (' + tried.join(', ') + ')';
    }

    clickElement(result.el);
    if (i < targets.length - 1) sleep(delay);
  }

  if (targets.length === 1) {
    var result = findElement(targets[0]);
    return 'OK:' + result.method + ' ' + getInfo(result.el);
  }
  return 'OK:clicked ' + targets.length + ' elements';
})();
