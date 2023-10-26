#!/usr/bin/env python3

import json
import os
from os.path import join, dirname
import sys

if len(sys.argv) < 2:
    print('Usage: %s <target_name>' % __file__)
    print('  Example: %s python' % __file__)
    exit(1)

target_name = sys.argv[1]

# read script file path
script_dir = dirname(__file__)

src_content = '<write_content>'

with open(join(script_dir, 'template', 'template.md'), 'r') as f:
    src = f.read()

# read json file
with open(join(script_dir, 'template', 'lang.json'), 'r') as f:
    lang = json.load(f)

    # Get all keys
    keys = lang.keys()

    for key in keys:
        # create new file
        v = lang[key]
        dest_path = join(script_dir, '..', 'src', key, target_name + '.md')
        if os.path.exists(dest_path):
            print('The %s is exists, skip it.' % dest_path)
            continue

        # write content
        content = src.replace(src_content, v)
        with open(dest_path, 'w') as f:
            f.write(content)
            print('Create file: %s' % dest_path)
