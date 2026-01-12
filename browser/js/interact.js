// interact.js - Universal element interaction (click or input)
// Used internally by: chrome interact SELECTOR [--input VALUE]

// Expects: INTERACT_SELECTOR, INTERACT_INPUT (optional), INTERACT_INDEX (optional)
// Use var to avoid "already declared" errors between runs
var SELECTOR = INTERACT_SELECTOR;
var INPUT_VALUE = typeof INTERACT_INPUT !== 'undefined' ? INTERACT_INPUT : null;
var INDEX = typeof INTERACT_INDEX !== 'undefined' ? INTERACT_INDEX : null;

// ============================================================================
// Configuration
// ============================================================================

var INTERACTIVE_SELECTORS = [
  'button',
  '[role="button"]',
  '[role="tab"]',
  '[role="link"]',
  '[role="menuitem"]',
  '[role="checkbox"]',
  'a',
  'input',
  'textarea',
  'select',
  '[onclick]',
  '[data-testid]'
];

// ============================================================================
// Utilities
// ============================================================================

function normalizeText(text) {
  return text ? text.replace(/\s+/g, ' ').trim() : '';
}

function isClickable(element) {
  const rect = element.getBoundingClientRect();
  const styles = window.getComputedStyle(element);

  return (
    rect.width > 0 &&
    rect.height > 0 &&
    styles.display !== 'none' &&
    styles.visibility !== 'hidden' &&
    styles.pointerEvents !== 'none' &&
    !element.disabled
  );
}

function getElementState(el) {
  // Checkbox/radio
  if (el.type === 'checkbox' || el.type === 'radio') {
    return el.checked ? 'checked' : 'unchecked';
  }

  // ARIA toggles
  if (el.getAttribute('aria-pressed')) {
    return el.getAttribute('aria-pressed') === 'true' ? 'pressed' : 'unpressed';
  }

  // ARIA expanded (dropdowns)
  if (el.getAttribute('aria-expanded')) {
    return el.getAttribute('aria-expanded') === 'true' ? 'expanded' : 'collapsed';
  }

  return null;
}

function getElementDescription(el) {
  const tag = el.tagName.toLowerCase();
  const text = normalizeText(el.innerText).substring(0, 50);
  const ariaLabel = el.getAttribute('aria-label');
  const testId = el.getAttribute('data-testid');

  let desc = tag;
  if (text) desc += ' "' + text + '"';
  if (ariaLabel) desc += ' [aria-label="' + ariaLabel + '"]';
  if (testId) desc += ' [data-testid="' + testId + '"]';

  return desc;
}

function generateSelector(el) {
  if (!el || el === document.body || el === document.documentElement) {
    return null;
  }

  // Prefer ID
  if (el.id) {
    return '#' + el.id;
  }

  // Prefer unique class combination
  if (el.className && typeof el.className === 'string') {
    const classes = el.className.trim().split(/\s+/).filter(c => c.length > 0);
    if (classes.length > 0) {
      const selector = '.' + classes.join('.');
      const matches = document.querySelectorAll(selector);
      if (matches.length === 1) {
        return selector;
      }
    }
  }

  // Prefer data-testid
  const testId = el.getAttribute('data-testid');
  if (testId) {
    return '[data-testid="' + testId + '"]';
  }

  // Fallback: tag name (not unique, but better than nothing)
  return el.tagName.toLowerCase();
}

function getCaptureContext(el) {
  const parent = el.parentElement;
  const grandparent = parent ? parent.parentElement : null;

  return {
    parent: parent ? {
      selector: generateSelector(parent),
      childCount: parent.children.length,
      innerHTML: parent.innerHTML.length
    } : null,
    grandparent: grandparent ? {
      selector: generateSelector(grandparent),
      childCount: grandparent.children.length,
      innerHTML: grandparent.innerHTML.length
    } : null
  };
}

// ============================================================================
// Element Finding
// ============================================================================

