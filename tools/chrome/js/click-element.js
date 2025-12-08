// click-element.js - Smart element finding + click
// Usage: chrome-cli execute 'var _p={targets:["[@Search](#btn)"], times:1}; <code>'
//        chrome-cli execute 'var _p={targets:["[+]"], times:5}; <code>'

(function() {
  var p = typeof _p !== 'undefined' ? _p : {};
  var root = document;

  // Blocking sleep for delays between actions
  function sleep(ms) {
    var start = Date.now();
    while (Date.now() - start < ms) {}
  }

  // Normalize text for fuzzy matching (whitespace only)
  function normalizeText(text) {
    return text.replace(/\s+/g, ' ').trim();
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

    // PROGRESSIVE AND LOGIC: Collect candidates (union), then filter to intersection
    var candidates = new Set();

    // Strategy 1: Collect by id-like attributes (universal matching)
    if (params.testid && params.testid !== 'button') {
      var allElements = root.querySelectorAll('*');
      for (var i = 0; i < allElements.length; i++) {
        var element = allElements[i];

        // Priority 1: Check id attribute first
        if (element.getAttribute('id') === params.testid) {
          candidates.add(element);
          continue;
        }

        // Priority 2: Check ANY attribute ending in 'id'
        var attrs = element.attributes;
        for (var j = 0; j < attrs.length; j++) {
          var attrName = attrs[j].name;
          if (attrName.endsWith('id') && attrs[j].value === params.testid) {
            candidates.add(element);
            break;
          }
        }

        // Fallback: Check class
        if (element.className && element.className.indexOf(params.testid) > -1) {
          candidates.add(element);
        }
      }
    }

    // Strategy 2: Collect by aria-label
    if (params.aria) {
      var searchAria = params.aria.toLowerCase();
      var labeled = root.querySelectorAll('[aria-label]');
      for (var i = 0; i < labeled.length; i++) {
        var ariaLabel = (labeled[i].getAttribute('aria-label') || '').toLowerCase();
        if (ariaLabel.indexOf(searchAria) > -1) {
          candidates.add(labeled[i]);
        }
      }
    }

    // Strategy 3: Collect by text content
    if (params.text) {
      var searchText = normalizeText(params.text.replace(/\\n/g, '\n').toLowerCase());
      var clickables = root.querySelectorAll('button, a, [role="button"], [onclick]');
      for (var i = 0; i < clickables.length; i++) {
        var t = normalizeText((clickables[i].innerText || '').toLowerCase());
        if (t.indexOf(searchText) > -1) {
          candidates.add(clickables[i]);
        }
      }
    }

    // Strategy 4: Collect by href
    if (params.href) {
      var links = root.querySelectorAll('a[href^="' + params.href + '"]');
      for (var i = 0; i < links.length; i++) {
        candidates.add(links[i]);
      }
    }

    // Strategy 5: Collect by CSS selector
    if (params.selector) {
      try {
        var selectorEls = root.querySelectorAll(params.selector);
        for (var i = 0; i < selectorEls.length; i++) {
          candidates.add(selectorEls[i]);
        }
      } catch (e) {
        // Invalid selector - skip
      }
    }

    // Filter to intersection: elements matching ALL provided criteria
    var validElements = Array.from(candidates).filter(function(el) {
      // Validate id-like attributes if provided
      if (params.testid && params.testid !== 'button') {
        var matched = false;

        // Priority 1: Check id attribute first
        if (el.getAttribute('id') === params.testid) {
          matched = true;
        }

        // Priority 2: Check ANY attribute ending in 'id'
        if (!matched) {
          var attrs = el.attributes;
          for (var j = 0; j < attrs.length; j++) {
            var attrName = attrs[j].name;
            if (attrName.endsWith('id') && attrs[j].value === params.testid) {
              matched = true;
              break;
            }
          }
        }

        // Fallback: Check class
        if (!matched && el.className && el.className.indexOf(params.testid) > -1) {
          matched = true;
        }

        if (!matched) {
          return false;
        }
      }

      // Validate aria if provided
      if (params.aria) {
        var ariaLabel = (el.getAttribute('aria-label') || '').toLowerCase();
        if (ariaLabel.indexOf(params.aria.toLowerCase()) === -1) {
          return false;
        }
      }

      // Validate text if provided
      if (params.text) {
        var searchText = normalizeText(params.text.replace(/\\n/g, '\n').toLowerCase());
        var elText = normalizeText((el.innerText || '').toLowerCase());
        if (elText.indexOf(searchText) === -1) {
          return false;
        }
      }

      // Validate href if provided
      if (params.href) {
        var href = el.getAttribute('href') || '';
        if (href.indexOf(params.href) !== 0) {
          return false;
        }
      }

      return true;  // Matches ALL provided criteria
    });

    if (validElements.length === 0) {
      return { el: null, method: '', params: params };
    }

    var el = validElements[0];

    // Warn if multiple matches
    if (validElements.length > 1) {
      var warning = 'WARN:found ' + validElements.length + ' matches, using first';
      console.log(warning);
    }

    // Determine method used
    var method = '';
    if (params.testid) {
      // Priority 1: id attribute
      if (el.getAttribute('id') === params.testid) {
        method = 'id';
      } else {
        // Priority 2: ANY attribute ending in 'id'
        var attrs = el.attributes;
        for (var j = 0; j < attrs.length; j++) {
          var attrName = attrs[j].name;
          if (attrName.endsWith('id') && attrs[j].value === params.testid) {
            method = attrName;
            break;
          }
        }
        // Fallback: class
        if (!method && el.className && el.className.indexOf(params.testid) > -1) {
          method = 'class';
        }
      }
    } else if (params.aria) {
      method = 'aria';
    } else if (params.text) {
      method = 'text';
    } else if (params.href) {
      method = 'href';
    } else {
      method = 'selector';
    }

    return { el: el, method: method, params: params, count: validElements.length };
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

  // Generate diagnostic error message
  function generateErrorReport(params, root) {
    var report = [];

    // Check each criterion and report findings
    if (params.testid) {
      var idMatches = root.querySelectorAll('[id="' + params.testid + '"]').length;
      var attrMatches = 0;
      var allEls = root.querySelectorAll('*');
      for (var i = 0; i < allEls.length; i++) {
        var attrs = allEls[i].attributes;
        for (var j = 0; j < attrs.length; j++) {
          if (attrs[j].name.endsWith('id') && attrs[j].value === params.testid) {
            attrMatches++;
            break;
          }
        }
      }
      var classMatches = root.querySelectorAll('[class*="' + params.testid + '"]').length;
      report.push('testid=' + params.testid + ' (id:' + idMatches + ', *id:' + attrMatches + ', class:' + classMatches + ')');
    }

    if (params.aria) {
      var ariaMatches = root.querySelectorAll('[aria-label*="' + params.aria + '"]').length;
      report.push('aria=' + params.aria + ' (' + ariaMatches + ' found)');
    }

    if (params.text) {
      var searchText = normalizeText(params.text.replace(/\\n/g, '\n').toLowerCase());
      var clickables = root.querySelectorAll('button, a, [role="button"], [onclick]');
      var textMatches = 0;
      for (var i = 0; i < clickables.length; i++) {
        var t = normalizeText((clickables[i].innerText || '').toLowerCase());
        if (t.indexOf(searchText) > -1) textMatches++;
      }
      report.push('text=' + params.text + ' (' + textMatches + ' found)');
    }

    if (params.href) {
      var hrefMatches = root.querySelectorAll('a[href^="' + params.href + '"]').length;
      report.push('href=' + params.href + ' (' + hrefMatches + ' found)');
    }

    if (params.selector) {
      try {
        var selectorMatches = root.querySelectorAll(params.selector).length;
        report.push('selector=' + params.selector + ' (' + selectorMatches + ' found)');
      } catch (e) {
        report.push('selector=' + params.selector + ' (invalid)');
      }
    }

    return report.join(', ');
  }

  // Get element info for output
  function getInfo(el) {
    var info = el.tagName.toLowerCase();
    if (el.id) info += '#' + el.id;
    var txt = (el.innerText || '').trim().substring(0, 25);
    if (txt) info += ' "' + txt + '"';
    return info;
  }

  // Handle single target
  var targets = p.targets || [];
  var times = p.times || 1;
  var delay = p.delay || 100;

  if (targets.length === 0) {
    return 'FAIL:no targets specified';
  }

  if (targets.length > 1) {
    return 'FAIL:multiple targets not supported, use chaining instead';
  }

  var target = targets[0];

  // times > 1: click same element multiple times
  // Re-find element each time for React components that re-render after state change
  if (times > 1) {
    for (var i = 0; i < times; i++) {
      var result = findElement(target);
      if (!result.el) {
        return 'FAIL:click ' + (i + 1) + ' not found (' + generateErrorReport(result.params, root) + ')';
      }
      clickElement(result.el);
      if (i < times - 1) sleep(delay);
    }
    var lastResult = findElement(target);
    var msg = 'OK:clicked ' + times + ' times ' + getInfo(lastResult.el);
    if (lastResult.count > 1) {
      msg = 'OK(' + lastResult.count + ' matches):clicked ' + times + ' times ' + getInfo(lastResult.el);
    }
    return msg;
  }

  // times=1: single click
  var result = findElement(target);
  if (!result.el) {
    return 'FAIL:target not found (' + generateErrorReport(result.params, root) + ')';
  }

  clickElement(result.el);
  var msg = 'OK:' + result.method + ' ' + getInfo(result.el);
  if (result.count > 1) {
    msg = 'OK(' + result.count + ' matches):' + result.method + ' ' + getInfo(result.el);
  }
  return msg;
})();
