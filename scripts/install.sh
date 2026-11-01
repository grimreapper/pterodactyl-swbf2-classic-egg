#!/usr/bin/env bash
set -Eeuo pipefail
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ "${ACCEPT_LUCASARTS_LICENSE:-NO}" == "YES" ]] || fail "ACCEPT_LUCASARTS_LICENSE must be exactly YES; review and accept the license supplied with your copy"
[[ "${NONCOMMERCIAL_USE:-NO}" == "YES" ]] || fail "NONCOMMERCIAL_USE must be exactly YES; this candidate is limited to personal, noncommercial hosting"
SERVER_DIR="${SERVER_DIR:-/mnt/server}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends python3
python3 - "$SERVER_DIR" <<'PY_INSTALL'
START_SCRIPT = '#!/usr/bin/env bash\nset -Eeuo pipefail\npython3 - "$0" <<\'PY_RUNTIME\'\n#!/usr/bin/env python3\n"""Pinned-descriptor startup and generated configuration writer."""\nimport hashlib\nimport os\nfrom pathlib import Path\nimport secrets\nimport stat\nimport sys\n\nORIGINAL_EXE_SHA256="eeb3bd768ec6ebdf7d0bca39a34a354c4d465b74f244702727ef6b70cbaea04a"\nNOTICE=("This is an unofficial community-operated server. It is not affiliated with or endorsed by LucasArts or its successors.\\n"\n        "The original GameSpy discovery service is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate SWBFSpy-patched Steam client; public-browser discovery and other client builds remain unverified.\\n")\nSUPPORTED_MAPS=set("""cor1c_con cor1c_ctf cor1g_con cor1g_ctf dag1c_con dag1c_ctf dag1g_con dag1g_ctf dea1c_1flag dea1c_con dea1g_1flag dea1g_con end1g_1flag end1g_con end1g_hunt fel1c_1flag fel1c_con fel1g_1flag fel1g_con geo1c_con geo1c_ctf geo1c_hunt hot1g_1flag hot1g_con hot1g_hunt kam1c_1flag kam1c_con kam1g_1flag kam1g_con kas2c_con kas2c_ctf kas2c_hunt kas2g_con kas2g_ctf mus1c_con mus1c_ctf mus1g_con mus1g_ctf myg1c_con myg1c_ctf myg1g_con myg1g_ctf nab2c_con nab2c_ctf nab2c_hunt nab2g_con nab2g_ctf pol1c_con pol1c_ctf pol1g_con pol1g_ctf spa1g_1flag spa1g_ass spa3c_1flag spa3c_ass spa6c_1flag spa6c_ass spa7c_1flag spa7c_ass spa8g_1flag spa8g_ass spa9g_1flag spa9g_ass tan1c_1flag tan1c_con tan1g_1flag tan1g_con tat2c_con tat2c_ctf tat2g_con tat2g_ctf tat2g_eli tat2g_hunt tat3c_1flag tat3c_con tat3g_1flag tat3g_con uta1c_1flag uta1c_con uta1g_1flag uta1g_con yav1c_1flag yav1c_con yav1g_1flag yav1g_con""".split())\n\nclass ValidationError(Exception): pass\n\ndef identity(st): return (st.st_dev,st.st_ino,stat.S_IFMT(st.st_mode))\ndef open_real_directory(path):\n    path=Path(path); absolute=path if path.is_absolute() else Path.cwd()/path; fd=os.open(\'/\',os.O_RDONLY|os.O_DIRECTORY)\n    try:\n        for part in absolute.parts[1:]:\n            if part in (\'\',\'.\'): continue\n            if part==\'..\': raise ValidationError(\'runtime path contains parent component\')\n            try: new=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd)\n            except OSError as exc: raise ValidationError(\'runtime base must have only real, unchanged directory components\') from exc\n            os.close(fd); fd=new\n        return fd\n    except Exception: os.close(fd); raise\n\ndef read_regular(fd,name):\n    try: f=os.open(name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=fd)\n    except OSError as exc: raise ValidationError(f\'{name} is missing or not a regular file; reinstall\') from exc\n    try:\n        st=os.fstat(f)\n        if not stat.S_ISREG(st.st_mode) or st.st_nlink>1: raise ValidationError(f\'{name} is not an independent regular file; reinstall\')\n        data=b\'\'\n        while True:\n            chunk=os.read(f,1024*1024)\n            if not chunk: break\n            data+=chunk\n        if identity(os.fstat(f))!=identity(st) or os.fstat(f).st_size!=len(data): raise ValidationError(f\'{name} changed while being read\')\n        return data\n    finally: os.close(f)\n\ndef hash_regular(fd,name): return hashlib.sha256(read_regular(fd,name)).hexdigest()\n\ndef atomic_write(directory_fd,name,data,mode):\n    temporary=f\'.{name}.tmp-{secrets.token_hex(8)}\'\n    out=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,mode,dir_fd=directory_fd)\n    try:\n        view=memoryview(data)\n        while view: view=view[os.write(out,view):]\n        os.fsync(out)\n    except Exception:\n        try: os.unlink(temporary,dir_fd=directory_fd)\n        except OSError: pass\n        raise\n    finally: os.close(out)\n    os.replace(temporary,name,src_dir_fd=directory_fd,dst_dir_fd=directory_fd)\n    os.fsync(directory_fd)\n\ndef text(value): return value.replace(\'\\r\',\' \').replace(\'\\n\',\' \').replace(\'"\',"\'")[:96]\ndef integer(env,name,default,minimum,maximum):\n    value=env.get(name,default)\n    if not value.isascii() or not value.isdigit() or len(value)>20 or not minimum<=int(value)<=maximum: raise ValidationError(f\'{name} must be between {minimum} and {maximum}\')\n    return value\ndef boolean(env,name,default):\n    value=env.get(name,default)\n    if value not in (\'0\',\'1\'): raise ValidationError(f\'{name} must be 0 or 1\')\n    return value\n\ndef configuration(env):\n    server_name=text(env.get(\'SERVER_NAME\',\'SWBF2 Dedicated Server\')); server_password=text(env.get(\'SERVER_PASSWORD\',\'\')); admin=text(env.get(\'ADMIN_PASSWORD\',\'CHANGE_ME\'))\n    if not server_name: raise ValidationError(\'SERVER_NAME must not be empty\')\n    if admin.lower() in (\'\',\'change-me\',\'change_me\',\'changeme\') or len(admin)<8: raise ValidationError(\'ADMIN_PASSWORD must be changed and contain at least 8 characters\')\n    port=integer(env,\'SERVER_PORT\',\'3658\',1024,65535); rcon=integer(env,\'RCON_PORT\',\'4658\',1024,65535); players=integer(env,\'MAX_PLAYERS\',\'64\',1,64)\n    tps=integer(env,\'TPS\',\'30\',10,60); ai=integer(env,\'AI_PER_TEAM\',\'0\',0,32); difficulty=integer(env,\'DIFFICULTY\',\'2\',1,3); bandwidth=integer(env,\'BANDWIDTH\',\'6144\',64,65535)\n    region=env.get(\'REGION\',\'NA\')\n    if region not in (\'NA\',\'EUR\',\'JAP\'): raise ValidationError(\'REGION must be NA, EUR, or JAP\')\n    heroes=boolean(env,\'HEROES\',\'1\'); damage=boolean(env,\'TEAM_DAMAGE\',\'0\'); assign=boolean(env,\'AUTO_ASSIGN\',\'1\'); lan=boolean(env,\'LAN_MODE\',\'0\'); randomize=boolean(env,\'RANDOMIZE\',\'0\')\n    maps=env.get(\'MAP_ROTATION\',\'uta1c_con tan1c_con cor1g_con\').replace(\'\\r\',\' \').replace(\'\\n\',\' \').split()\n    if not maps: raise ValidationError(\'MAP_ROTATION must contain at least one supported stock map token\')\n    for item in maps:\n        if item not in SUPPORTED_MAPS: raise ValidationError(f\'unsupported stock map token: {item}\')\n    settings=f\'\'\'/gamename "{server_name}"\n/password "{server_password}"\n/adminpw "{admin}"\n/ip 0.0.0.0\n/gameport {port}\n/rconport {rcon}\n/tps {tps}\n/playerlimit {players}\n/playercount 1\n/lan {lan}\n/bandwidth {bandwidth}\n/voicemode 0\n/netregion {region}\n/videostd NTSC\n/heroes {heroes}\n/awards 1\n/hrunlock 3\n/hrunlockvalue 10\n/hrplayer 8\n/hrteam 1\n/hrrespawn 90\n/contimelimit 0\n/ctftimelimit 0\n/huntimelimit 0\n/ctfscorelimit 5\n/assscorelimit 0\n/huntscorelimit 0\n/conreinforcements 100\n/assreinforcements 0\n/teamdamage {damage}\n/autoassignteams {assign}\n/shownames 1\n/randomize {randomize}\n/difficulty {difficulty}\n/spawn 0\n/pregametime 0\n/kickvotethreshold 0\n/teamvotethreshold 0\n/conaiperteam {ai}\n/ctfaiperteam {ai}\n/assaiperteam {ai}\n/aimassist 1\n/autokickscore 0\n/autokickscorevalue 6\n/autokickping 0\n/autokickpingvalue 250\n/autokickpingwarnings 0\n/autokickword 0\n/autokickwordwarnings 3\n/autoannounce 0\n/autoannounceperiod 60\n/autocsvlogging 0\n/autocsvlogfilename "statistics.csv"\n\'\'\'\n    rotation=\' \'.join(f\'/addmap {item}\' for item in maps)+\'\\n\'\n    return settings.encode(),rotation.encode(),server_name,port,rcon\n\ndef _launch(argv,env): os.execvpe(\'wine\',argv,env)\ndef run_runtime(script_path,env=None,launch=_launch):\n    env=dict(os.environ if env is None else env)\n    if env.get(\'ACCEPT_LUCASARTS_LICENSE\',\'NO\')!=\'YES\': raise ValidationError(\'ACCEPT_LUCASARTS_LICENSE must be exactly YES before proprietary content may be used\')\n    if env.get(\'NONCOMMERCIAL_USE\',\'NO\')!=\'YES\': raise ValidationError(\'NONCOMMERCIAL_USE must be exactly YES before proprietary content may be used\')\n    script_path=Path(script_path); base_path=script_path.parent\n    base_fd=open_real_directory(base_path); base_initial=os.fstat(base_fd)\n    try:\n        script_info=os.stat(script_path.name,dir_fd=base_fd,follow_symlinks=False)\n        if not stat.S_ISREG(script_info.st_mode) or script_info.st_nlink>1: raise ValidationError(\'start.sh must be a real independent file\')\n        try: server_fd=os.open(\'server\',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=base_fd)\n        except OSError as exc: raise ValidationError(\'verified server tree is missing; reinstall\') from exc\n        try:\n            marker=read_regular(base_fd,\'.swbf2-byoc-verified\').decode(errors=\'strict\').splitlines()\n            expected=f\'BattlefrontII.exe sha256={ORIGINAL_EXE_SHA256}\'\n            if expected not in marker: raise ValidationError(\'installation verification marker is invalid; reinstall\')\n            if hash_regular(server_fd,\'BattlefrontII.exe\')!=ORIGINAL_EXE_SHA256: raise ValidationError(\'BattlefrontII.exe checksum drift detected; reinstall from original content\')\n            for required in (\'license.txt\',\'data/_LVL_PC/core.lvl\',\'data/_LVL_PC/mission.lvl\',\'data/_LVL_PC/shell.lvl\'):\n                parts=required.split(\'/\'); fd=os.dup(server_fd)\n                try:\n                    for part in parts[:-1]:\n                        new=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd); os.close(fd); fd=new\n                    if not read_regular(fd,parts[-1]): raise ValidationError(f\'required original data file is empty: {required}\')\n                finally: os.close(fd)\n            settings_data,rotation_data,server_name,port,rcon=configuration(env)\n            try: os.mkdir(\'settings\',0o700,dir_fd=server_fd)\n            except FileExistsError: pass\n            try: settings_fd=os.open(\'settings\',os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=server_fd)\n            except OSError as exc: raise ValidationError(\'settings must be a real directory\') from exc\n            settings_initial=os.fstat(settings_fd)\n            try:\n                atomic_write(settings_fd,\'ServerSettings.cfg\',settings_data,0o600)\n                atomic_write(settings_fd,\'ServerRotation.cfg\',rotation_data,0o600)\n                atomic_write(base_fd,\'UNOFFICIAL-SERVER-NOTICE.txt\',NOTICE.encode(),0o600)\n                current_settings=os.stat(\'settings\',dir_fd=server_fd,follow_symlinks=False)\n                if not stat.S_ISDIR(current_settings.st_mode) or identity(current_settings)!=identity(settings_initial): raise ValidationError(\'settings directory changed while generated files were written\')\n            finally: os.close(settings_fd)\n            try: current_base=os.stat(base_path,follow_symlinks=False)\n            except OSError as exc: raise ValidationError(\'runtime base changed during startup\') from exc\n            if not stat.S_ISDIR(current_base.st_mode) or identity(current_base)!=identity(base_initial): raise ValidationError(\'runtime base changed during startup\')\n            print(\'Unofficial server: not affiliated with or endorsed by LucasArts or its successors.\')\n            print(\'Original GameSpy discovery is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate SWBFSpy-patched Steam client; public-browser discovery and other client builds remain unverified.\')\n            print(f\'Launching verified original SWBF2 dedicated server: {server_name}, UDP {port}, optional RCON TCP {rcon}\')\n            argv=[\'wine\',\'./BattlefrontII.exe\',\'/win\',\'/norender\',\'/nosound\',\'/nointro\',\'/autonet\',\'dedicated\',\'/resolution\',\'640\',\'480\']\n            old=os.open(\'.\',os.O_RDONLY|os.O_DIRECTORY)\n            try: os.fchdir(server_fd); return launch(argv,env)\n            finally: os.fchdir(old); os.close(old)\n        finally: os.close(server_fd)\n    finally: os.close(base_fd)\n\ndef main(argv=None):\n    argv=sys.argv[1:] if argv is None else argv\n    if len(argv)!=1: print(\'ERROR: startup requires its script path\',file=sys.stderr); return 2\n    try: run_runtime(argv[0])\n    except (ValidationError,OSError,UnicodeError) as exc: print(f\'ERROR: {exc}\',file=sys.stderr); return 1\n    return 0\nif __name__==\'__main__\': raise SystemExit(main())\nPY_RUNTIME\n'
#!/usr/bin/env python3
"""Securely stage operator-supplied SWBF2 server content."""
import ctypes
import errno
import hashlib
import os
from pathlib import Path
import secrets
import stat
import subprocess
import sys

