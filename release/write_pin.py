"""Write the released tag into a tree that names an engine.

TWO SHAPES, ONE FACT. The platform tree names it as `version: "<tag>"` under its
ansiwise entry; the catalogue names it as `- ansiwise=<tag>` in the row that
installs the pinned tools. Both are matched on the SHAPE OF A TAG rather than on
the neighbouring words, so a file that renames its keys still pins, and a file
that carries no pin at all says so instead of being silently left behind.
"""
import io, re, sys

path, shape, tag = sys.argv[1], sys.argv[2], sys.argv[3]
TAG = r'[0-9]+\.[0-9]+\.[0-9]+-[a-z]+-[0-9]{14}'
pattern = {
    'version': re.compile(r'(version:\s*")' + TAG + r'(")'),
    'tool': re.compile(r'(-\s*ansiwise=)' + TAG),
}[shape]
text = io.open(path, encoding='utf-8').read()
if not pattern.search(text):
    raise SystemExit('release: %s carries no %s pin to write — nothing was changed there' % (path, shape))
io.open(path, 'w', encoding='utf-8', newline='\n').write(
    pattern.sub(lambda m: ''.join(m.groups()[:1]) + tag + (m.group(2) if pattern.groups > 1 else ''), text))
print('  %s pinned to %s' % (path, tag))
