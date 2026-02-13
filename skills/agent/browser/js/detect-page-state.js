// detect-page-state.js - Generic page state detection for snapshot comparison
// Returns: 'dialog', 'overlay', 'dropdown', 'base'

(function() {
  // 1. Check for dialog/modal (most specific)
  if (document.querySelector('[role="dialog"]')) return 'dialog';

  // 2. Check for large overlays covering significant viewport
  // (date pickers, guest selectors, filters, etc.)
  const overlayElements = document.querySelectorAll('[role="complementary"], [role="region"], aside, [class*="overlay"], [class*="modal"], [class*="popup"]');
  for (const el of overlayElements) {
    const rect = el.getBoundingClientRect();
    const computed = window.getComputedStyle(el);

    // Check if it's positioned as overlay and takes up significant space
    if ((computed.position === 'fixed' || computed.position === 'absolute') &&
        rect.width > window.innerWidth * 0.3 &&
        rect.height > window.innerHeight * 0.3 &&
        computed.display !== 'none' &&
        computed.visibility !== 'hidden') {
      return 'overlay';
    }
  }

  // 3. Check for expanded dropdowns/comboboxes
  const expandedCombobox = document.querySelector('[role="combobox"][aria-expanded="true"]');
  if (expandedCombobox) return 'dropdown';

  // 4. Check for visible listbox (autocomplete results)
  const listbox = document.querySelector('[role="listbox"]');
  if (listbox) {
    const rect = listbox.getBoundingClientRect();
    if (rect.top >= 0 && rect.bottom <= window.innerHeight &&
        rect.left >= 0 && rect.right <= window.innerWidth) {
      return 'dropdown';
    }
  }

  // 5. Default state
  return 'base';
})()
