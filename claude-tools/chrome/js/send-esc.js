// send-esc.js - Send ESC key to close dialogs/modals
// Used internally by: chrome esc

(function() {
  // Find the active/focused element or document
  var target = document.activeElement || document.body;

  // Create and dispatch ESC keydown event
  var evt = new KeyboardEvent('keydown', {
    key: 'Escape',
    code: 'Escape',
    keyCode: 27,
    which: 27,
    bubbles: true,
    cancelable: true
  });

  target.dispatchEvent(evt);

  // Also try on document for handlers that listen there
  document.dispatchEvent(evt);

  // For native <dialog> elements, try to close them
  var openDialogs = document.querySelectorAll('dialog[open]');
  if (openDialogs.length > 0) {
    openDialogs[openDialogs.length - 1].close();
    return 'OK: closed native dialog';
  }

  return 'OK: ESC dispatched to ' + target.tagName;
})();
