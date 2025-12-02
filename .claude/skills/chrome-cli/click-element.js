// click-element.js - Robust clicking for React/SPA apps
// Usage: chrome-cli execute "const selector='SELECTOR'; $(cat click-element.js)"
// Returns: "clicked: <element info>" or "failed: <reason>"

(function() {
  const sel = typeof selector !== 'undefined' ? selector : null;
  if (!sel) return 'failed: no selector provided. Usage: const selector=".btn"; ...';

  const el = document.querySelector(sel);
  if (!el) return 'failed: element not found: ' + sel;

  const rect = el.getBoundingClientRect();
  const style = getComputedStyle(el);

  // Check visibility
  if (rect.width === 0 || rect.height === 0) return 'failed: element has no size';
  if (style.display === 'none') return 'failed: element is display:none';
  if (style.visibility === 'hidden') return 'failed: element is hidden';
  if (style.pointerEvents === 'none') return 'failed: element has pointer-events:none';

  // Scroll into view if needed
  el.scrollIntoView({ block: 'center', behavior: 'instant' });

  // Get element description
  const desc = el.tagName.toLowerCase() +
    (el.id ? '#' + el.id : '') +
    (el.className ? '.' + el.className.split(' ')[0] : '') +
    (el.innerText ? ' "' + el.innerText.trim().substring(0, 30) + '"' : '');

  // Strategy 1: Focus + Enter (for buttons)
  if (el.tagName === 'BUTTON' || el.getAttribute('role') === 'button') {
    el.focus();
  }

  // Strategy 2: Native click
  el.click();

  // Strategy 3: MouseEvent sequence (for React)
  const centerX = rect.left + rect.width / 2;
  const centerY = rect.top + rect.height / 2;

  const mouseOpts = {
    view: window,
    bubbles: true,
    cancelable: true,
    clientX: centerX,
    clientY: centerY,
    button: 0
  };

  el.dispatchEvent(new MouseEvent('mousedown', mouseOpts));
  el.dispatchEvent(new MouseEvent('mouseup', mouseOpts));
  el.dispatchEvent(new MouseEvent('click', mouseOpts));

  // Strategy 4: PointerEvent (modern browsers, some React versions need this)
  try {
    const pointerOpts = {
      ...mouseOpts,
      pointerId: 1,
      pointerType: 'mouse',
      isPrimary: true
    };
    el.dispatchEvent(new PointerEvent('pointerdown', pointerOpts));
    el.dispatchEvent(new PointerEvent('pointerup', pointerOpts));
  } catch (e) {
    // PointerEvent might not be supported
  }

  return 'clicked: ' + desc;
})();
