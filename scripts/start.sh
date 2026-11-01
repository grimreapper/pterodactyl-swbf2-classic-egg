#!/usr/bin/env bash
set -Eeuo pipefail
python3 - "$0" <<'PY_RUNTIME'
#!/usr/bin/env python3
"""Pinned-descriptor startup and generated configuration writer."""
import hashlib
import os
from pathlib import Path
import secrets
import stat
import sys

ORIGINAL_EXE_SHA256="eeb3bd768ec6ebdf7d0bca39a34a354c4d465b74f244702727ef6b70cbaea04a"
NOTICE=("This is an unofficial community-operated server. It is not affiliated with or endorsed by LucasArts or its successors.\n"
        "The original GameSpy discovery service is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate SWBFSpy-patched Steam client; public-browser discovery and other client builds remain unverified.\n")
SUPPORTED_MAPS=set("""cor1c_con cor1c_ctf cor1g_con cor1g_ctf dag1c_con dag1c_ctf dag1g_con dag1g_ctf dea1c_1flag dea1c_con dea1g_1flag dea1g_con end1g_1flag end1g_con end1g_hunt fel1c_1flag fel1c_con fel1g_1flag fel1g_con geo1c_con geo1c_ctf geo1c_hunt hot1g_1flag hot1g_con hot1g_hunt kam1c_1flag kam1c_con kam1g_1flag kam1g_con kas2c_con kas2c_ctf kas2c_hunt kas2g_con kas2g_ctf mus1c_con mus1c_ctf mus1g_con mus1g_ctf myg1c_con myg1c_ctf myg1g_con myg1g_ctf nab2c_con nab2c_ctf nab2c_hunt nab2g_con nab2g_ctf pol1c_con pol1c_ctf pol1g_con pol1g_ctf spa1g_1flag spa1g_ass spa3c_1flag spa3c_ass spa6c_1flag spa6c_ass spa7c_1flag spa7c_ass spa8g_1flag spa8g_ass spa9g_1flag spa9g_ass tan1c_1flag tan1c_con tan1g_1flag tan1g_con tat2c_con tat2c_ctf tat2g_con tat2g_ctf tat2g_eli tat2g_hunt tat3c_1flag tat3c_con tat3g_1flag tat3g_con uta1c_1flag uta1c_con uta1g_1flag uta1g_con yav1c_1flag yav1c_con yav1g_1flag yav1g_con""".split())

class ValidationError(Exception): pass

def identity(st): return (st.st_dev,st.st_ino,stat.S_IFMT(st.st_mode))
def open_real_directory(path):
    path=Path(path); absolute=path if path.is_absolute() else Path.cwd()/path; fd=os.open('/',os.O_RDONLY|os.O_DIRECTORY)
    try:
        for part in absolute.parts[1:]:
            if part in ('','.'): continue
            if part=='..': raise ValidationError('runtime path contains parent component')
            try: new=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)
            except OSError as exc: raise ValidationError('runtime base must have only real, unchanged directory components') from exc
            os.close(fd); fd=new
        return fd
    except Exception: os.close(fd); raise

def read_regular(fd,name):
    try: f=os.open(name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=fd)
    except OSError as exc: raise ValidationError(f'{name} is missing or not a regular file; reinstall') from exc
    try:
        st=os.fstat(f)
        if not stat.S_ISREG(st.st_mode) or st.st_nlink>1: raise ValidationError(f'{name} is not an independent regular file; reinstall')
        data=b''
        while True:
            chunk=os.read(f,1024*1024)
            if not chunk: break
            data+=chunk
        if identity(os.fstat(f))!=identity(st) or os.fstat(f).st_size!=len(data): raise ValidationError(f'{name} changed while being read')
        return data
    finally: os.close(f)

def hash_regular(fd,name): return hashlib.sha256(read_regular(fd,name)).hexdigest()

def atomic_write(directory_fd,name,data,mode):
    temporary=f'.{name}.tmp-{secrets.token_hex(8)}'
    out=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode,dir_fd=directory_fd)
    try:
        view=memoryview(data)
        while view: view=view[os.write(out,view):]
        os.fsync(out)
    except Exception:
        try: os.unlink(temporary,dir_fd=directory_fd)
        except OSError: pass
        raise
    finally: os.close(out)
    os.replace(temporary,name,src_dir_fd=directory_fd,dst_dir_fd=directory_fd)
    os.fsync(directory_fd)

