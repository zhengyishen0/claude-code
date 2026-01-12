#!/usr/bin/env python3
# format-inspect.py - Pretty print inspect JSON output

import json
import sys

data = json.load(sys.stdin)

print('URL Parameter Discovery')
print('=' * 60)
print()

# Summary
summary = data.get('summary', {})
print(f"Summary:")
print(f"  Parameters from links: {summary.get('paramsFromLinks', 0)}")
print(f"  Parameters from forms: {summary.get('paramsFromForms', 0)}")
print(f"  Total forms found: {summary.get('totalForms', 0)}")
print()

# URL Parameters
params = data.get('urlParams', {})
if params:
    print('Discovered Parameters:')
    print('-' * 60)
    for name, info in params.items():
        source = info.get('source', 'unknown')
        examples = info.get('examples', [])
        ex_str = ', '.join(repr(e) for e in examples[:3])
        print(f"  {name:<20} [{source:>5}] {ex_str}")
    print()

# Forms
forms = data.get('forms', [])
if forms:
    print('Forms:')
    print('-' * 60)
    for form in forms:
        idx = form.get('index', 0)
        action = form.get('action', '')
        method = form.get('method', 'GET')
        fields = form.get('fields', [])
        print(f"  Form #{idx}: {method} {action}")
        for field in fields:
            fname = field.get('name', '')
            ftype = field.get('type', '')
            print(f"    - {fname:<20} ({ftype})")
    print()

# URL Pattern (with meaningful placeholders)
pattern = summary.get('patternUrl', '')
if pattern:
    print('URL Pattern:')
    print('-' * 60)
    print(f"  {pattern}")
    print()