EXPECTED_INSTALLER_SIZE = 161902200
EXPECTED_INSTALLER_SHA256 = "667e5065a58bfc02d9d8da9056fae5911d5f5abef168e8efe602911ab24304d5"
ORIGINAL_EXE_SHA256 = "eeb3bd768ec6ebdf7d0bca39a34a354c4d465b74f244702727ef6b70cbaea04a"
ISS_COMMIT = "01232146c9284a86958817817849f320e77f5fb7"
ISS_C_SHA256 = "362f06408d646e079c5ce462be39a20542f01249d92e353a9998d96d3be96871"
ISS_H_SHA256 = "07bc516eead9d5e9685a9b65f93e50c41cb3b593f8fa379203e8ed93b13726b2"
MAX_FILES = 20_000
MAX_SINGLE_FILE = 512 * 1024 * 1024
MAX_TOTAL_BYTES = 4 * 1024 * 1024 * 1024
MAX_DEPTH = 24
MAX_PATH_LENGTH = 240
REQUIRED_FILES = ("BattlefrontII.exe", "license.txt", "data/_LVL_PC/core.lvl", "data/_LVL_PC/mission.lvl", "data/_LVL_PC/shell.lvl")
REQUIRED_DIRS = ("data/_LVL_PC/SIDE", "data/_LVL_PC/UTA")
NOTICE = ("This is an unofficial community-operated server. It is not affiliated with or endorsed by LucasArts or its successors.\n"
          "The original GameSpy discovery service is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate SWBFSpy-patched Steam client; public-browser discovery and other client builds remain unverified.\n")