def text(value): return value.replace('\r',' ').replace('\n',' ').replace('"',"'")[:96]
def integer(env,name,default,minimum,maximum):
    value=env.get(name,default)
    if not value.isascii() or not value.isdigit() or len(value)>20 or not minimum<=int(value)<=maximum: raise ValidationError(f'{name} must be between {minimum} and {maximum}')
    return value
def boolean(env,name,default):
    value=env.get(name,default)
    if value not in ('0','1'): raise ValidationError(f'{name} must be 0 or 1')
    return value

def configuration(env):
    server_name=text(env.get('SERVER_NAME','SWBF2 Dedicated Server')); server_password=text(env.get('SERVER_PASSWORD','')); admin=text(env.get('ADMIN_PASSWORD','CHANGE_ME'))
    if not server_name: raise ValidationError('SERVER_NAME must not be empty')
    if admin.lower() in ('','change-me','change_me','changeme') or len(admin)<8: raise ValidationError('ADMIN_PASSWORD must be changed and contain at least 8 characters')
    port=integer(env,'SERVER_PORT','3658',1024,65535); rcon=integer(env,'RCON_PORT','4658',1024,65535); players=integer(env,'MAX_PLAYERS','64',1,64)
    tps=integer(env,'TPS','30',10,60); ai=integer(env,'AI_PER_TEAM','0',0,32); difficulty=integer(env,'DIFFICULTY','2',1,3); bandwidth=integer(env,'BANDWIDTH','6144',64,65535)
    region=env.get('REGION','NA')
    if region not in ('NA','EUR','JAP'): raise ValidationError('REGION must be NA, EUR, or JAP')
    heroes=boolean(env,'HEROES','1'); damage=boolean(env,'TEAM_DAMAGE','0'); assign=boolean(env,'AUTO_ASSIGN','1'); lan=boolean(env,'LAN_MODE','0'); randomize=boolean(env,'RANDOMIZE','0')
    maps=env.get('MAP_ROTATION','uta1c_con tan1c_con cor1g_con').replace('\r',' ').replace('\n',' ').split()
    if not maps: raise ValidationError('MAP_ROTATION must contain at least one supported stock map token')
    for item in maps:
        if item not in SUPPORTED_MAPS: raise ValidationError(f'unsupported stock map token: {item}')
    settings=f'''/gamename "{server_name}"
/password "{server_password}"
/adminpw "{admin}"
/ip 0.0.0.0
/gameport {port}
/rconport {rcon}
/tps {tps}
/playerlimit {players}
/playercount 1
/lan {lan}
/bandwidth {bandwidth}
/voicemode 0
/netregion {region}
/videostd NTSC
/heroes {heroes}
/awards 1
/hrunlock 3
/hrunlockvalue 10
/hrplayer 8
/hrteam 1
/hrrespawn 90
/contimelimit 0
/ctftimelimit 0
/huntimelimit 0
/ctfscorelimit 5
/assscorelimit 0
/huntscorelimit 0
/conreinforcements 100
/assreinforcements 0
/teamdamage {damage}
/autoassignteams {assign}
/shownames 1
/randomize {randomize}
/difficulty {difficulty}
/spawn 0
/pregametime 0
/kickvotethreshold 0
/teamvotethreshold 0
/conaiperteam {ai}
/ctfaiperteam {ai}
/assaiperteam {ai}
/aimassist 1
/autokickscore 0
/autokickscorevalue 6
/autokickping 0
/autokickpingvalue 250
/autokickpingwarnings 0
/autokickword 0
/autokickwordwarnings 3
/autoannounce 0
/autoannounceperiod 60
/autocsvlogging 0
/autocsvlogfilename "statistics.csv"
'''
    rotation=' '.join(f'/addmap {item}' for item in maps)+'\n'
    return settings.encode(),rotation.encode(),server_name,port,rcon

