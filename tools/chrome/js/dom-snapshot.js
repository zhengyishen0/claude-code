// dom-snapshot.js - Create and compare DOM snapshots for diff
// Used by recon --diff to show only what changed

(function() {
  // Generate a stable path for an element
  function getElementPath(el) {
    const parts = [];
    let current = el;
    while (current && current !== document.body && current !== document.documentElement) {
      let selector = current.tagName.toLowerCase();

      // Add id if exists
      if (current.id) {
        selector += '#' + current.id;
      } else {
        // Add nth-child for uniqueness
        const parent = current.parentElement;
        if (parent) {
          const siblings = Array.from(parent.children).filter(c => c.tagName === current.tagName);
          if (siblings.length > 1) {
            const index = siblings.indexOf(current) + 1;
            selector += ':nth-of-type(' + index + ')';
          }
        }
      }

      parts.unshift(selector);
      current = current.parentElement;
    }
    return parts.join(' > ');
  }

  // Get element's key properties for comparison
  function getElementProps(el) {
    const tag = el.tagName.toLowerCase();
    const props = {
      tag: tag,
      text: el.innerText?.trim().substring(0, 100) || '',
      role: el.getAttribute('role') || '',
      ariaLabel: el.getAttribute('aria-label') || '',
      disabled: el.disabled || el.getAttribute('aria-disabled') === 'true',
      hidden: el.hidden || el.getAttribute('aria-hidden') === 'true',
    };

    // For inputs, track value
    if (['input', 'textarea', 'select'].includes(tag)) {
      props.value = el.value || '';
      props.type = el.getAttribute('type') || 'text';
      props.name = el.getAttribute('name') || '';
      props.placeholder = el.getAttribute('placeholder') || '';
    }

    // For links, track href
    if (tag === 'a') {
      props.href = el.getAttribute('href') || '';
    }

    return props;
  }

  // Get CSS selector for an element (for output)
  function getSelector(el) {
    const parts = [];
    const tag = el.tagName.toLowerCase();

    if (['button', 'input', 'select', 'textarea', 'a'].includes(tag)) {
      parts.push(tag);
    }

    const id = el.getAttribute('id');
    if (id && id.length < 50 && !/\s/.test(id)) {
      parts.push('#' + id);
    }

    for (let i = 0; i < el.attributes.length; i++) {
      const attr = el.attributes[i];
      if (attr.name.startsWith('data-') &&
          !attr.name.includes('style') &&
          !attr.name.includes('class') &&
          attr.value && attr.value.length < 50) {
        parts.push('[' + attr.name + '="' + attr.value + '"]');
      }
    }

    const aria = el.getAttribute('aria-label');
    if (aria && aria.length < 50) {
      parts.push('[aria-label="' + aria + '"]');
    }

    const role = el.getAttribute('role');
    if (role && !(tag === 'button' && role === 'button')) {
      parts.push('[role="' + role + '"]');
    }

    const name = el.getAttribute('name');
    if (name && name.length < 50) {
      parts.push('[name="' + name + '"]');
    }

    return parts.length > 0 ? parts.join('') : tag;
  }

  // Check if element is interactive/relevant
  function isRelevantElement(el) {
    const tag = el.tagName.toLowerCase();
    const role = el.getAttribute('role');

    // Interactive elements
    if (['button', 'input', 'select', 'textarea', 'a'].includes(tag)) return true;
    if (['button', 'link', 'menuitem', 'tab', 'checkbox', 'radio', 'option', 'listbox', 'combobox', 'textbox', 'dialog', 'alert', 'alertdialog'].includes(role)) return true;

    // Semantic sections
    if (['header', 'main', 'nav', 'aside', 'footer', 'article', 'section', 'form', 'dialog'].includes(tag)) return true;

    // Headings
    if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)) return true;

    // Clickable elements
    if (el.onclick || el.getAttribute('onclick') || el.getAttribute('tabindex') === '0') return true;

    return false;
  }

  // Check if element is visible
  function isVisible(el) {
    if (!el.offsetParent && el.tagName.toLowerCase() !== 'body' &&
        getComputedStyle(el).position !== 'fixed' &&
        getComputedStyle(el).position !== 'absolute') return false;
    const rect = el.getBoundingClientRect();
    if (rect.width === 0 && rect.height === 0) return false;
    const style = getComputedStyle(el);
    if (style.visibility === 'hidden' || style.opacity === '0') return false;
    return true;
  }

  // Create snapshot of current DOM
  function createSnapshot() {
    const snapshot = {};
    const elements = document.querySelectorAll('*');

    elements.forEach(el => {
      if (!isRelevantElement(el)) return;
      if (!isVisible(el)) return;

      const path = getElementPath(el);
      snapshot[path] = {
        path: path,
        selector: getSelector(el),
        props: getElementProps(el),
        element: el  // Keep reference for diff output
      };
    });

    return snapshot;
  }

  // Compare two snapshots and return diff
  function diffSnapshots(before, after) {
    const changes = {
      added: [],
      removed: [],
      changed: []
    };

    // Find added and changed
    for (const path in after) {
      if (!(path in before)) {
        changes.added.push(after[path]);
      } else {
        // Check if properties changed
        const beforeProps = before[path].props;
        const afterProps = after[path].props;
        const diffs = [];

        if (beforeProps.text !== afterProps.text) {
          diffs.push({ prop: 'text', from: beforeProps.text, to: afterProps.text });
        }
        if (beforeProps.disabled !== afterProps.disabled) {
          diffs.push({ prop: 'disabled', from: beforeProps.disabled, to: afterProps.disabled });
        }
        if (beforeProps.hidden !== afterProps.hidden) {
          diffs.push({ prop: 'hidden', from: beforeProps.hidden, to: afterProps.hidden });
        }
        if (beforeProps.value !== afterProps.value) {
          diffs.push({ prop: 'value', from: beforeProps.value, to: afterProps.value });
        }

        if (diffs.length > 0) {
          changes.changed.push({
            ...after[path],
            diffs: diffs
          });
        }
      }
    }

    // Find removed
    for (const path in before) {
      if (!(path in after)) {
        changes.removed.push(before[path]);
      }
    }

    return changes;
  }

  // Format diff as readable output
  function formatDiff(changes) {
    const lines = [];

    lines.push('# DOM Changes');
    lines.push('');
    lines.push('**URL:** ' + location.href);
    lines.push('');
    lines.push('---');

    if (changes.added.length === 0 && changes.removed.length === 0 && changes.changed.length === 0) {
      lines.push('');
      lines.push('No changes detected.');
      return lines.join('\n');
    }

    if (changes.added.length > 0) {
      lines.push('');
      lines.push('## Added');
      changes.added.forEach(item => {
        const text = item.props.text ? ': ' + item.props.text.substring(0, 50) : '';
        lines.push('- + ' + item.selector + text);
      });
    }

    if (changes.removed.length > 0) {
      lines.push('');
      lines.push('## Removed');
      changes.removed.forEach(item => {
        const text = item.props.text ? ': ' + item.props.text.substring(0, 50) : '';
        lines.push('- - ' + item.selector + text);
      });
    }

    if (changes.changed.length > 0) {
      lines.push('');
      lines.push('## Changed');
      changes.changed.forEach(item => {
        lines.push('- ~ ' + item.selector);
        item.diffs.forEach(d => {
          if (d.prop === 'text') {
            lines.push('    text: "' + d.from.substring(0, 30) + '" → "' + d.to.substring(0, 30) + '"');
          } else if (d.prop === 'disabled') {
            lines.push('    disabled: ' + d.from + ' → ' + d.to);
          } else if (d.prop === 'hidden') {
            lines.push('    hidden: ' + d.from + ' → ' + d.to);
          } else if (d.prop === 'value') {
            lines.push('    value: "' + d.from.substring(0, 30) + '" → "' + d.to.substring(0, 30) + '"');
          }
        });
      });
    }

    // Summary
    lines.push('');
    lines.push('---');
    lines.push('Summary: +' + changes.added.length + ' added, -' + changes.removed.length + ' removed, ~' + changes.changed.length + ' changed');

    return lines.join('\n');
  }

  // Main: either take snapshot or diff
  const mode = window.__RECON_DIFF_MODE__;  // 'snapshot' or 'diff'

  if (mode === 'diff') {
    const before = window.__RECON_SNAPSHOT__ || {};
    const after = createSnapshot();
    const changes = diffSnapshots(before, after);

    // Update snapshot for next diff
    window.__RECON_SNAPSHOT__ = after;

    return formatDiff(changes);
  } else {
    // Just take snapshot (called after normal recon)
    window.__RECON_SNAPSHOT__ = createSnapshot();
    return 'Snapshot saved';
  }
})();
