// page-status.js - Get page loading status
// Used internally by: chrome wait

(function() {
  const status = {
    readyState: document.readyState,
    images: { total: document.images.length, loaded: Array.from(document.images).filter(i => i.complete).length },
    scripts: { total: document.scripts.length },
    iframes: document.querySelectorAll('iframe').length,
    pendingXHR: window.performance.getEntriesByType('resource').filter(r => !r.responseEnd).length
  };
  return '## Loading Status\n' +
    '- Document: ' + status.readyState + '\n' +
    '- Images: ' + status.images.loaded + '/' + status.images.total + ' loaded\n' +
    '- Scripts: ' + status.scripts.total + '\n' +
    '- Iframes: ' + status.iframes + '\n' +
    '- Pending resources: ' + status.pendingXHR + '\n\n';
})();
