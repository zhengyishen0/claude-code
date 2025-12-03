// html2md-ultra.js - Ultra-lean HTML to Markdown converter
// Outputs valid, universal Markdown (CommonMark compatible)
// Uses nested lists for hierarchy

(function() {
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

  // Track seen footers to avoid duplicates
  let footerSeen = false;

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

    // Buttons - as fake links with selector for automation
    if (tag === 'button' || getAttr(node, 'role') === 'button') {
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      const label = getAttr(node, 'aria-label') || text;
      if (!label) return lines;
      const testId = getAttr(node, 'data-testid');
      const idAttr = getAttr(node, 'id');
      const selector = testId || idAttr || 'button';
      lines.push(listIndent(depth) + `[${label}](#${selector})`);
      return lines;
    }

    // Inputs - as list items
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      const type = getAttr(node, 'type') || 'text';
      const name = getAttr(node, 'name') || getAttr(node, 'id') || getAttr(node, 'placeholder') || 'input';
      const value = node.value ? `="${node.value.substring(0, 30)}"` : '';
      lines.push(listIndent(depth) + `Input: \`${name}${value}\` (${type})`);
      return lines;
    }

    // List items - keep as proper list items
    if (tag === 'li') {
      const link = node.querySelector('a');
      const text = node.textContent.trim().replace(/\s+/g, ' ');
      if (!text) return lines;
      if (link) {
        const href = getAttr(link, 'href');
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

    // Footer - only first one
    if (tag === 'footer') {
      if (footerSeen) return lines;
      footerSeen = true;
      lines.push('');
      lines.push('## Footer');
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, 0));
      });
      return lines;
    }

    // Major regions - ## level
    const majorRegions = ['header', 'main', 'nav', 'aside'];
    if (majorRegions.includes(tag)) {
      const regionNames = {
        'header': 'Header',
        'nav': 'Navigation',
        'main': 'Main Content',
        'aside': 'Sidebar'
      };
      const label = getAttr(node, 'aria-label');
      const heading = label ? `${regionNames[tag]}: ${label}` : regionNames[tag];
      lines.push('');
      lines.push(`## ${heading}`);
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, 0));
      });
      return lines;
    }

    // Section with aria-label - output as ### heading
    if (tag === 'section') {
      const label = getAttr(node, 'aria-label');
      if (label) {
        lines.push('');
        lines.push(`### ${label}`);
      }
      // Skip unnamed sections - just process children
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, depth));
      });
      return lines;
    }

    // Other semantic tags - form, article, dialog
    const otherSemantic = { 'form': 'Form', 'article': 'Article', 'dialog': 'Dialog' };
    if (otherSemantic[tag]) {
      const label = getAttr(node, 'aria-label');
      if (label) {
        lines.push('');
        lines.push(`## ${otherSemantic[tag]}: ${label}`);
      } else {
        lines.push('');
        lines.push(`## ${otherSemantic[tag]}`);
      }
      Array.from(node.childNodes).forEach(child => {
        lines.push(...processNode(child, 0));
      });
      return lines;
    }

    // Meaningful divs/spans - card containers, etc.
    const testId = getAttr(node, 'data-testid');
    const role = getAttr(node, 'role');
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
