// html2md.js - Pure HTML to Markdown with CSS selectors
// No site-specific logic, just clean HTML structure
// Smart defaults: Show structure + expand priority sections

(function() {
  const fullMode = window.__RECON_FULL__ || false;
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

  // Priority sections that should be fully expanded
  const prioritySections = ['dialog', 'form', 'nav', 'alert'];

  function isPrioritySection(sectionName) {
    if (!sectionName) return false;
    const lower = sectionName.toLowerCase();
    return prioritySections.some(p => lower.includes(p));
  }

  function processNode(node, depth, context = {}) {
    const lines = [];
    const currentSection = context.section || '';
    const isExpanded = fullMode || isPrioritySection(currentSection);

    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (text && isExpanded) {
        lines.push('  '.repeat(depth + 1) + text);
      }
      return lines;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) return lines;

    const tag = node.tagName.toLowerCase();
    if (['head', 'title', 'template'].includes(tag)) return lines;

    // Headings - always show
    if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)) {
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (text) {
        lines.push('');
        lines.push('### ' + text);
      }
      return lines;
    }

    // Buttons - show only in expanded sections
    if (tag === 'button' || getAttr(node, 'role') === 'button') {
      if (isExpanded) {
        const text = node.innerText.trim().replace(/\s+/g, ' ').substring(0, 50);
        const selector = getSelector(node);
        if (selector) {
          lines.push(indent(depth) + `Button ${selector}: ${text || '(no text)'}`);
        } else if (text) {
          lines.push(indent(depth) + `Button: ${text}`);
        }
      }
      return lines;
    }

    // Inputs - show only in expanded sections
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      if (isExpanded) {
        const type = getAttr(node, 'type') || 'text';
        const selector = getSelector(node);
        const value = node.value ? ` = "${node.value.substring(0, 30)}"` : '';
        if (selector) {
          lines.push(indent(depth) + `Input ${selector}${value} (${type})`);
        } else {
          lines.push(indent(depth) + `Input (${type})`);
        }
      }
      return lines;
    }

    // Links - show only in expanded sections
    if (tag === 'a') {
      if (isExpanded) {
        const href = getAttr(node, 'href');
        if (!href || href === '#') return lines;
        const text = node.textContent.trim().replace(/\s+/g, ' ').substring(0, 50) || 'link';
        const shortHref = href.length > 50 ? href.substring(0, 50) + '...' : href;
        lines.push(indent(depth) + `[${text}](${shortHref})`);
      }
      return lines;
    }

    // Semantic sections - always show heading, expand content based on priority
    const semanticTags = ['header', 'main', 'nav', 'aside', 'footer', 'article', 'section', 'form', 'dialog'];
    const role = getAttr(node, 'role');
    if (semanticTags.includes(tag) || role === 'dialog' || role === 'alert') {
      const capTag = role === 'dialog' ? 'Dialog' :
                     role === 'alert' ? 'Alert' :
                     tag.charAt(0).toUpperCase() + tag.slice(1);
      const label = getAttr(node, 'aria-label');
      const heading = label ? `${capTag}: ${label}` : capTag;

      lines.push('');
      lines.push(`## ${heading}`);

      // Create new context with this section name
      const newContext = { section: heading };
      const shouldExpand = fullMode || isPrioritySection(heading);

      if (shouldExpand) {
        // Fully expand priority sections
        Array.from(node.childNodes).forEach(child => {
          lines.push(...processNode(child, 0, newContext));
        });
      } else {
        // For collapsed sections, show structure (h3) only
        Array.from(node.childNodes).forEach(child => {
          if (child.nodeType === Node.ELEMENT_NODE) {
            const childTag = child.tagName.toLowerCase();
            // Show headings and semantic sections
            if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(childTag) ||
                semanticTags.includes(childTag)) {
              lines.push(...processNode(child, 0, newContext));
            }
          }
        });
      }

      return lines;
    }

    // Default: process children
    Array.from(node.childNodes).forEach(child => {
      lines.push(...processNode(child, depth, context));
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

  const modeIndicator = fullMode ? '' : '\n[Smart mode: showing structure + Dialog/Form/Nav details. Use --full for everything]';
  const header = `# ${document.title}\n\n**URL:** ${location.href}${modeIndicator}\n\n---\n`;

  return header + cleaned;
})();
