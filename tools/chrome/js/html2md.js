// html2md-ultra.js - Ultra-lean HTML to Markdown converter
// Outputs valid, universal Markdown (CommonMark compatible)
// Uses nested lists for hierarchy

(function() {
  // Build map of button data from live DOM (clone loses innerText spacing and class)
  // Replace newlines with literal \n so it's visible and usable in click command
  const buttonData = new Map();
  document.querySelectorAll('button, [role="button"]').forEach((btn) => {
    // Find a unique-looking class (long name or has numbers/hyphens)
    const classes = (btn.className || '').split(/\s+/).filter(c => c.length > 10 || /[-_\d]/.test(c));
    buttonData.set(btn.textContent, {
      text: btn.innerText.trim().replace(/\s*\n\s*/g, '\\n').replace(/\s+/g, ' '),
      class: classes[0] || ''
    });
  });

  const clone = document.documentElement.cloneNode(true);

  // Remove non-content elements
  clone.querySelectorAll('style, link[rel="stylesheet"], script, noscript, meta, svg, canvas, img, picture, source, iframe').forEach(el => el.remove());
  clone.querySelectorAll('[aria-hidden="true"]').forEach(el => el.remove());
  clone.querySelectorAll('[inert]').forEach(el => el.remove());

  // Remove common noise elements (skip links, empty banners/overlays, Facebook SDK)
  clone.querySelectorAll('[id*="skip-link"], [id*="skip-links"], #fb-root').forEach(el => el.remove());
  clone.querySelectorAll('[id*="banner"]:empty, [id*="overlay"]:empty, [id*="modal"]:empty').forEach(el => el.remove());

  // Remove presentation-only roles
  clone.querySelectorAll('[role="presentation"], [role="none"]').forEach(el => el.remove());

  // Remove empty img placeholders
  clone.querySelectorAll('[role="img"]').forEach(el => {
    if (!el.textContent.trim()) el.remove();
  });

  // Remove tables inside map/application containers (often verbose keyboard shortcuts)
  clone.querySelectorAll('[role="application"] table, [data-testid*="map"] table, [data-testid*="Map"] table').forEach(el => el.remove());

  // Remove style and class attributes
  clone.querySelectorAll('*').forEach(el => {
    el.removeAttribute('style');
    el.removeAttribute('class');
  });

  function getAttr(el, attr) {
    return el.getAttribute(attr) || '';
  }

  function listIndent(depth) {
    // Each nesting level is 2 spaces
    return '  '.repeat(depth) + '- ';
  }

  function textIndent(depth) {
    // Text under a list item needs extra indent
    return '  '.repeat(depth + 1);
  }

  function processNode(node, depth) {
    const lines = [];

    if (node.nodeType === Node.TEXT_NODE) {
      let text = node.textContent.trim().replace(/\s+/g, ' ');
      // Skip noise text
      if (text && text !== ',' && text !== '·' && text !== '|') {
        lines.push(textIndent(depth) + text);
      }
      return lines;
    }

    if (node.nodeType !== Node.ELEMENT_NODE) return lines;

    const tag = node.tagName.toLowerCase();

    // Skip these entirely
    if (['head', 'title', 'template'].includes(tag)) return lines;

    // Headings - all content headings become ### (subsections under ## regions)
    // This flattens h1-h6 to ### to maintain clean hierarchy
    if (['h1', 'h2', 'h3', 'h4', 'h5', 'h6'].includes(tag)) {
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (text) {
        // All content headings become ### (under ## major regions)
        lines.push('');
        lines.push('### ' + text);
      }
      return lines;
    }

    // Links - as list items
    if (tag === 'a') {
      const text = node.textContent.trim().replace(/\s+/g, ' ') || getAttr(node, 'aria-label') || 'link';
      const href = getAttr(node, 'href');
      if (!href || href === '#') return lines;
      // Shorten href but keep important parts (like room IDs)
      let shortHref = href;
      if (href.length > 50) {
        const qIndex = href.indexOf('?');
        shortHref = qIndex > 0 ? href.substring(0, qIndex) : href.substring(0, 50) + '...';
      }
      lines.push(listIndent(depth) + `[${text}](${shortHref})`);
      return lines;
    }

    // Buttons - format: [text@aria](#testid) for clear click strategy selection
    // text = visible text, aria = aria-label, selector = data-testid || id || class || 'button'
    if (tag === 'button' || getAttr(node, 'role') === 'button') {
      // Use pre-built map from live DOM (clone loses innerText spacing and class)
      const rawText = node.textContent;
      const data = buttonData.get(rawText) || { text: rawText.trim().replace(/\s+/g, ' '), class: '' };
      const text = data.text;
      const aria = getAttr(node, 'aria-label');
      const testId = getAttr(node, 'data-testid');
      const idAttr = getAttr(node, 'id');
      // Priority: testid > id > class > 'button'
      const selector = testId || idAttr || data.class || 'button';

      // Build label: [text@aria] or [text] or [@aria]
      let label = '';
      if (text && aria && text !== aria) {
        label = `${text}@${aria}`;
      } else if (text) {
        label = text;
      } else if (aria) {
        label = `@${aria}`;
      }
      if (!label) return lines;

      lines.push(listIndent(depth) + `[${label}](#${selector})`);
      return lines;
    }

    // Inputs - as list items with aria-label prominently shown
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      const type = getAttr(node, 'type') || 'text';
      const aria = getAttr(node, 'aria-label');
      const name = getAttr(node, 'name') || getAttr(node, 'id') || getAttr(node, 'placeholder') || 'input';
      const value = node.value ? `="${node.value.substring(0, 30)}"` : '';
      // Show aria-label first if available (most useful for automation)
      const label = aria ? `aria="${aria}"` : `\`${name}\``;
      lines.push(listIndent(depth) + `Input: ${label}${value} (${type})`);
      return lines;
    }

    // List items - check if simple or complex
    if (tag === 'li') {
      const links = node.querySelectorAll('a');
      const buttons = node.querySelectorAll('button, [role="button"]');
      // If multiple interactive elements, recurse into children
      if (links.length > 1 || buttons.length > 0) {
        Array.from(node.childNodes).forEach(child => {
          lines.push(...processNode(child, depth));
        });
        return lines;
      }
      // Simple list item with 0-1 links
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (!text) return lines;
      if (links.length === 1) {
        const href = getAttr(links[0], 'href');
        const shortHref = href.length > 40 ? href.substring(0, 40) + '...' : href;
        lines.push(listIndent(depth) + `[${text}](${shortHref})`);
      } else {
        lines.push(listIndent(depth) + text);
      }
      return lines;
    }

    // Lists - process children
    if (tag === 'ul' || tag === 'ol') {
      Array.from(node.children).forEach(child => {
        lines.push(...processNode(child, depth));
      });
      return lines;
    }

    // Tables - simplified marker
    if (tag === 'table') {
      lines.push(listIndent(depth) + '(table)');
      return lines;
    }

    // Semantic sectioning elements - unified handling
    const semanticTags = ['header', 'main', 'nav', 'aside', 'footer', 'article', 'section', 'form', 'dialog'];
    const role = getAttr(node, 'role');
    // Also treat role="dialog" as a dialog section (common in React/SPAs)
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

    // Meaningful divs/spans - card containers, etc.
    const testId = getAttr(node, 'data-testid');
    const id = getAttr(node, 'id');

    // Skip empty elements with subtitle/label patterns
    if (testId && /subtitle|label/i.test(testId) && !node.textContent.trim()) {
      return lines;
    }

    // Skip CSS injection and utility containers (pass through to children)
    if (testId && /injector|underline|portal|tooltip/i.test(testId)) {
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, depth));
      });
      return lines;
    }

    // Card-like containers - treat as meaningful group
    if (testId && /card|item|result|listing/i.test(testId) && !/subtitle|title|name/i.test(testId)) {
      lines.push('');
      lines.push(listIndent(depth) + '**Card**');
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, depth + 1));
      });
      return lines;
    }

    // Other meaningful blocks - as nested list items
    if (testId || (role && role !== 'group') || (id && id.length < 30)) {
      const marker = testId || role || id;
      // Skip generic wrapper patterns (pass through to children)
      const wrapperPatterns = /^(content-scroller|scroller|wrapper|container|group|root|inner|outer)$/i;
      if (wrapperPatterns.test(marker)) {
        Array.from(node.childNodes).forEach(child => {
          lines.push(...processNode(child, depth));
        });
        return lines;
      }
      lines.push(listIndent(depth) + `**${marker}**`);
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, depth + 1));
      });
      return lines;
    }

    // Default: process children, skip wrapper
    Array.from(node.childNodes).forEach(child => {
      lines.push(...processNode(child, depth));
    });

    return lines;
  }

  const body = clone.querySelector('body');
  const output = processNode(body, 0);

  // Clean up
  const cleaned = output
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/^\s*\n/gm, '\n')
    .trim();

  const header = `# ${document.title}\n\n**URL:** ${location.href}\n\n---\n`;

  return header + cleaned;
})();