try:
    START_SCRIPT
except NameError:
    START_SCRIPT = ""

class ValidationError(Exception):
    pass

def _identity(st):
    return (st.st_dev, st.st_ino, stat.S_IFMT(st.st_mode), st.st_size, st.st_mtime_ns, st.st_ctime_ns)

def open_real_directory(path):
    path = Path(path)
    absolute = path if path.is_absolute() else Path.cwd() / path
    parts = absolute.parts
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in parts[1:]:
            if part in ("", "."):
                continue
            if part == "..":
                raise ValidationError("directory path contains a parent component")
            try:
                newfd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            except OSError as exc:
                raise ValidationError(f"directory path must contain only real directories (no symlink): {absolute}") from exc
            os.close(fd)
            fd = newfd
        return fd
    except Exception:
        os.close(fd)
        raise

def _copy_regular_file(source_fd, source_stat, destination_fd, name, relative):
    before = os.fstat(source_fd)
    if _identity(before) != _identity(source_stat):
        raise ValidationError(f"source changed before copy: {relative}")
    if before.st_nlink > 1:
        raise ValidationError(f"source contains a hardlink: {relative}")
    output_fd = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=destination_fd)
    written = 0
    try:
        while True:
            chunk = os.read(source_fd, 1024 * 1024)
            if not chunk:
                break
            written += len(chunk)
            if written > before.st_size:
                raise ValidationError(f"source changed while copying: {relative}")
            view = memoryview(chunk)
            while view:
                view = view[os.write(output_fd, view):]
        os.fsync(output_fd)
    finally:
        os.close(output_fd)
    after = os.fstat(source_fd)
    if _identity(after) != _identity(before) or written != before.st_size:
        raise ValidationError(f"source changed while copying: {relative}")

