# Star Wars Battlefront II Classic (2005) BYOC egg

Importable PTDL_v2 egg for the original LucasArts Windows v1.1 dedicated server under Wine. This repository contains no proprietary game files. It is intended for operator-supplied content under documented license constraints; it is not legal advice. This unofficial project is not affiliated with or endorsed by LucasArts or its successors.

## Accepted operator content

Upload exactly one candidate to `/mnt/server`:

1. The exact file `swbattlefrontiipcserver_v1_1.exe` (161902200 bytes; SHA-256 `667e5065a58bfc02d9d8da9056fae5911d5f5abef168e8efe602911ab24304d5`); or
2. A pre-extracted real directory named `/mnt/server/swbf2-original-server` containing the complete original dedicated-server installation. Extract or install it on your own PC, then upload the directory through SFTP. The directory itself and every directory below it must be real directories, not symlinks.

The directory mode exists for operators who already extracted or installed their copy. Do not publish the directory or installer.

## Failed first install → upload → reinstall

1. Import the egg and create the server. The failed first install on an empty volume is expected.
2. Upload the exact installer **or** the complete `swbf2-original-server` directory through SFTP.
3. After reviewing the supplied license, set `ACCEPT_LUCASARTS_LICENSE=YES`.
4. Set `NONCOMMERCIAL_USE=YES` to acknowledge personal, noncommercial use.
5. Click **Reinstall**.

Both acknowledgments must be exactly uppercase `YES` at install and startup.

## Safety and authentication boundaries

Installer mode first copies the upload into private staging with `O_NOFOLLOW`, inode/device/size/time stability checks, and a pinned size and SHA-256. Only that private snapshot is passed to the extractors.

Directory mode walks and copies from descriptor-anchored source directories into a fresh private release. It rejects symlinks, detectable regular-file hardlinks, devices, FIFOs, sockets, other special files, path or case collisions, alternate `BattlefrontII*.exe` files, more than 20,000 files, an individual file over 512 MiB, more than 4 GiB total, depth over 24, and paths over 240 characters. A changing source fails closed.

Both modes require:

- `BattlefrontII.exe` with SHA-256 `eeb3bd768ec6ebdf7d0bca39a34a354c4d465b74f244702727ef6b70cbaea04a`;
- non-empty `license.txt`, `data/_LVL_PC/core.lvl`, `mission.lvl`, and `shell.lvl`;
- populated `data/_LVL_PC/SIDE` and representative stock-map `data/_LVL_PC/UTA` directories;
- no alternate `BattlefrontII*.exe`.

Only `BattlefrontII.exe` is authenticated against an exact hash. Remaining content receives structural, type, path, count, and size safety checks; it is not authenticated against a full vendor manifest. Modified or incomplete files outside the minimum inventory may pass and then fail at runtime or omit selected map content.

## Downloads and transaction

Python and base packages are installed before the first Python invocation. Only installer mode adds the Debian build/extraction packages and downloads the two pinned open-source `iss_extract` source files. Debian packages come from the installer image's configured repositories. Proprietary content is never downloaded.

The installer fully constructs `swbf2-runtime` in a new private release directory. Runtime files, startup, notice, marker, and server tree commit together through one atomic directory rename or Linux `renameat2(RENAME_EXCHANGE)`. An existing runtime remains intact until the final exchange; a generated-output failure cannot activate a partial release. Existing symlinks at generated-output names are never followed.

Startup pins the real release, server, and settings directories by file descriptor; rechecks the marker, executable hash, license, and representative data; writes settings and notice with descriptor-anchored temporary files plus atomic replacement; and fails closed if the release or settings parent changes. It launches only:

```text
wine ./BattlefrontII.exe /win /norender /nosound /nointro /autonet dedicated /resolution 640 480
```

Text values are line/quote sanitized, numeric and boolean values are bounded, placeholder admin passwords are rejected, and map rotation is restricted to the 85 tokens in [`SUPPORTED-MAPS.md`](SUPPORTED-MAPS.md).

## Limitations

Original GameSpy discovery is defunct. A direct-connect join was verified on 2026-11-01 with one legitimate Steam copy using the optional SWBFSpy player-side patch. Public-browser discovery, reconnect behavior, and other client builds remain unverified; no store-client browser compatibility is claimed. Optional client-side community information is in [`CLIENT-SETUP.md`](CLIENT-SETUP.md); this egg does not download or modify client or server executables.

## Source layout and local checks

- `scripts/install_runtime.py` — descriptor-anchored source snapshot/copy, verification, extraction orchestration, and atomic release commit.
- `scripts/runtime.py` — pinned startup validation, configuration generation, and Wine launch.
- `scripts/start.sh`, `scripts/install.sh`, and the egg JSON — deterministic rendered artifacts.
- `scripts/build_release.py` — renderer.

```bash
python3 scripts/build_release.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
bash -n scripts/install.sh scripts/start.sh
python3 -m py_compile scripts/build_release.py scripts/install_runtime.py scripts/runtime.py tests/test_project.py
python3 -m json.tool egg-swbf2-classic-2005.json >/dev/null
sha256sum --check SHA256SUMS
```

No live panel, production server, network service, GitHub operation, commit, or publication is part of local validation.

## License

The egg metadata, original scripts, tests, and documentation are MIT licensed. Star Wars Battlefront II and its server files remain proprietary and are not included.
