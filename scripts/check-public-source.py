#!/usr/bin/env python3
"""Check a public product snapshot, without printing sensitive matches."""
from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parent.parent
skip={'.git','.build','.swiftpm','build','outputs'}
patterns={
 'private-key':r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
 'github-token':r'\b(?:gh[pousr]_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{40,})\b',
 'gitlab-token':r'\bglpat-[A-Za-z0-9_-]{15,}\b',
 'aws-key':r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
 'local-user-path':r'/(?:[U]sers|[h]ome)/[^/\s]+/',
 'internal-tracker':r'gitlab[.]com/[s]hiroi-work|figma[.]com/design/',
}
hits=[];count=0
for p in ROOT.rglob('*'):
 relative=p.relative_to(ROOT)
 if any(part in skip for part in relative.parts):continue
 if p.is_symlink():hits.append((str(relative),'symlink'));continue
 if not p.is_file():continue
 if p.name in ['pet.json','care.json','desktop.json']or p.suffix.lower()in ['.p12','.p8','.key']or p.name.startswith('.env'):
  hits.append((str(relative),'private-data-path'))
 raw=p.read_bytes()
 if b'\x00'in raw:continue
 s=raw.decode('utf-8',errors='replace');count+=1
 for label,pattern in patterns.items():
  if re.search(pattern,s):hits.append((str(relative),label))
if hits:
 print(json.dumps({'rejectedPathsAndTypes':hits},ensure_ascii=False));raise SystemExit(1)
for name in ['README.md','LICENSE','SECURITY.md','DISCLAIMER.zh-TW.md','THIRD_PARTY_NOTICES.md','Package.swift']:
 if not(ROOT/name).is_file():raise SystemExit('Required public file missing: '+name)
print('PASS public-source hygiene:',count,'text files; no listed private-data/secret/path patterns (not a full security audit)')