def _copy_tree_fds(source_fd, destination_parent_fd, destination_name):
    os.mkdir(destination_name, 0o700, dir_fd=destination_parent_fd)
    destination_fd = os.open(destination_name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=destination_parent_fd)
    state = {"files": 0, "bytes": 0, "seen": {}}
    def recurse(src_fd, dst_fd, prefix, depth):
        if depth > MAX_DEPTH:
            raise ValidationError(f"source path exceeds depth cap: {prefix}")
        directory_before = os.fstat(src_fd)
        names = sorted(os.listdir(src_fd))
        local_folded = {}
        for name in names:
            if name in (".", "..") or "/" in name or "\x00" in name:
                raise ValidationError(f"source contains an invalid path component: {name!r}")
            relative = f"{prefix}/{name}" if prefix else name
            if len(relative) > MAX_PATH_LENGTH:
                raise ValidationError(f"source path exceeds path-length cap: {relative}")
            folded_name = name.casefold()
            if folded_name in local_folded and local_folded[folded_name] != name:
                raise ValidationError(f"source contains a case collision: {local_folded[folded_name]} and {name}")
            local_folded[folded_name] = name
            folded = relative.casefold()
            if folded in state["seen"] and state["seen"][folded] != relative:
                raise ValidationError(f"source contains a case collision: {state['seen'][folded]} and {relative}")
            state["seen"][folded] = relative
            info = os.stat(name, dir_fd=src_fd, follow_symlinks=False)
            if stat.S_ISLNK(info.st_mode):
                raise ValidationError(f"source contains a symlink: {relative}")
            if stat.S_ISDIR(info.st_mode):
                child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=src_fd)
                try:
                    if _identity(os.fstat(child)) != _identity(info):
                        raise ValidationError(f"source directory changed: {relative}")
                    os.mkdir(name, 0o700, dir_fd=dst_fd)
                    child_dst = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=dst_fd)
                    try:
                        recurse(child, child_dst, relative, depth + 1)
                    finally:
                        os.close(child_dst)
                    if _identity(os.fstat(child)) != _identity(info):
                        raise ValidationError(f"source directory changed: {relative}")
                finally:
                    os.close(child)
            elif stat.S_ISREG(info.st_mode):
                if info.st_nlink > 1:
                    raise ValidationError(f"source contains a hardlink: {relative}")
                if info.st_size > MAX_SINGLE_FILE:
                    raise ValidationError(f"source file exceeds per-file cap: {relative}")
                state["files"] += 1
                state["bytes"] += info.st_size
                if state["files"] > MAX_FILES:
                    raise ValidationError("source exceeds file-count cap")
                if state["bytes"] > MAX_TOTAL_BYTES:
                    raise ValidationError("source exceeds total-size cap")
                source_file = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=src_fd)
                try:
                    _copy_regular_file(source_file, info, dst_fd, name, relative)
                finally:
                    os.close(source_file)
            else:
                raise ValidationError(f"source contains a special or non-regular file: {relative}")
        if _identity(os.fstat(src_fd)) != _identity(directory_before):
            raise ValidationError(f"source directory changed while copying: {prefix or '.'}")
    try:
        recurse(source_fd, destination_fd, "", 1)
        os.fsync(destination_fd)
    finally:
        os.close(destination_fd)
    return state