def _launch(argv,env): os.execvpe('wine',argv,env)
def run_runtime(script_path,env=None,launch=_launch):
    env=dict(os.environ if env is None else env)
    if env.get('ACCEPT_LUCASARTS_LICENSE','NO')!='YES': raise ValidationError('ACCEPT_LUCASARTS_LICENSE must be exactly YES before proprietary content may be used')
    if env.get('NONCOMMERCIAL_USE','NO')!='YES': raise ValidationError('NONCOMMERCIAL_USE must be exactly YES before proprietary content may be used')
    script_path=Path(script_path); base_path=script_path.parent
    base_fd=open_real_directory(base_path); base_initial=os.fstat(base_fd)
    try:
        script_info=os.stat(script_path.name,dir_fd=base_fd,follow_symlinks=False)
        if not stat.S_ISREG(script_info.st_mode) or script_info.st_nlink>1: raise ValidationError('start.sh must be a real independent file')
        try: server_fd=os.open('server',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=base_fd)
        except OSError as exc: raise ValidationError('verified server tree is missing; reinstall') from exc
        try:
            marker=read_regular(base_fd,'.swbf2-byoc-verified').decode(errors='strict').splitlines()
            expected=f'BattlefrontII.exe sha256={ORIGINAL_EXE_SHA256}'
            if expected not in marker: raise ValidationError('installation verification marker is invalid; reinstall')
            if hash_regular(server_fd,'BattlefrontII.exe')!=ORIGINAL_EXE_SHA256: raise ValidationError('BattlefrontII.exe checksum drift detected; reinstall from original content')
            for required in ('license.txt','data/_LVL_PC/core.lvl','data/_LVL_PC/mission.lvl','data/_LVL_PC/shell.lvl'):
                parts=required.split('/'); fd=os.dup(server_fd)
                try:
                    for part in parts[:-1]:
                        new=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd); os.close(fd); fd=new
                    if not read_regular(fd,parts[-1]): raise ValidationError(f'required original data file is empty: {required}')
                finally: os.close(fd)
            settings_data,rotation_data,server_name,port,rcon=configuration(env)
            try: os.mkdir('settings',0o700,dir_fd=server_fd)
            except FileExistsError: pass
            try: settings_fd=os.open('settings',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=server_fd)
            except OSError as exc: raise ValidationError('settings must be a real directory') from exc
            settings_initial=os.fstat(settings_fd)
            try:
                atomic_write(settings_fd,'ServerSettings.cfg',settings_data,0o600)
                atomic_write(settings_fd,'ServerRotation.cfg',rotation_data,0o600)
                atomic_write(base_fd,'UNOFFICIAL-SERVER-NOTICE.txt',NOTICE.encode(),0o600)
                current_settings=os.stat('settings',dir_fd=server_fd,follow_symlinks=False)
                if not stat.S_ISDIR(current_settings.st_mode) or identity(current_settings)!=identity(settings_initial): raise ValidationError('settings directory changed while generated files were written')
            finally: os.close(settings_fd)
            try: current_base=os.stat(base_path,follow_symlinks=False)
            except OSError as exc: raise ValidationError('runtime base changed during startup') from exc
            if not stat.S_ISDIR(current_base.st_mode) or identity(current_base)!=identity(base_initial): raise ValidationError('runtime base changed during startup')
            print('Unofficial server: not affiliated with or endorsed by LucasArts or its successors.')
            print('Original GameSpy discovery is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate SWBFSpy-patched Steam client; public-browser discovery and other client builds remain unverified.')
            print(f'Launching verified original SWBF2 dedicated server: {server_name}, UDP {port}, optional RCON TCP {rcon}')
            argv=['wine','./BattlefrontII.exe','/win','/norender','/nosound','/nointro','/autonet','dedicated','/resolution','640','480']
            old=os.open('.',os.O_RDONLY|os.O_DIRECTORY)
            try: os.fchdir(server_fd); return launch(argv,env)
            finally: os.fchdir(old); os.close(old)
        finally: os.close(server_fd)
    finally: os.close(base_fd)

def main(argv=None):
    argv=sys.argv[1:] if argv is None else argv
    if len(argv)!=1: print('ERROR: startup requires its script path',file=sys.stderr); return 2
    try: run_runtime(argv[0])
    except (ValidationError,OSError,UnicodeError) as exc: print(f'ERROR: {exc}',file=sys.stderr); return 1
    return 0
if __name__=='__main__': raise SystemExit(main())
PY_RUNTIME
