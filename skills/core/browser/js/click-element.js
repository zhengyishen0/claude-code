// click-element.js - Click element by CSS selector
// Used internally by: chrome click SELECTOR

(function() {
  var el = document.querySelector(SELECTOR);
  if (!el) return 'FAIL: element not found';

  // Only scroll if element is not in viewport
  var rect = el.getBoundingClientRect();
  var isVisible = (
    rect.top >= 0 &&
    rect.left >= 0 &&
    rect.bottom <= (window.innerHeight || document.documentElement.clientHeight) &&
    rect.right <= (window.innerWidth || document.documentElement.clientWidth)
  );

  if (!isVisible) {
    el.scrollIntoView({block: 'center', behavior: 'instant'});
  }

  el.click();
  var tag = el.tagName.toLowerCase();
  var text = (el.innerText || '').trim().substring(0, 30);
  return 'OK: clicked ' + tag + (text ? ' "' + text + '"' : '');
})();
