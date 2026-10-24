#!/usr/bin/env python3
"""Create a distinct, launchable QA app that always uses disposable pet data.

The launcher hardcodes its isolated data directory even if opened from Finder or
an accessibility tool. No production code, defaults or real saves are modified.
"""
import json
import argparse
import hashlib
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parent.parent
source = ROOT / 'build/Tomatogotchi.app'
assert source.is_dir(), 'Build the development app first.'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--species', choices=['cat','dinosaur','dog','daruma','goblin'], default='cat')
parser.add_argument('--stage', choices=['egg','hatchling','adult'], default='hatchling')
parser.add_argument('--output-root', type=Path)
parser.add_argument('--work-minutes', type=int, default=1)
parser.add_argument('--rest-minutes', type=int, default=1)
mode = parser.add_mutually_exclusive_group()
mode.add_argument('--walking', action='store_true')
mode.add_argument('--fresh', action='store_true')
args = parser.parse_args()
assert 1 <= args.work_minutes <= 1440 and 1 <= args.rest_minutes <= 1440
if args.output_root:
    args.output_root.mkdir(parents=True, exist_ok=True)
qa = Path(tempfile.mkdtemp(prefix=args.species+'-qa-', dir=args.output_root or ROOT / '.build'))
label = {'cat':'小貓','dinosaur':'小恐龍','dog':'小狗','daruma':'達摩','goblin':'哥布林'}[args.species]
if args.fresh: label = '新蛋'
app = qa / ('Tomatogotchi QA '+label+'.app')
data = qa / 'data'
data.mkdir()
shutil.copytree(source, app)
info_file = app / 'Contents/Info.plist'
info = plistlib.loads(info_file.read_bytes())
info['CFBundleIdentifier'] = 'work.shiroi.tomatogotchi.qa.device.' + uuid.uuid4().hex[:8]
info['CFBundleName'] = 'Tomatogotchi QA '+label
info['CFBundleDisplayName'] = 'Tomatogotchi QA '+label
info_file.write_bytes(plistlib.dumps(info))
binary = app / 'Contents/MacOS/Tomatogotchi'
actual = binary.with_name('Tomatogotchi-real')
binary.rename(actual)
# exec preserves the launcher's PID and guarantees the QA data path on every
# launch, including reopens by native UI tools. No environment-dependent fallback.
binary.write_text('#!/bin/sh\nexport TOMATOGOTCHI_DATA_DIR=' + shlex.quote(str(data)) + '\nunset TOMATOGOTCHI_NOTIFICATION_PROBE\nexec ' + shlex.quote(str(actual)) + ' "$@"\n')
binary.chmod(0o755)
pet_id = str(uuid.uuid4())
rests = {'egg':0,'hatchling':3,'adult':12}[args.stage]
pet = {'saveVersion':4,'id':pet_id,'name':'測試'+label,'lifeStage':args.stage,
       'createdAt':1000,'updatedAt':1000,
       'growth':{'species':args.species,'completedRests':['qa-'+str(n)for n in range(rests)],
                 'neglectedSeconds':0,'health':5,'mood':5,'needs':{}}}
care = {'version':2,'phase':'paused' if args.walking else 'idle',
        'remainingWork':0 if args.walking else args.work_minutes*60,
        'workDuration':args.work_minutes*60,'breakDuration':args.rest_minutes*60,'demandElapsed':0}
if not args.fresh:
    (data/'pet.json').write_text(json.dumps(pet))
    care['petID']=pet_id
if args.walking:
    care.update({'demand':'walk','demandID':str(uuid.uuid4())})
(data/'care.json').write_text(json.dumps(care))
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
report = {'qaRoot': str(qa), 'app': str(app), 'directory': str(data),
          'bundleIdentifier': info['CFBundleIdentifier'], 'sourceVersion': info['CFBundleShortVersionString'],
          'sourceBuild': info['CFBundleVersion'],
          'sourceExecutableSHA256': hashlib.sha256(actual.read_bytes()).hexdigest(),
          'nativeInteractionVerified': False, 'species': 'unknown' if args.fresh else args.species,
          'stage': 'new-adoption' if args.fresh else args.stage, 'walkingTaskReady': args.walking}
(qa / 'manifest.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
