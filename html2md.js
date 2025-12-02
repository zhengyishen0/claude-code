// html2md.js - Page structure reconnaissance for chrome-cli
// Execute: chrome-cli execute "$(cat ~/html2md.js)"
// Purpose: Give LLM the page layout so it can write targeted JS queries

(function() {
  const md = [];
  const getText = el => el?.innerText?.trim().replace(/\s+/g, ' ').substring(0, 100) || '';
  const getLabel = el => getText(el) || el?.getAttribute('aria-label') || el?.getAttribute('title') || '';

  // === PAGE CONTEXT ===
  md.push('# ' + document.title);
  md.push('**URL:** ' + location.href);
  md.push('');

  // === MODAL/DIALOG CHECK ===
  const dialogs = [...document.querySelectorAll('[role="dialog"], [aria-modal="true"], dialog[open]')];
  const visibleDialog = dialogs.find(d => {
    const r = d.getBoundingClientRect();
    const s = getComputedStyle(d);
    return r.width > 100 && r.height > 100 && s.display !== 'none' && s.visibility !== 'hidden';
  });

  if (visibleDialog) {
    const r = visibleDialog.getBoundingClientRect();
    const coversPage = r.width > window.innerWidth * 0.5 || visibleDialog.getAttribute('aria-modal') === 'true';
    md.push('## ⚠️ Dialog Open' + (coversPage ? ' (MODAL - blocks page)' : ' (panel/sidebar)'));
    const dialogTitle = visibleDialog.querySelector('h1, h2, h3, [role="heading"]');
    if (dialogTitle) md.push('**Title:** ' + getText(dialogTitle));
    md.push('**Size:** ' + Math.round(r.width) + 'x' + Math.round(r.height));
    md.push('');
  }

  // === PAGE SECTIONS ===
  md.push('## Page Sections');
  const sections = document.querySelectorAll('header, nav, main, aside, footer, [role="banner"], [role="navigation"], [role="main"], [role="complementary"], [role="contentinfo"], section[aria-label], div[aria-label]');
  const seenSections = new Set();
  sections.forEach(s => {
    const tag = s.tagName.toLowerCase();
    const role = s.getAttribute('role') || '';
    const label = s.getAttribute('aria-label') || '';
    const id = s.id || '';
    const key = tag + role + label + id;
    if (seenSections.has(key)) return;
    seenSections.add(key);

    const r = s.getBoundingClientRect();
    if (r.width < 50 || r.height < 20) return;

    const desc = [tag];
    if (role) desc.push('role="' + role + '"');
    if (label) desc.push('"' + label.substring(0, 30) + '"');
    if (id) desc.push('#' + id);
    md.push('- ' + desc.join(' '));
  });
  md.push('');

  // === HEADINGS (document structure) ===
  md.push('## Headings');
  const headings = document.querySelectorAll('h1, h2, h3');
  let hCount = 0;
  headings.forEach(h => {
    if (hCount >= 15) return;
    const text = getText(h);
    if (!text) return;
    const level = h.tagName[1];
    md.push('  '.repeat(level - 1) + '- ' + h.tagName + ': ' + text);
    hCount++;
  });
  if (headings.length > 15) md.push('  ... +' + (headings.length - 15) + ' more');
  md.push('');

  // === INTERACTIVE ELEMENTS ===
  md.push('## Interactive Elements');

  // Buttons
  const buttons = document.querySelectorAll('button, [role="button"], input[type="submit"], input[type="button"]');
  const btnLabels = [...buttons].map(b => getLabel(b)).filter(l => l && l.length > 1 && l.length < 40);
  const uniqueBtns = [...new Set(btnLabels)].slice(0, 15);
  md.push('**Buttons (' + buttons.length + '):** ' + (uniqueBtns.length ? uniqueBtns.join(' | ') : 'none labeled'));

  // Links
  const links = document.querySelectorAll('a[href]');
  md.push('**Links:** ' + links.length);

  // Inputs
  const inputs = document.querySelectorAll('input:not([type="hidden"]), textarea, select');
  if (inputs.length > 0) {
    const inputInfo = [...inputs].slice(0, 8).map(i => {
      const label = i.getAttribute('aria-label') || i.placeholder || i.name || i.id || i.type;
      const val = i.value ? '="' + i.value.substring(0, 20) + '"' : '';
      return label + val;
    });
    md.push('**Inputs (' + inputs.length + '):** ' + inputInfo.join(' | '));
  }

  // Checkboxes/Toggles
  const toggles = document.querySelectorAll('[aria-pressed], [aria-checked], input[type="checkbox"], input[type="radio"]');
  if (toggles.length > 0) {
    md.push('**Toggles/Checkboxes:** ' + toggles.length);
  }
  md.push('');

  // === LISTS/GRIDS (potential data) ===
  md.push('## Content Patterns');
  const lists = document.querySelectorAll('ul, ol, [role="list"], [role="listbox"]');
  const tables = document.querySelectorAll('table, [role="grid"], [role="table"]');
  const articles = document.querySelectorAll('article, [role="article"]');
  const cards = document.querySelectorAll('[class*="card"], [class*="item"], [class*="result"]');

  if (lists.length) md.push('- Lists: ' + lists.length);
  if (tables.length) md.push('- Tables/Grids: ' + tables.length);
  if (articles.length) md.push('- Articles: ' + articles.length);
  if (cards.length > 3) md.push('- Card-like elements: ' + cards.length);

  // Forms
  const forms = document.querySelectorAll('form');
  if (forms.length) {
    md.push('- Forms: ' + forms.length);
    forms.forEach((f, i) => {
      const action = f.action || f.getAttribute('action') || '';
      const name = f.name || f.id || f.getAttribute('aria-label') || '';
      md.push('  - Form ' + (i + 1) + ': ' + (name || action || 'unnamed'));
    });
  }
  md.push('');

  // === QUICK STATS ===
  md.push('---');
  md.push('**Stats:** ' + buttons.length + ' buttons, ' + inputs.length + ' inputs, ' + links.length + ' links, ' + (visibleDialog ? 'DIALOG OPEN' : 'no dialog'));

  return md.join('\n');
})();
