# C# wrapper behavior probes

These source-only probes cover the C# motion, expression, parameter, and effect
wrappers with measured model behavior. They require an **isolated private copy**
of the `demo` Redot project containing the separately obtained Mao sample at
`res://addons/gd_cubism/example/res/live2d/mao_pro_jp/runtime/Mao.model3.json`.
The sample, native libraries, Mono editor, and build outputs are not part of
these tests. See [Linux source build](../../docs/build/linux.md#build-the-retained-c-demo)
for Redot 26.2 Mono, .NET 8, native add-on, and `NuGet.Config` setup. Use the
matching Redot Mono editor and a local project copy on either platform.

Set `PROJECT_DIR` to the private project copy and `REDOT_MONO_BIN` to that Mono
editor. From the repository root, before editor import (POSIX shell syntax):

```sh
python tests/csharp/prepare_event_fixture.py "$PROJECT_DIR"
cp tests/csharp/MotionProbe.cs tests/csharp/motion_probe.gd \
   tests/csharp/effects_probe.cs tests/csharp/effects_probe.gd "$PROJECT_DIR/"
dotnet build "$PROJECT_DIR/demo.csproj" --configuration Debug --no-incremental
"$REDOT_MONO_BIN" --headless --editor --path "$PROJECT_DIR" --import --quit-after 1000
"$REDOT_MONO_BIN" --headless --path "$PROJECT_DIR" \
   --script res://motion_probe.gd --quit-after 600
"$REDOT_MONO_BIN" --headless --path "$PROJECT_DIR" \
   --script res://effects_probe.gd --quit-after 600
```

Run the two scripts separately with an external wall-clock timeout (120 seconds
is ample for the observed Windows source runs). Require exit code 0, the
`MOTION_PROBE_PASS:` and `EFFECTS_PROBE_PASS:` markers respectively, and no
engine errors or unexplained warnings. The motion probe requires the add-on's
`CUBISM_MOTION_CUSTOMDATA` build option, enabled by default in `SConstruct`.

`prepare_event_fixture.py` changes **only the copied**
`motions/special_01.motion3.json` (TapBody/3): it inserts one Unicode `UserData`
event at 0.1 seconds and updates `Meta.UserDataCount` and
`Meta.TotalUserDataSize` using UTF-8 bytes. It refuses a second patch or an
unexpected existing event. Reimport after patching; do not modify or publish
the licensed source model. The probe checks event delivery and unsubscribe.

On the Windows 26.2 Mono **source project**, the prior audio/reentry baseline
passed. The motion probe passed 18 checks: smile `0→1→0`, angle range
`−25.910..0.004`, and one Unicode event. The effects probe passed target,
hit-area, breath, blink, and parameter checks: angle `+19.902/−19.895`, eye
target `+0.746/−0.746`, one hit enter/exit, breath `0..0.5`, and eye openness
`0..1`. Both probes also passed in saved Windows Mono debug and release
exports, with exit code 0 and no engine errors or warnings. These results do
not claim a Linux rerun or resolve the separate audio-probe shutdown warning.

The C# `StartMotion`/`StartMotionLoop` methods return `void` even though native
methods return motion handles; queue entries are placeholder Resources. These
probes therefore check queue count, numeric effect, completion, and signals,
not handle status. Breath and EyeBlink have no dedicated typed C# wrappers;
the effect probe creates native nodes and uses the inherited
`GDCubismEffectCS.Active` property while checking their parameter effects.
