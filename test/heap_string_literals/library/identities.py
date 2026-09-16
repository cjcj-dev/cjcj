from pathlib import Path
import re,sys,json
ir='\n'.join(p.read_text() for p in Path(sys.argv[1]).rglob('*.ll'))
units=sorted(set(re.findall(r'define[^\n]*@"?(literal_probe\.cjstring\.materialize\.\d+)"?',ir)),key=lambda s:int(s.rsplit('.',1)[1]))
entries=set(re.findall(r'define[^\n]*@"?(_CGP[^" (]+iiHv)',ir))
resets=set(re.findall(r'define[^\n]*@"?(_CGP[^" (]+irHv)',ir))
assert units and len(entries)==len(resets)==1,(units,entries,resets)
ids={'Package':entries.pop(),'Unit':units[-1],'Reset':resets.pop()}
out=Path(sys.argv[2])
out.write_text('\n'.join(f'extern "C" void target{k}() asm("{v}");\nextern "C" void* literalProbe{k}() {{ return reinterpret_cast<void*>(&target{k}); }}' for k,v in ids.items())+'\n')
out.with_suffix('.json').write_text(json.dumps(ids,indent=2)+'\n')
