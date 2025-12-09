// inspect.js - Universal URL parameter and form discovery
// Combines Tier 1 (link extraction) and Tier 2 (form inspection)
(function() {
  const result = {
    urlParams: {},
    forms: [],
    summary: {
      paramsFromLinks: 0,
      paramsFromForms: 0,
      totalForms: 0,
      suggestedUrl: ''
    }
  };

  // ============================================================================
  // TIER 1: Extract parameters from existing links
  // ============================================================================
  const linkParams = new Map();

  document.querySelectorAll('a[href]').forEach(link => {
    try {
      const url = new URL(link.href);

      // Only process if URL has query parameters
      if (url.search) {
        url.searchParams.forEach((value, key) => {
          if (!linkParams.has(key)) {
            linkParams.set(key, {
              examples: [],
              source: 'links',
              count: 0
            });
          }

          const param = linkParams.get(key);
          param.count++;

          // Keep up to 3 unique example values
          if (param.examples.length < 3 && !param.examples.includes(value)) {
            param.examples.push(value);
          }
        });
      }
    } catch(e) {
      // Ignore invalid URLs
    }
  });

  // Add link params to result
  linkParams.forEach((value, key) => {
    result.urlParams[key] = value;
    result.summary.paramsFromLinks++;
  });

  // ============================================================================
  // TIER 2: Inspect forms
  // ============================================================================
  document.querySelectorAll('form').forEach((form, idx) => {
    const formInfo = {
      index: idx,
      action: form.action || window.location.href,
      method: (form.method || 'GET').toUpperCase(),
      fields: []
    };

    Array.from(form.elements).forEach(element => {
      if (element.name) {
        const field = {
          name: element.name,
          type: element.type,
          value: element.value || '',
          placeholder: element.placeholder || '',
          required: element.required
        };

        formInfo.fields.push(field);

        // Add to urlParams if not already discovered from links
        if (!result.urlParams[element.name]) {
          result.urlParams[element.name] = {
            examples: element.value ? [element.value] : [],
            source: 'form',
            type: element.type,
            formIndex: idx
          };
          result.summary.paramsFromForms++;
        }
      }
    });

    if (formInfo.fields.length > 0) {
      result.forms.push(formInfo);
    }
  });

  result.summary.totalForms = result.forms.length;

  // ============================================================================
  // Generate suggested URL pattern
  // ============================================================================
  if (Object.keys(result.urlParams).length > 0) {
    // Use first form action if available, otherwise current URL
    let baseUrl = result.forms.length > 0 ?
      result.forms[0].action :
      window.location.origin + window.location.pathname;

    // Remove existing query params from base
    try {
      const url = new URL(baseUrl);
      url.search = '';
      baseUrl = url.href;
    } catch(e) {}

    // Build param template
    const params = Object.keys(result.urlParams)
      .map(k => `${k}=<value>`)
      .join('&');

    result.summary.suggestedUrl = `${baseUrl}?${params}`;
  }

  // ============================================================================
  // Return formatted result
  // ============================================================================
  return JSON.stringify(result, null, 2);
})();
