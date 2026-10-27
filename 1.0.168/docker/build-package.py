"""Build the offline deploy bundle from reviewed assets and the pinned vendor tgz."""
from pathlib import Path
import argparse, hashlib, io, tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SHA = '030359d3cc1aac326409c6c37cc2ef5c1b9e5f1ddf97d722f5b8ab2cfa711d13'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine-archive', type=Path, required=True)
args = parser.parse_args()
if hashlib.sha256(args.engine_archive.read_bytes()).hexdigest() != SHA:
    raise SystemExit('Vendor Docker archive SHA-256 mismatch')
payload = sorted(p for p in (HERE/'payload').iterdir() if p.is_file() and p.name != 'SHA256SUMS')
(HERE/'payload/SHA256SUMS').write_text(''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in payload), encoding='utf-8', newline='\n')
output = ROOT/'dist/1.0.168/router-docker-1.0.168-v1.1.0.tar.gz'
output.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(output, 'w:gz') as tar:
    files = [HERE/'install-router-docker.sh', HERE/'README.md', HERE/'SOURCES.md', *payload, HERE/'payload/SHA256SUMS']
    for path in files:
        data = path.read_bytes()
        item = tarfile.TarInfo('router-docker-1.0.168/'+path.relative_to(HERE).as_posix())
        item.size = len(data)
        item.mode = 0o755 if path.suffix == '.sh' else 0o644
        tar.addfile(item, io.BytesIO(data))
    tar.add(args.engine_archive, arcname='router-docker-1.0.168/docker-19.03.15-ce.tgz', recursive=False)
digest = hashlib.sha256(output.read_bytes()).hexdigest()
output.with_name(output.name+'.sha256').write_text(f'{digest}  {output.name}\n', encoding='ascii')
print(output.name, output.stat().st_size, digest)
