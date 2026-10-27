"""Publish the standalone proxy script; no device config is packaged."""
from pathlib import Path
import hashlib, shutil

here=Path(__file__).resolve().parent
output=here.parents[1]/'dist/1.0.168/docker-mihomo-proxy-1.0.168-v1.0.0.sh'
output.parent.mkdir(parents=True,exist_ok=True)
shutil.copyfile(here/'docker-mihomo-proxy.sh',output)
output.with_name(output.name+'.sha256').write_text(f'{hashlib.sha256(output.read_bytes()).hexdigest()}  {output.name}\n',encoding='ascii',newline='\n')
print(output.name,output.stat().st_size)
