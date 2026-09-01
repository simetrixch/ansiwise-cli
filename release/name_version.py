"""Write the version this release states into the manifest, and nowhere else."""
import io, re, sys

manifest, version = sys.argv[1], sys.argv[2]
text = io.open(manifest, encoding='utf-8').read()
if not re.search(r'^version:\s*\S+', text, re.M):
    raise SystemExit('release: %s declares no version to stamp' % manifest)
io.open(manifest, 'w', encoding='utf-8', newline='\n').write(
    re.sub(r'^version:\s*\S+', 'version: ' + version, text, count=1, flags=re.M))
print('  %s declares %s' % (manifest, version))
