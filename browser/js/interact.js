// interact.js - Universal element interaction (click, input, hover, drag)
// Used internally by: chrome interact SELECTOR [--input VALUE] [--action ACTION]

// Expects: INTERACT_SELECTOR, INTERACT_INPUT (optional), INTERACT_INDEX (optional), INTERACT_ACTION (optional)
// Use var to avoid "already declared" errors between runs
var SELECTOR = INTERACT_SELECTOR;
var INPUT_VALUE = typeof INTERACT_INPUT !== 'undefined' ? INTERACT_INPUT : null;
var INDEX = typeof INTERACT_INDEX !== 'undefined' ? INTERACT_INDEX : null;
var ACTION = typeof INTERACT_ACTION !== 'undefined' ? INTERACT_ACTION : 'click';
var DRAG_TARGET = typeof INTERACT_DRAG_TARGET !== 'undefined' ? INTERACT_DRAG_TARGET : null;

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
  // Tier 1: CSS Selector
  // Matches: #id, .class, [attr], tag#id, tag.class, tag[attr], tag:pseudo
  if (/^[#.\[]/.test(selector) || /^[a-z]+[#.\[:]/.test(selector)) {
    try {
      const el = document.querySelector(selector);
      return el ? [el] : [];
    } catch (e) {
      // Invalid CSS selector, fall through to text matching
    }
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

function hoverElement(el) {
  try {
    const contextBefore = getCaptureContext(el);

    // Scroll into view if needed
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

    // Dispatch mouse events for hover
    el.dispatchEvent(new MouseEvent('mouseenter', {bubbles: true, cancelable: true}));
    el.dispatchEvent(new MouseEvent('mouseover', {bubbles: true, cancelable: true}));

    return JSON.stringify({
      status: 'OK',
      message: 'hovered ' + getElementDescription(el),
      context: contextBefore
    });
  } catch (e) {
    return JSON.stringify({
      status: 'ERROR',
      message: 'hoverElement failed: ' + e.toString(),
      context: null
    });
  }
}

function dragElement(sourceEl, targetEl) {
  try {
    const contextBefore = getCaptureContext(sourceEl);

    // Scroll source into view
    sourceEl.scrollIntoView({block: 'center', behavior: 'instant'});

    const sourceRect = sourceEl.getBoundingClientRect();
    const targetRect = targetEl.getBoundingClientRect();

    const sourceX = sourceRect.left + sourceRect.width / 2;
    const sourceY = sourceRect.top + sourceRect.height / 2;
    const targetX = targetRect.left + targetRect.width / 2;
    const targetY = targetRect.top + targetRect.height / 2;

    // Simulate drag sequence
    const dataTransfer = new DataTransfer();

    sourceEl.dispatchEvent(new MouseEvent('mousedown', {
      bubbles: true, cancelable: true, clientX: sourceX, clientY: sourceY
    }));

    sourceEl.dispatchEvent(new DragEvent('dragstart', {
      bubbles: true, cancelable: true, clientX: sourceX, clientY: sourceY, dataTransfer
    }));

    targetEl.dispatchEvent(new DragEvent('dragenter', {
      bubbles: true, cancelable: true, clientX: targetX, clientY: targetY, dataTransfer
    }));

    targetEl.dispatchEvent(new DragEvent('dragover', {
      bubbles: true, cancelable: true, clientX: targetX, clientY: targetY, dataTransfer
    }));

    targetEl.dispatchEvent(new DragEvent('drop', {
      bubbles: true, cancelable: true, clientX: targetX, clientY: targetY, dataTransfer
    }));

    sourceEl.dispatchEvent(new DragEvent('dragend', {
      bubbles: true, cancelable: true, clientX: targetX, clientY: targetY, dataTransfer
    }));

    targetEl.dispatchEvent(new MouseEvent('mouseup', {
      bubbles: true, cancelable: true, clientX: targetX, clientY: targetY
    }));

    return JSON.stringify({
      status: 'OK',
      message: 'dragged ' + getElementDescription(sourceEl) + ' to ' + getElementDescription(targetEl),
      context: contextBefore
    });
  } catch (e) {
    return JSON.stringify({
      status: 'ERROR',
      message: 'dragElement failed: ' + e.toString(),
      context: null
    });
  }
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
      // Perform action based on ACTION type
      if (ACTION === 'hover') {
        __result = hoverElement(element);
      } else if (ACTION === 'drag') {
        // Drag requires a target element
        if (!DRAG_TARGET) {
          __result = JSON.stringify({
            status: 'FAIL',
            message: 'drag requires a target selector',
            context: null
          });
        } else {
          const targetMatches = findInteractiveElements(DRAG_TARGET);
          if (targetMatches.length === 0) {
            __result = JSON.stringify({
              status: 'FAIL',
              message: 'no element found for drag target "' + DRAG_TARGET + '"',
              context: null
            });
          } else if (targetMatches.length > 1) {
            __result = JSON.stringify({
              status: 'FAIL',
              message: 'drag target "' + DRAG_TARGET + '" matched ' + targetMatches.length + ' elements, need unique target',
              context: null
            });
          } else {
            __result = dragElement(element, targetMatches[0]);
          }
        }
      } else if (INPUT_VALUE !== null) {
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
