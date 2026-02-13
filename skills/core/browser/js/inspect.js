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
  // Helper: Generate meaningful placeholder for a parameter name
  // ============================================================================
  function getMeaningfulPlaceholder(paramName) {
    const lower = paramName.toLowerCase();

    // Common search/query params
    if (/^(q|query|search|keyword|term)$/i.test(lower)) return 'query';
    if (/^search[_-]?query$/i.test(lower)) return 'query';

    // Video/media IDs
    if (/^v(id(eo)?)?$/i.test(lower)) return 'video_id';
    if (/^(track|song|audio)[_-]?id$/i.test(lower)) return 'track_id';

    // Generic IDs
    if (/^id$/i.test(lower)) return 'id';
    if (/[_-]id$/i.test(lower)) return paramName; // Keep specific IDs like user_id

    // Pagination
    if (/^(page|p)$/i.test(lower)) return 'page';
    if (/^(offset|start)$/i.test(lower)) return 'offset';
    if (/^(limit|per[_-]?page|page[_-]?size)$/i.test(lower)) return 'limit';

    // Filtering/sorting
    if (/^sort([_-]?by)?$/i.test(lower)) return 'sort';
    if (/^order([_-]?by)?$/i.test(lower)) return 'order';
    if (/^filter$/i.test(lower)) return 'filter';
    if (/^category$/i.test(lower)) return 'category';

    // Authentication/security
    if (/^(token|auth|api[_-]?key)$/i.test(lower)) return 'token';
    if (/^(session|sid)$/i.test(lower)) return 'session_id';

    // Dates
    if (/^(from|start)[_-]?date$/i.test(lower)) return 'start_date';
    if (/^(to|end)[_-]?date$/i.test(lower)) return 'end_date';
    if (/^date$/i.test(lower)) return 'date';

    // Location
    if (/^(loc|location|place)$/i.test(lower)) return 'location';
    if (/^(lat|latitude)$/i.test(lower)) return 'latitude';
    if (/^(lng|lon|longitude)$/i.test(lower)) return 'longitude';

    // Common params
    if (/^lang(uage)?$/i.test(lower)) return 'language';
    if (/^(format|type)$/i.test(lower)) return 'format';
    if (/^callback$/i.test(lower)) return 'callback';

    // Default: use the param name itself
    return paramName;
  }

  // ============================================================================
  // Generate suggested URL patterns
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

    // Build generic template (existing)
    const params = Object.keys(result.urlParams)
      .map(k => `${k}=<value>`)
      .join('&');

    result.summary.suggestedUrl = `${baseUrl}?${params}`;

    // Build pattern template with meaningful placeholders
    const patternParams = Object.keys(result.urlParams)
      .map(k => `${k}=<${getMeaningfulPlaceholder(k)}>`)
      .join('&');

    result.summary.patternUrl = `${baseUrl}?${patternParams}`;
  }

  // ============================================================================
  // Return formatted result
  // ============================================================================
  return JSON.stringify(result, null, 2);
})();
