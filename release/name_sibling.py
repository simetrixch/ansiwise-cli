"""Write the commit a sibling repository is built from into this manifest.

ONE PLACE PER REPOSITORY, however many packages it holds. ansiwise-plugins is a
dozen packages in one tree, and every one of them is named out of the same
checkout — so one commit answers for all of them, and a rewrite that matched a
loose version string instead would reach the neighbouring repository's ref as
well. Measured on 2026-09-01: a `sed` written that way overwrote the ansiwise_core
ref with a plugins tag, and nothing resolved afterwards.
"""
import io, re, sys

manifest, repo, sha = sys.argv[1], sys.argv[2], sys.argv[3]
text = io.open(manifest, encoding='utf-8').read()
pattern = re.compile(
    r'(url:\s*https://github\.com/simetrixch/' + re.escape(repo) + r'\.git\s*\n'
    r'(?:[ \t]*#[^\n]*\n)*'
    r'[ \t]*ref:[ \t]*)(\S+)')
found = pattern.findall(text)
if not found:
    raise SystemExit('release: %s names no dependency on %s' % (manifest, repo))
io.open(manifest, 'w', encoding='utf-8', newline='\n').write(
    pattern.sub(lambda m: m.group(1) + sha, text))
print('  %-18s %d ref(s) -> %s' % (repo, len(found), sha[:12]))
