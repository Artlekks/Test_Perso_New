# Validated Linux Web builds

Daily rebuild, from this project in PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\mobile\build_mobile_playtest.ps1
```

Keep the existing HTTPS LAN server running; refresh Safari after `Build complete`.
The helper now defaults to Linux through the dedicated `FishingGameMobileBuild`
WSL 2 distribution. It uses official Godot 4.7.2 and the existing
`Mobile Portrait Web Playtest` preset, features and Web export templates.
There is no CI upload, camera/gameplay change, certificate change or server restart.

## Diagnosis and evidence

The failing Windows export contained a 31,235,696-byte `index.pck`, PCK format 4,
with 1,588 directory entries. `project.binary` existed but had size 0 and hence
no ECFG header. HTML/JS/WASM/PCK all used basename `index`; HTML sizes matched.
This matches the reported [Godot Windows Web-export failure](https://github.com/godotengine/godot/issues/124197).
No game package entry was patched.

The regenerated Linux export contains a 31,222,416-byte PCK, 1,582 entries,
and a 9,454-byte `project.binary` with ECFG header, 38 settings and valid MD5.
Its export basename and HTML PCK/WASM sizes validate together.

## Build architecture

The Linux builder synchronizes the current working project into a dedicated
Linux filesystem mirror. It excludes Windows `.godot`, `.git`, output and build
directories; retains its own Linux import cache between iterations; imports
resources; and exports the same preset. Source files and normal save data are
not changed. Linux-generated artifacts are copied intact to
`build/mobile-web/staging`, which is already ignored by Git.

The read-only PowerShell validator checks all four nonempty output files,
HTML executable/script basename and advertised file sizes, the PCK header,
version, directory bounds, unique nonempty `project.binary`, ECFG header,
settings count and MD5. It deliberately rejects unsupported encrypted/sparse
packs. It does not attempt to repair a corrupt export.

Only after successful staged validation are artifacts published to `export/`,
with HTML last, then validated again. A failed build/validation cannot replace
the served build. Refresh after completion, not during publication.

`-GodotPath` remains available with `-Builder Windows` for future upstream
testing. That path also stages and validates; on this machine it reproduced
the defect, exited 1 and left the good served PCK hash unchanged. It is not
the daily workaround.

## Local environment installed for this pass

WSL 2 was already available; no distro was installed. A dedicated Ubuntu
24.04 distribution was imported from Canonical's official WSL image. Its SHA256
was checked against Canonical's published SHA256SUMS:
`2a790896740b14d637dbdc583cce1ba081ac53b9e9cdb46dc09a2f73abbd9934`.

Distribution storage is at:
`C:/Users/Alucard7th/.codex/visualizations/2026/10/07/01a11499-fbf0-72a0-9e0f-f282670a771c/mobile-linux/distro`.
Keep this directory while using the builder. Inside that isolated distro,
the official Linux executable is installed at
`/opt/fishing-mobile/Godot_v4.7.2-stable_linux.x86_64`.
The mirror/cache/logs are under
`/root/.cache/fishing-mobile/64906215CB56FFF1/`.

For another workstation, import an Ubuntu WSL distro as
`FishingGameMobileBuild` (or pass `-WslDistribution <name>`), install the official
Godot 4.7.2 Linux executable at the above `/opt/fishing-mobile` path, make it
executable, and ensure `rsync` is installed. The helper copies the existing
Windows `APPDATA/Godot/export_templates/4.7.2.stable` templates into that distro.
No Windows feature toggles, Docker daemon or remote repository publication
were needed here.

## Checks run

- `validate_web_export.ps1 -Directory export`: rejected original zero-byte entry.
- `test_web_export_validation.ps1`: 6/6 (healthy, empty, wrong header, missing,
  out-of-bounds entry, stale HTML/WASM size); fixtures are synthetic, not patches
  to game output.
- `build_mobile_playtest.ps1 -Builder Windows`: reproduced defect, failed loudly,
  served SHA256 remained `D0203E6A3EBA590AB9DA0858EA0E71DAC1BD7DB6E1864F99404F3AF741CCD228`.
- Default `build_mobile_playtest.ps1`: two successful Linux builds, valid PCK.
- Actual browser startup of the normal regenerated `index.html`: beach and
  mobile controls rendered successfully; project-data startup error absent.
- `git diff --check`: passed.

Clean Linux import retains existing authored UID fallback warnings. No unrelated
resources were regenerated in the source project to silence them. This pass
does not claim a physical iPhone test.
