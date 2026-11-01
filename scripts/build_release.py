#!/usr/bin/env python3
"""Deterministically render the startup wrapper, installer, and PTDL_v2 egg."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
INSTALL_RUNTIME=ROOT/'scripts'/'install_runtime.py'
RUNTIME=ROOT/'scripts'/'runtime.py'
START=ROOT/'scripts'/'start.sh'
INSTALL=ROOT/'scripts'/'install.sh'
EGG=ROOT/'egg-swbf2-classic-2005.json'
PRODUCTION_EXE_SHA256='eeb3bd768ec6ebdf7d0bca39a34a354c4d465b74f244702727ef6b70cbaea04a'

def build_start_content(expected_exe_sha256=PRODUCTION_EXE_SHA256):
    runtime=RUNTIME.read_text().replace(PRODUCTION_EXE_SHA256,expected_exe_sha256)
    return "#!/usr/bin/env bash\nset -Eeuo pipefail\npython3 - \"$0\" <<'PY_RUNTIME'\n"+runtime.rstrip()+"\nPY_RUNTIME\n"

def build_install_content(expected_exe_sha256=PRODUCTION_EXE_SHA256):
    if len(expected_exe_sha256)!=64 or any(c not in '0123456789abcdef' for c in expected_exe_sha256):
        raise ValueError('expected executable SHA-256 must be 64 lowercase hex characters')
    start=build_start_content(expected_exe_sha256)
    installer=INSTALL_RUNTIME.read_text().replace(PRODUCTION_EXE_SHA256,expected_exe_sha256)
    prefix='''#!/usr/bin/env bash
set -Eeuo pipefail
fail() { printf 'ERROR: %s\\n' "$*" >&2; exit 1; }
[[ "${ACCEPT_LUCASARTS_LICENSE:-NO}" == "YES" ]] || fail "ACCEPT_LUCASARTS_LICENSE must be exactly YES; review and accept the license supplied with your copy"
[[ "${NONCOMMERCIAL_USE:-NO}" == "YES" ]] || fail "NONCOMMERCIAL_USE must be exactly YES; this candidate is limited to personal, noncommercial hosting"
SERVER_DIR="${SERVER_DIR:-/mnt/server}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends python3
python3 - "$SERVER_DIR" <<'PY_INSTALL'
'''
    return prefix+f"START_SCRIPT = {start!r}\n"+installer.rstrip()+"\nPY_INSTALL\n"

def variable(name,description,env,default,rules,viewable=True,editable=True):
    return {'name':name,'description':description,'env_variable':env,'default_value':default,'user_viewable':viewable,'user_editable':editable,'rules':rules,'field_type':'text'}

def variables():
    return [
      variable('Accept LucasArts License','Set YES only after reviewing and accepting the license included with your operator-supplied server package.','ACCEPT_LUCASARTS_LICENSE','NO','required|in:YES,NO'),
      variable('Personal Noncommercial Use','Set YES to acknowledge personal, noncommercial hosting within the supplied license terms.','NONCOMMERCIAL_USE','NO','required|in:YES,NO'),
      variable('Server Name','Server name; quotes and line breaks are sanitized.','SERVER_NAME','SWBF2 Dedicated Server','required|string|max:96'),
      variable('Server Password','Optional player join password.','SERVER_PASSWORD','','nullable|string|max:96'),
      variable('Admin Password','Private admin/RCON password; at least 8 characters and not the placeholder.','ADMIN_PASSWORD','CHANGE_ME','required|string|max:96'),
      variable('RCON Port','Optional RCON TCP port; add a matching TCP allocation separately.','RCON_PORT','4658','required|integer|between:1024,65535'),
      variable('Maximum Players','Player limit from 1 to 64.','MAX_PLAYERS','64','required|integer|between:1,64'),
      variable('Ticks Per Second','Simulation updates per second from 10 to 60.','TPS','30','required|integer|between:10,60'),
      variable('AI Per Team','AI bots per team from 0 to 32.','AI_PER_TEAM','0','required|integer|between:0,32'),
      variable('Difficulty','AI skill: 1 easy, 2 normal, 3 elite.','DIFFICULTY','2','required|integer|between:1,3'),
      variable('Bandwidth','Legacy engine bandwidth value in Kbit/s.','BANDWIDTH','6144','required|integer|between:64,65535'),
      variable('Network Region','Legacy region code; discovery is defunct.','REGION','NA','required|in:NA,EUR,JAP'),
      variable('Map Rotation','Space-separated exact stock tokens from SUPPORTED-MAPS.md.','MAP_ROTATION','uta1c_con tan1c_con cor1g_con','required|string|max:1024'),
      variable('Heroes','1 enable; 0 disable.','HEROES','1','required|integer|in:0,1'),
      variable('Team Damage','1 enable; 0 disable.','TEAM_DAMAGE','0','required|integer|in:0,1'),
      variable('Auto Assign Teams','1 enable; 0 disable.','AUTO_ASSIGN','1','required|integer|in:0,1'),
      variable('LAN Mode','1 LAN; 0 internet.','LAN_MODE','0','required|integer|in:0,1'),
      variable('Randomize Rotation','1 randomize; 0 listed order.','RANDOMIZE','0','required|integer|in:0,1')]

def render():
    start=build_start_content(); START.write_text(start); START.chmod(0o755)
    install=build_install_content(); INSTALL.write_text(install); INSTALL.chmod(0o755)
    egg={
      '_comment':'DO NOT EDIT: FILE GENERATED FOR PTERODACTYL/PELICAN IMPORT',
      'meta':{'version':'PTDL_v2','update_url':None},'exported_at':'2026-11-01T00:00:00Z',
      'name':'Star Wars Battlefront II Classic (2005) BYOC','author':'community@example.invalid',
      'description':('Bring-your-own-content candidate for the original LucasArts Windows v1.1 dedicated server under Wine. '
        'Intended for operator-supplied content under documented license constraints; not legal advice. '
        'The exact original installer and BattlefrontII.exe are authenticated by pinned size/SHA-256. Remaining content receives structural, type, size, and path-safety checks and is not authenticated against a full manifest. '
        'Installer mode downloads Debian packages from configured repositories and two pinned open-source extractor source files; proprietary content is never downloaded. '
        'Original GameSpy discovery is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate SWBFSpy-patched Steam client; public-browser discovery, reconnect behavior, and other client builds remain unverified. Unofficial and not affiliated with or endorsed by LucasArts or its successors.'),
      'features':None,'docker_images':{'Wine latest (Ptero-Eggs)':'ghcr.io/ptero-eggs/yolks:wine_latest','Wine latest (Pelican-Eggs)':'ghcr.io/pelican-eggs/yolks:wine_latest'},
      'file_denylist':[],'startup':'bash ./swbf2-runtime/start.sh','config':{'files':'{}','startup':'{}','logs':'{}','stop':'^C'},
      'scripts':{'installation':{'script':install,'container':'ghcr.io/ptero-eggs/installers:debian','entrypoint':'bash'}},'variables':variables()}
    EGG.write_text(json.dumps(egg,indent=4,ensure_ascii=False)+'\n')

def main(): render()
if __name__=='__main__': main()
