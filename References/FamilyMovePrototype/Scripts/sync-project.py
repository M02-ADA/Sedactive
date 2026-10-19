"""Synchronize app Swift sources without depending on Xcode's plist formatting.

Keep target settings, resources, signing, tests, and existing object IDs intact.
"""
from pathlib import Path
import copy
import hashlib
import json
import re
import subprocess

root = Path(__file__).resolve().parent.parent
project = root / 'FamilyMove.xcodeproj/project.pbxproj'
original = project.read_bytes()
def read_plist(path):
    return json.loads(subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(path)],
                                    check=True, capture_output=True).stdout)
data = read_plist(project)
before = copy.deepcopy(data)
objects = data['objects']
target = next(v for v in objects.values() if v.get('isa') == 'PBXNativeTarget'
              and v.get('name') == 'FamilyMove')
sources = next(objects[key] for key in target['buildPhases'] if objects[key].get('isa') == 'PBXSourcesBuildPhase')
group = next(v for v in objects.values() if v.get('isa') == 'PBXGroup' and v.get('path') == 'FamilyMove')
def is_swift(ref):
    obj = objects.get(ref, {})
    return obj.get('isa') == 'PBXFileReference' and str(obj.get('path', '')).endswith('.swift')
def ident(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
existing_refs = {objects[key].get('path'): key for key in group['children'] if is_swift(key)}
existing_builds = {objects[key].get('fileRef'): key for key in sources['files']}
other_children = [key for key in group['children'] if not is_swift(key)]
other_builds = [key for key in sources['files'] if not is_swift(objects[key].get('fileRef'))]
refs, builds = [], []
for file in sorted((root / 'FamilyMove').rglob('*.swift')):
    path = str(file.relative_to(root / 'FamilyMove'))
    ref = existing_refs.get(path, ident(path + 'ref'))
    build = existing_builds.get(ref, ident(path + 'build'))
    if ref not in objects:
        objects[ref] = {'isa': 'PBXFileReference', 'lastKnownFileType': 'sourcecode.swift',
                        'path': path, 'sourceTree': '<group>'}
    if build not in objects:
        objects[build] = {'isa': 'PBXBuildFile', 'fileRef': ref}
    refs.append(ref); builds.append(build)
group['children'] = refs + other_children
sources['files'] = builds + other_builds

# OpenStep property lists allow quoted strings and nested dictionaries/arrays.
def atom(value):
    text = str(value)
    return text if re.fullmatch(r'[A-Za-z0-9_./]+', text) else json.dumps(text, ensure_ascii=False)
def encode(value, depth=0):
    pad = '\t' * depth
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (depth+1) + atom(key) + ' = ' + encode(item, depth+1) + ';\n'
                              for key, item in value.items()) + pad + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t' * (depth+1) + encode(item, depth+1) + ',\n' for item in value) + pad + ')'
    return atom(value)

if data != before:
    temporary = project.with_suffix('.pbxproj.tmp')
    try:
        temporary.write_text('// !$*UTF8*$!\n' + encode(data) + '\n')
        assert read_plist(temporary) == data, 'Project serialization changed its values'
        if project.read_bytes() != original:
            raise RuntimeError('Xcode changed the project during sync; retry the build.')
        temporary.replace(project)
    finally:
        temporary.unlink(missing_ok=True)
print(f'Project includes {len(refs)} Swift files; existing project settings preserved.')
