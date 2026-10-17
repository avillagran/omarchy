#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
python3 - "$ROOT" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='tooltip-installer-test.') as temp:
    base = pathlib.Path(temp)
    def write(path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        path.chmod(0o755)
    source = base/'source'
    (source/'shell').mkdir(parents=True)
    (source/'default').mkdir()
    fake = base/'bin'
    write(fake/'omarchy-pkg-add', '#!/bin/bash\nexit 0\n')
    write(fake/'pacman', '''#!/bin/bash
if [[ $1 == -Q ]]; then echo 'quickshell 0.3.1-1'; exit 0; fi
exit 99
''')
    write(fake/'sudo', '''#!/bin/bash
printf '%s\\n' "$*" >> "$TEST_LOG"
[[ $1 == pacman && $2 == -U ]] || exit 99
if [[ $* == *new.pkg.tar* && $FAULT == package* ]]; then exit 42; fi
if [[ $* == *previous.pkg.tar* && $FAULT == package-rollback ]]; then exit 43; fi
''')
    write(fake/'makepkg', '''#!/bin/bash
if [[ ${1:-} == --packagelist ]]; then printf '%s/new.pkg.tar\\n' "$PWD"; else touch new.pkg.tar; fi
''')
    write(source/'bin/omarchy-dev-link', '''#!/bin/bash
printf 'link %s\\n' "$1" >> "$TEST_LOG"
if [[ $1 == */trial/omarchy && $FAULT == link ]]; then exit 44; fi
''')
    write(source/'default/tooltips/check-runtime', '#!/bin/bash\nexit 0\n')
    write(source/'default/tooltips/build-runtime', '#!/bin/bash\nmkdir -p "$TOOLTIP_BUILD_DIR/build/src"\ntouch "$TOOLTIP_BUILD_DIR/build/src/quickshell"\n')
    write(source/'default/tooltips/prepare-trial.py', '''import argparse
from pathlib import Path
p=argparse.ArgumentParser()
for name in ['source','installed','stock-package','output','runtime']: p.add_argument('--'+name)
a=p.parse_args(); t=Path(a.output)
for d in ['backup','package','omarchy/test/shell.d']: (t/d).mkdir(parents=True,exist_ok=True)
(t/'omarchy/test/shell.d/tooltips-test.sh').write_text('exit 0\\n')
''')
    for fault in ['none','package','link','package-rollback']:
        work=base/fault
        stock=work/'cache/omarchy/tooltips/stock/quickshell-0.3.1-1-any.pkg.tar.xz'
        stock.parent.mkdir(parents=True)
        stock.touch()
        env={**os.environ, 'PATH':str(fake)+':'+os.environ['PATH'], 'HOME':str(work),
             'XDG_STATE_HOME':str(work/'state'), 'XDG_DATA_HOME':str(work/'data'),
             'XDG_CACHE_HOME':str(work/'cache'), 'XDG_CONFIG_HOME':str(work/'config'),
             'OMARCHY_PATH':str(source), 'FAULT':fault, 'TEST_LOG':str(work/'log')}
        run=subprocess.run(['bash',str(root/'default/tooltips/install')],env=env,capture_output=True,text=True)
        state=work/'state/omarchy/tooltip-trial.json'
        pending=state.with_name(state.name+'.pending')
        log=(work/'log').read_text()
        assert (run.returncode==0)==(fault=='none'), (fault,run.stdout,run.stderr)
        assert state.exists()==(fault=='none'), (fault,log)
        assert pending.exists()==(fault=='package-rollback'), (fault,log)
        if fault=='none':
            assert pathlib.Path(json.loads(state.read_text())['previousPackage']).exists()
        else:
            assert 'previous.pkg.tar' in log, (fault,log)
            if fault=='link': assert f'link {source}' in log, log
            if fault.startswith('package'): assert 'link ' not in log, log
        print('ok - tooltip installer transaction: '+fault)
PY