def sha256_path(path):
    digest = hashlib.sha256()
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        for chunk in iter(lambda: os.read(fd, 1024 * 1024), b""):
            digest.update(chunk)
    finally:
        os.close(fd)
    return digest.hexdigest()

def verify_private_tree(root, expected_hash):
    root = Path(root)
    for relative in REQUIRED_FILES:
        path = root / relative
        try:
            info = path.stat(follow_symlinks=False)
        except FileNotFoundError as exc:
            raise ValidationError(f"required non-empty file is missing: {relative}") from exc
        if not stat.S_ISREG(info.st_mode) or info.st_size == 0:
            raise ValidationError(f"required non-empty file is missing: {relative}")
    for relative in REQUIRED_DIRS:
        directory = root / relative
        if not directory.is_dir() or directory.is_symlink():
            raise ValidationError(f"required populated directory is missing: {relative}")
        if not any(path.is_file() and not path.is_symlink() for path in directory.rglob("*")):
            raise ValidationError(f"required populated directory is missing: {relative}")
    for path in root.rglob("*"):
        if path.is_file() and path.name.casefold().startswith("battlefrontii") and path.suffix.casefold() == ".exe":
            if path.relative_to(root).as_posix() != "BattlefrontII.exe":
                raise ValidationError(f"alternate BattlefrontII executable is forbidden: {path.relative_to(root)}")
    actual = sha256_path(root / "BattlefrontII.exe")
    if actual != expected_hash:
        raise ValidationError(f"BattlefrontII.exe checksum mismatch: expected {expected_hash}, got {actual}")

