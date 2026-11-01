# Validation record

## Scope

The automated suite was local and used synthetic, non-proprietary fixtures. It did not access a production panel, network service, GitHub publication path, or proprietary payload. A separate authorized live acceptance on 2026-11-01 used the pre-extracted-directory route and verified the exact original executable, Wine process survival, game UDP and RCON TCP listeners, an external RCON handshake, controlled restart, bounded soak, and a successful direct-connect join from one legitimate SWBFSpy-patched Steam client. The exact proprietary-installer extraction route, public-browser discovery, reconnect behavior, and other client builds remain unverified. Runtime images and configured Debian repositories remain mutable external inputs. Post-acceptance wording updates do not change installation, validation, configuration, or launch mechanics.

## Automated coverage

The suite covers PTDL_v2 structure, deterministic rendering, shell/Python/JSON parsing, exact acknowledgments, the two accepted source modes, synthetic pre-extracted-directory installation, fake-Wine argv capture, configuration sanitization, exact installer and executable pins, no production hash override, and intended errors independent of host apt permissions.

Directory behavior checks rejection of symlinks, hardlinks, special files, case collisions, alternate executables, missing structure, wrong hashes, file/byte/depth/path caps, and source changes during copy. Installer snapshot tests cover `O_NOFOLLOW` and source-change detection.

Transactional tests cover existing notice/start/marker symlink targets, rollback on generated-output failure, atomic whole-release replacement, descriptor-pinned base/settings swaps, and atomic replacement of settings and notice symlinks without touching external targets.

Documentation/release checks cover the absence of compressed-input support, exact download scope, approved client-information URLs, map allowlist, checksum coverage, and public privacy/proprietary scans.

## Commands

```bash
python3 scripts/build_release.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
bash -n scripts/install.sh scripts/start.sh
python3 -m py_compile scripts/build_release.py scripts/install_runtime.py scripts/runtime.py tests/test_project.py
python3 -m json.tool egg-swbf2-classic-2005.json >/dev/null
sha256sum --check SHA256SUMS
git diff --check
```

The final run completed 33 unit tests successfully. Shell syntax, Python compilation, JSON parsing, deterministic rendering, checksums, diff whitespace, and public/private/proprietary scans passed.

## Remaining acceptance work

An authorized operator must still test the exact proprietary-installer path and inspect the resulting extracted package. Public-browser discovery, a deliberate disconnect/reconnect cycle, and additional legitimate client builds remain separate acceptance work.
