// html2md.js - Pure HTML to Markdown with CSS selectors
// No site-specific logic, just clean HTML structure

(function() {
  const clone = document.documentElement.cloneNode(true);

  // Remove non-content elements
  clone.querySelectorAll('style, link[rel="stylesheet"], script, noscript, meta, svg, canvas, img, picture, source, iframe').forEach(el => el.remove());
  clone.querySelectorAll('[aria-hidden="true"], [inert]').forEach(el => el.remove());
  clone.querySelectorAll('[role="presentation"], [role="none"]').forEach(el => el.remove());

  function getAttr(el, attr) {
    return el.getAttribute(attr) || '';
  }

  // Build full CSS selector with all useful attributes (ignore class)
  function getSelector(el) {
    const parts = [];
    const tag = el.tagName.toLowerCase();

    // Add tag name for interactive elements
    if (['button', 'input', 'select', 'textarea', 'a'].includes(tag)) {
      parts.push(tag);
    }

    // Add #id if exists
    const id = el.getAttribute('id');
    if (id && id.length < 50 && !/\s/.test(id)) {
      parts.push(`#${id}`);
    }

    // Add data-* attributes (except style-related)
    for (let i = 0; i < el.attributes.length; i++) {
      const attr = el.attributes[i];
      if (attr.name.startsWith('data-') &&
          !attr.name.includes('style') &&
          !attr.name.includes('class') &&
          attr.value && attr.value.length < 50) {
        parts.push(`[${attr.name}="${attr.value}"]`);
      }
    }

    // Add aria-label
    const aria = el.getAttribute('aria-label');
    if (aria && aria.length < 50) {
      parts.push(`[aria-label="${aria}"]`);
    }

    // Add role (if not redundant with tag)
    const role = el.getAttribute('role');
    if (role && !(tag === 'button' && role === 'button')) {
      parts.push(`[role="${role}"]`);
    }

    // Add name for form elements
    const name = el.getAttribute('name');
    if (name && name.length < 50) {
      parts.push(`[name="${name}"]`);
    }

    return parts.length > 0 ? parts.join('') : null;
  }

  function indent(depth) {
    return '  '.repeat(depth) + '- ';
  }

  function processNode(node, depth) {
    const lines = [];

    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (text) lines.push('  '.repeat(depth + 1) + text);
      return lines;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) return lines;

    const tag = node.tagName.toLowerCase();
    if (['head', 'title', 'template'].includes(tag)) return lines;

    // Headings
    if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)) {
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (text) {
        lines.push('');
        lines.push('### ' + text);
      }
      return lines;
    }

    // Buttons
    if (tag === 'button' || getAttr(node, 'role') === 'button') {
      const text = node.innerText.trim().replace(/\s+/g, ' ').substring(0, 50);
      const selector = getSelector(node);
      if (selector) {
        lines.push(indent(depth) + `Button ${selector}: ${text || '(no text)'}`);
      } else if (text) {
        lines.push(indent(depth) + `Button: ${text}`);
      }
      return lines;
    }

    // Inputs
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      const type = getAttr(node, 'type') || 'text';
      const selector = getSelector(node);
      const value = node.value ? ` = "${node.value.substring(0, 30)}"` : '';
      if (selector) {
        lines.push(indent(depth) + `Input ${selector}${value} (${type})`);
      } else {
        lines.push(indent(depth) + `Input (${type})`);
      }
      return lines;
    }

    // Links
    if (tag === 'a') {
      const href = getAttr(node, 'href');
      if (!href || href === '#') return lines;
      const text = node.textContent.trim().replace(/\s+/g, ' ').substring(0, 50) || 'link';
      const shortHref = href.length > 50 ? href.substring(0, 50) + '...' : href;
      lines.push(indent(depth) + `[${text}](${shortHref})`);
      return lines;
    }

    // Semantic sections
    const semanticTags = ['header', 'main', 'nav', 'aside', 'footer', 'article', 'section', 'form', 'dialog'];
    const role = getAttr(node, 'role');
    if (semanticTags.includes(tag) || role === 'dialog') {
      const capTag = role === 'dialog' ? 'Dialog' : tag.charAt(0).toUpperCase() + tag.slice(1);
      const label = getAttr(node, 'aria-label');
      const heading = label ? `${capTag}: ${label}` : capTag;
      lines.push('');
      lines.push(`## ${heading}`);
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, 0));
      });
      return lines;
    }

    // Default: process children
    Array.from(node.childNodes).forEach(child => {
      lines.push(...processNode(child, depth));
    });

    return lines;
  }

  const body = clone.querySelector('body');
  const output = processNode(body, 0);

  const cleaned = output
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/^\s*\n/gm, '\n')
    .trim();

  const header = `# ${document.title}\n\n**URL:** ${location.href}\n\n---\n`;

  return header + cleaned;
})();