function findInteractiveElements(selector) {
  // Tier 1: CSS Selector (starts with #, ., [)
  if (/^[#.\[]/.test(selector)) {
    const el = document.querySelector(selector);
    return el ? [el] : [];
  }

  // Get all interactive elements
  const candidates = Array.from(
    document.querySelectorAll(INTERACTIVE_SELECTORS.join(','))
  ).filter(isClickable);

  const selectorNorm = normalizeText(selector);

  // Tier 2: Exact text match
  let matches = candidates.filter(el =>
    normalizeText(el.innerText) === selectorNorm
  );
  if (matches.length > 0) return matches;

  // Tier 3: Exact aria-label match
  matches = candidates.filter(el =>
    normalizeText(el.getAttribute('aria-label')) === selectorNorm
  );
  if (matches.length > 0) return matches;

  // Tier 4: Partial text match (contains)
  matches = candidates.filter(el =>
    normalizeText(el.innerText).includes(selectorNorm)
  );
  if (matches.length > 0) return matches;

  // Tier 5: Partial aria-label match
  matches = candidates.filter(el =>
    normalizeText(el.getAttribute('aria-label')).includes(selectorNorm)
  );

  return matches;
}

// ============================================================================
// Actions
// ============================================================================

function clickElement(el) {
  try {
    const stateBefore = getElementState(el);
    const contextBefore = getCaptureContext(el);

    // Only scroll if element is not in viewport
    const rect = el.getBoundingClientRect();
    const isVisible = (
      rect.top >= 0 &&
      rect.left >= 0 &&
      rect.bottom <= window.innerHeight &&
      rect.right <= window.innerWidth
    );

    if (!isVisible) {
      el.scrollIntoView({block: 'center', behavior: 'instant'});
    }

    el.click();

    const stateAfter = getElementState(el);
    const stateChange = stateBefore && stateAfter && stateBefore !== stateAfter
      ? ' (' + stateBefore + ' → ' + stateAfter + ')'
      : '';

    return JSON.stringify({
      status: 'OK',
      message: 'clicked ' + getElementDescription(el) + stateChange,
      context: contextBefore
    });
  } catch (e) {
    return JSON.stringify({
      status: 'ERROR',
      message: 'clickElement failed: ' + e.toString(),
      context: null
    });
  }
}

function inputIntoElement(el, value) {
  // Verify element can accept input
  if (!['INPUT', 'TEXTAREA'].includes(el.tagName)) {
    return JSON.stringify({
      status: 'FAIL',
      message: 'cannot type into ' + el.tagName.toLowerCase() + ' element (expected input or textarea)',
      context: null
    });
  }

  const contextBefore = getCaptureContext(el);

  el.focus();
  el.click();

  // Use native setter for React compatibility
  const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement : HTMLInputElement;
  const setter = Object.getOwnPropertyDescriptor(proto.prototype, 'value');
  if (setter && setter.set) {
    setter.set.call(el, value);
  } else {
    el.value = value;
  }

  // Dispatch events React listens to
  el.dispatchEvent(new Event('input', {bubbles: true}));
  el.dispatchEvent(new Event('change', {bubbles: true}));

  return JSON.stringify({
    status: 'OK',
    message: 'set ' + getElementDescription(el) + ' = "' + value.substring(0, 30) + '"',
    context: contextBefore
  });
}

// ============================================================================
// Main Execution
// ============================================================================

var __result;
try {
const matches = findInteractiveElements(SELECTOR);

  // No matches found
  if (matches.length === 0) {
    __result = JSON.stringify({
      status: 'FAIL',
      message: 'no element found for "' + SELECTOR + '"',
      context: null
    });
  }

  // Multiple matches - need disambiguation
  else if (matches.length > 1 && INDEX === null) {
    let details = 'found ' + matches.length + ' matches for "' + SELECTOR + '":\n';
    matches.slice(0, 5).forEach((el, i) => {
      details += '\n[' + (i + 1) + '] ' + getElementDescription(el);
    });
    if (matches.length > 5) {
      details += '\n... and ' + (matches.length - 5) + ' more';
    }
    details += '\n\nUse: interact "' + SELECTOR + '" --index N';
    __result = JSON.stringify({
      status: 'DISAMBIGUATE',
      message: details,
      context: null
    });
  }

  // Select element by index or first match
  else {
    const element = INDEX !== null ? matches[INDEX - 1] : matches[0];

    if (!element) {
      __result = JSON.stringify({
        status: 'FAIL',
        message: 'index ' + INDEX + ' out of range (found ' + matches.length + ' matches)',
        context: null
      });
    } else {
      // Perform action
      if (INPUT_VALUE !== null) {
        __result = inputIntoElement(element, INPUT_VALUE);
      } else {
        __result = clickElement(element);
      }
    }
  }

} catch (e) {
__result = JSON.stringify({
  status: 'ERROR',
  message: e.toString(),
  context: null
});
}

__result;