def copy_and_verify_tree(source, destination, expected_hash=ORIGINAL_EXE_SHA256):
    source = Path(source)
    if source.is_symlink():
        raise ValidationError("source must be a real directory, not a symlink")
    try:
        source_fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    except OSError as exc:
        raise ValidationError("source must be a real directory, not a symlink") from exc
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        os.close(source_fd)
        raise ValidationError("private staging destination must not exist")
    parent_fd = open_real_directory(destination.parent)
    try:
        _copy_tree_fds(source_fd, parent_fd, destination.name)
    finally:
        os.close(source_fd); os.close(parent_fd)
    verify_private_tree(destination, expected_hash)

def _snapshot_fds(source_parent_fd, source_name, destination_parent_fd, destination_name, size, expected_hash):
    info = os.stat(source_name, dir_fd=source_parent_fd, follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode) or info.st_nlink > 1:
        raise ValidationError("installer must be a regular non-symlinked, non-hardlinked file")
    if info.st_size != size:
        raise ValidationError(f"installer size mismatch: expected {size} bytes, got {info.st_size}")
    src = os.open(source_name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=source_parent_fd)
    digest = hashlib.sha256()
    out = os.open(destination_name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=destination_parent_fd)
    try:
        before = os.fstat(src)
        if _identity(before) != _identity(info): raise ValidationError("installer changed before snapshot")
        copied = 0
        while True:
            chunk = os.read(src, 1024 * 1024)
            if not chunk: break
            copied += len(chunk); digest.update(chunk)
            view = memoryview(chunk)
            while view:
                view = view[os.write(out, view):]
        os.fsync(out)
        if copied != size or _identity(os.fstat(src)) != _identity(before):
            raise ValidationError("installer changed while snapshotting")
    finally:
        os.close(src); os.close(out)
    if digest.hexdigest() != expected_hash:
        raise ValidationError("installer checksum mismatch")

