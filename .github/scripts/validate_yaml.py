#!/usr/bin/env python3
"""Validate Configuration/custom.yml parses as YAML, tolerating AME's custom
!tags (!registryValue, !service, !powerShell, ...). CI gate for Null OS."""
import sys
import yaml


class Loader(yaml.SafeLoader):
    pass


# AME uses local tags like !registryValue - map every "!..." to a plain value
# so the document parses without a full AME schema.
Loader.add_multi_constructor('!', lambda loader, suffix, node: None)


def main() -> int:
    path = 'Configuration/custom.yml'
    with open(path, encoding='utf-8') as f:
        doc = yaml.load(f, Loader=Loader)
    if not isinstance(doc, dict):
        print('FAIL: %s did not parse to a mapping' % path)
        return 1
    actions = doc.get('actions')
    if not isinstance(actions, list) or not actions:
        print('FAIL: %s has no non-empty "actions" list' % path)
        return 1
    print('custom.yml OK: %d actions' % len(actions))
    return 0


if __name__ == '__main__':
    sys.exit(main())