def snapshot_installer(source, destination, size=EXPECTED_INSTALLER_SIZE, expected_hash=EXPECTED_INSTALLER_SHA256):
    source = Path(source); destination = Path(destination)
    source_parent = open_real_directory(source.parent); destination_parent = open_real_directory(destination.parent)
    try: _snapshot_fds(source_parent, source.name, destination_parent, destination.name, size, expected_hash)
    finally: os.close(source_parent); os.close(destination_parent)

def _write_new(fd, name, data, mode):
    out = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode, dir_fd=fd)
    try:
        view = memoryview(data)
        while view:
            view = view[os.write(out, view):]
        os.fsync(out)
    finally: os.close(out)

def write_release_files(release_fd, mode):
    if not START_SCRIPT:
        raise ValidationError("embedded startup script is missing")
    _write_new(release_fd, "start.sh", START_SCRIPT.encode(), 0o700)
    marker = f"source={mode}\nBattlefrontII.exe sha256={ORIGINAL_EXE_SHA256}\nlicense.txt=present-structural-check-only\n".encode()
    _write_new(release_fd, ".swbf2-byoc-verified", marker, 0o600)
    _write_new(release_fd, "UNOFFICIAL-SERVER-NOTICE.txt", NOTICE.encode(), 0o600)
    os.fsync(release_fd)

def _exists(fd, name):
    try: os.stat(name, dir_fd=fd, follow_symlinks=False); return True
    except FileNotFoundError: return False

def _remove_private_tree(parent_fd, name):
    try:
        info = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    if not stat.S_ISDIR(info.st_mode):
        os.unlink(name, dir_fd=parent_fd)
        return
    child_fd = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
    try:
        for child in os.listdir(child_fd):
            _remove_private_tree(child_fd, child)
    finally:
        os.close(child_fd)
    os.rmdir(name, dir_fd=parent_fd)

def _run(command, **kwargs):
    try: subprocess.run(command, check=True, **kwargs)
    except subprocess.CalledProcessError as exc: raise ValidationError(f"command failed: {command[0]}") from exc

def _hash_fd_file(fd, name):
    f = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=fd); d=hashlib.sha256()
    try:
        for chunk in iter(lambda: os.read(f, 1024*1024), b""): d.update(chunk)
    finally: os.close(f)
    return d.hexdigest()

def _installer_extract(work_fd):
    _run(["apt-get","install","-y","--no-install-recommends","ca-certificates","curl","gcc","libc6-dev","make","unshield"])
    base=f"/proc/self/fd/{work_fd}"
    os.set_inheritable(work_fd, True)
    urls=((f"https://raw.githubusercontent.com/hifi/iss_extract/{ISS_COMMIT}/iss_extract.c","iss_extract.c",ISS_C_SHA256),(f"https://raw.githubusercontent.com/hifi/iss_extract/{ISS_COMMIT}/pe.h","pe.h",ISS_H_SHA256))
    for url,name,digest in urls:
        _run(["curl","--fail","--location","--silent","--show-error","--retry","3","--retry-all-errors","--connect-timeout","20","--max-time","300","--max-filesize","2000000","--proto","=https","--proto-redir","=https","--output",f"{base}/{name}","--url",url],pass_fds=(work_fd,))
        if _hash_fd_file(work_fd,name)!=digest: raise ValidationError(f"downloaded {name} checksum mismatch")
    _run(["gcc","-std=c99","-O2","-Wall","-Wextra","-o",f"{base}/iss_extract",f"{base}/iss_extract.c"],pass_fds=(work_fd,))
    os.mkdir("outer",0o700,dir_fd=work_fd); os.mkdir("unshielded",0o700,dir_fd=work_fd)
    _run([f"{base}/iss_extract","x",f"{base}/installer.exe"],cwd=f"{base}/outer",pass_fds=(work_fd,))
    outer_fd = os.open("outer", os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=work_fd)
    try:
        if not _exists(outer_fd, "data1.cab"):
            raise ValidationError("verified installer did not contain data1.cab")
    finally:
        os.close(outer_fd)
    _run(["unshield","-d",f"{base}/unshielded","x",f"{base}/outer/data1.cab"],pass_fds=(work_fd,))

def _rename_exchange(fd, first, second):
    libc=ctypes.CDLL(None,use_errno=True); func=getattr(libc,"renameat2",None)
    if func is None: raise ValidationError("atomic directory exchange is unavailable")
    if func(fd,first.encode(),fd,second.encode(),2)!=0:
        err=ctypes.get_errno(); raise ValidationError(f"atomic runtime exchange failed: {os.strerror(err)}")

def install(server_dir):
    server_fd=open_real_directory(server_dir); token=secrets.token_hex(8); work_name=f".swbf2-work-{token}"; release_name=f".swbf2-release-{token}"; committed=False
    try:
        installer_present=_exists(server_fd,"swbattlefrontiipcserver_v1_1.exe"); directory_present=_exists(server_fd,"swbf2-original-server")
        if installer_present+directory_present != 1:
            if installer_present or directory_present: raise ValidationError("provide exactly one supported source, not both")
            raise ValidationError("no operator-supplied content found; after the failed first install, upload exact swbattlefrontiipcserver_v1_1.exe or the full real directory /mnt/server/swbf2-original-server via SFTP, then reinstall")
        os.mkdir(work_name,0o700,dir_fd=server_fd); os.mkdir(release_name,0o700,dir_fd=server_fd)
        work_fd=os.open(work_name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=server_fd); release_fd=os.open(release_name,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=server_fd)
        try:
            if directory_present:
                source_fd=os.open("swbf2-original-server",os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=server_fd)
                try: _copy_tree_fds(source_fd,release_fd,"server")
                finally: os.close(source_fd)
                mode="directory"
            else:
                _snapshot_fds(server_fd,"swbattlefrontiipcserver_v1_1.exe",work_fd,"installer.exe",EXPECTED_INSTALLER_SIZE,EXPECTED_INSTALLER_SHA256)
                _installer_extract(work_fd)
                unshielded=os.open("unshielded",os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=work_fd)
                main_files=os.open("Main_Files",os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=unshielded)
                try: _copy_tree_fds(main_files,release_fd,"server")
                finally: os.close(main_files); os.close(unshielded)
                mode="installer"
            verify_private_tree(Path(f"/proc/self/fd/{release_fd}/server"),ORIGINAL_EXE_SHA256)
            write_release_files(release_fd, mode)
        finally: os.close(work_fd); os.close(release_fd)
        if _exists(server_fd,"swbf2-runtime"):
            _rename_exchange(server_fd,release_name,"swbf2-runtime")
            committed=True
            _remove_private_tree(server_fd, release_name)
        else:
            os.rename(release_name,"swbf2-runtime",src_dir_fd=server_fd,dst_dir_fd=server_fd)
            committed=True
        print("SWBF2 bring-your-own-content installation completed.")
        print("Only the exact-hash original BattlefrontII.exe is authenticated; remaining content passed structural and safety checks.")
    finally:
        _remove_private_tree(server_fd, work_name)
        if not committed:
            _remove_private_tree(server_fd, release_name)
        os.close(server_fd)

def main(argv=None):
    argv=sys.argv[1:] if argv is None else argv
    if len(argv)!=1: print("ERROR: installer requires SERVER_DIR",file=sys.stderr); return 2
    try: install(argv[0])
    except (ValidationError,OSError) as exc: print(f"ERROR: {exc}",file=sys.stderr); return 1
    return 0

if __name__=="__main__": raise SystemExit(main())
PY_INSTALL
