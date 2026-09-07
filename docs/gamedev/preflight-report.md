# Redot Cubism plan review

Date: 2026-09-07. Scope: revise the existing plan without implementing or publishing the addon.

The source review supports retaining GDCubism as the basis for a Redot C++ GDExtension. The original plan combined a plausible port with substantial new features and contained build-order and API-contract errors. Those have been corrected in [the canonical plan](../../redot_live2d_cubism_importer_codex_plan.md). The planning review is complete; a working port is not yet demonstrated.

**Next-action recommendation: PREFLIGHT_BLOCKED** for SDK-dependent implementation and release qualification until the runtime/SDK evidence below is available. The intended approach remains adapting the pinned GDCubism source. Future authorized SDK-free source preparation and the binding/API spike can proceed independently of SDK provisioning. This status does not mean Redot is known to be incompatible.

## Research questions

| Question | Result | Plan destination |
|---|---|---|
| Is there local source to port? | Directory initially contained only the 94 KB plan; pinned upstream source was inspected remotely. | PR 0/1 preserve planning files when importing source |
| Are version/descriptor assumptions valid? | Pinned source records 26.2.0 / Godot 4.5.2; Redot descriptor options exist. Binary load remains untested. | Section 3, PR 2A |
| Can upstream build against R5 before migration? | No: it calls APIs removed in R5. | Section 12, PR 2B |
| Does multi-part importer selection exist? | Yes in selection/importability checks; discovery and UID paths still need an end-to-end stock-editor test. | Section 9.1, PR 2A/5 |
| Do path arrays guarantee reimport/export? | No: raw invalidation, real resource edges and export injection are separate. | Sections 9.7/17.5 |
| Can export callbacks guarantee cancellation? | Public callbacks return void. Use a checked entry point until a stock-menu failure path is proved. | Section 17.5, PR 9 |
| Is runtime behavior fully specified? | Naming, awaits, Layout, strings, blink RNG/ownership and parameter-write lifetime needed correction. | Sections 8/10/11/14 |
| Is a usable port coupled to optional features? | Previously yes. Native port and P0/P1/P2 now have separate gates. | Sections 5/18 |
| Is redistribution settled? | No product-specific classification or Core/model permission established. | Section 4, PR 12 |

## Main revisions

1. PR 2A proves binding/editor APIs without Core. PR 2B uses matched R5 immediately, including required compile substitutions. PR 3 handles lifecycle behavior. R1 is historical context, not a temporary dependency.
2. The first native port preserves class names, effect nodes, shader paths and the legacy assets API through rendered/animated/exported desktop smoke tests. The importer and controller follow. Timeline conversion, full editor dock, macOS, C# and mobile do not block P0.
3. PR 9 runs directly after PR 5. Dependency fingerprints, reverse index, bounded rescan, reimport scheduling and missing-file recovery are explicit. Checked export validates reachable models/shaders/raw files before promoting output.
4. Runtime contracts now preserve Layout and stable UTF-8 buffers, model-local mutable state, Node pause/reentry, terminal handles, one-step manual writes and authored blink ownership. Per-model seeded blink requires instance-owned timing.
5. The API uses playback_process_mode, maps motion IDs to valid AnimationLibrary keys, returns a speech handle and rejects script-bearing texture/audio formats before loading.
6. Public source/addon packages and private fixture-bearing test exports have distinct audit rules. Upstream reports motivate coverage; they do not prove Redot defects or fixes.

## Source ledger

The Framework tag 5-r.5 resolves to 145155d2c5bdd8d23475cef9cc3ab46d3220190c. The selected GDCubism tree pins upstream godot-cpp gitlink fbbf9ec4efd8f1055d00edb8d926eef8ba4c2cce. SDK archive/Core hashes and compiler versions remain required inputs.

| ID | Source and identity | Evidence / intended use |
|---|---|---|
| SRC-001 | [Redot version](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/version.py); 4f5b14abade2239104847d03d8f9056e4467cfcd | 26.2.0 stable, Godot 4.5.2 compatibility. PR 0 identity. |
| SRC-002 | [Descriptor loader](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/core/extension/gdextension_library_loader.cpp); 4f5b14abade2239104847d03d8f9056e4467cfcd | Redot minimum and disable_godot_checks supported. PR 2A. |
| SRC-003 | [Importer selection](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/core/io/resource_importer.cpp); 4f5b14abade2239104847d03d8f9056e4467cfcd | Suffix matching exists; selection uses priority. PR 2A/5. |
| SRC-004 | [Editor filesystem](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/editor/file_system/editor_file_system.cpp); 4f5b14abade2239104847d03d8f9056e4467cfcd | Discovery/import paths differ; metadata alone is no dependency watch. PR 5. |
| SRC-005 | [Import plugin API](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/doc/classes/EditorImportPlugin.xml); 4f5b14abade2239104847d03d8f9056e4467cfcd | gen_files is output; threaded default false; import order/version callbacks. PR 5. |
| SRC-006 | [Export plugin API](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/doc/classes/EditorExportPlugin.xml); 4f5b14abade2239104847d03d8f9056e4467cfcd | Void callbacks do not expose general abort return. PR 9. |
| SRC-007 | [AnimationLibrary keys](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/scene/resources/animation_library.cpp); 4f5b14abade2239104847d03d8f9056e4467cfcd | Entry names reject slash, colon, comma and left bracket. PR 6B. |
| SRC-008 | [Binding initialization](https://github.com/Redot-Engine/redot-cpp/blob/598ec78e86b2c240a023f6de13daba70f7de8610/src/godot.cpp); 598ec78e86b2c240a023f6de13daba70f7de8610 | Requires get_redot_version; checks generated API version. PR 2A. |
| SRC-009 | [Binding build options](https://github.com/Redot-Engine/redot-cpp/blob/598ec78e86b2c240a023f6de13daba70f7de8610/tools/godotcpp.py); 598ec78e86b2c240a023f6de13daba70f7de8610 | custom_api_file supported; precision defaults single. PR 0/2A. |
| SRC-010 | [Binding Windows flags](https://github.com/Redot-Engine/redot-cpp/blob/598ec78e86b2c240a023f6de13daba70f7de8610/tools/windows.py); 598ec78e86b2c240a023f6de13daba70f7de8610 | CRT flags selected through debug_crt/use_static_cpp. PR 2B. |
| SRC-011 | [Binding Linux flags](https://github.com/Redot-Engine/redot-cpp/blob/598ec78e86b2c240a023f6de13daba70f7de8610/tools/linux.py); 598ec78e86b2c240a023f6de13daba70f7de8610 | PIC, platform architecture and static C++ runtime settings. PR 2B. |
| SRC-012 | [Upstream SConstruct](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/SConstruct); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | max SDK discovery, implicit Framework override and fixed Core selection. PR 2B. |
| SRC-013 | [Upstream build docs](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/docs-src/modules/ROOT/pages/en/build.adoc); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Historical SDK example uses 5-r.1. PR 0. |
| SRC-014 | [Upstream native playback](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/src/private/internal_cubism_user_model.cpp); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Uses removed loop setters and expression priority API. PR 2B. |
| SRC-015 | [Upstream registration](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/src/register_types.cpp); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Framework initialization already extension-wide. PR 3. |
| SRC-016 | [Upstream runtime node](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/src/gd_cubism_user_model.cpp); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Regular process/ready callbacks drive playback; mutable callback data. PR 3. |
| SRC-017 | [Upstream canvas renderer](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/src/private/internal_cubism_renderer_2d.cpp); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Direct mesh updates; DBL_MIN maxima and GPU stride assumptions. PR 4. |
| SRC-018 | [Upstream motion loader](https://github.com/MizunagiKB/gd_cubism/blob/3aaa3c9001808732c40aa3fa07460a95125d9ccc/src/loaders/gd_cubism_motion_loader.cpp); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Parameter-only conversion approximates curves, steps and inverse steps. PR 6B. |
| SRC-019 | [R5 motion interface](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/Motion/ACubismMotion.hpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | SetLoop/GetLoop and callback custom-data APIs. PR 2B. |
| SRC-020 | [R5 expression manager](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/Motion/CubismExpressionMotionManager.hpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | Inherits motion queue manager; no expression priority API. PR 2B. |
| SRC-021 | [R5 motion queue](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/Motion/CubismMotionQueueManager.hpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | StartMotion takes motion and autoDelete. PR 2B. |
| SRC-022 | [R5 model API](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/Model/CubismModel.hpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | GetDrawableBlendModeType and precise color/culling APIs. PR 2B/4. |
| SRC-023 | [R5 settings interface](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/ICubismModelSetting.hpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | GetLayoutMap required; returned char pointers need stable storage. PR 5. |
| SRC-024 | [R5 layout parsing](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/CubismModelSettingJson.cpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | Preserve Layout through model settings adapter. PR 5. |
| SRC-025 | [R5 blink ownership](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/Motion/CubismEyeBlinkUpdater.cpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | Procedural blink conditional on motion updates. PR 6A. |
| SRC-026 | [R5 blink randomness](https://github.com/Live2D/CubismNativeFramework/blob/145155d2c5bdd8d23475cef9cc3ab46d3220190c/src/Effect/CubismEyeBlink.cpp); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | Uses process-global rand; per-model determinism needs adapter. PR 6A. |
| SRC-027 | [Redot resource loading](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/scene/resources/resource_format_text.cpp); 4f5b14abade2239104847d03d8f9056e4467cfcd | Texture/audio hints permit script-bearing resource loading. PR 5. |
| SRC-028 | [Redot Node lifecycle](https://github.com/Redot-Engine/redot-engine/blob/4f5b14abade2239104847d03d8f9056e4467cfcd/scene/main/node.cpp); 4f5b14abade2239104847d03d8f9056e4467cfcd | READY once by default; detach/reentry needs policy. PR 3. |
| SRC-029 | [Cubism R5 release](https://github.com/Live2D/CubismNativeFramework/releases/tag/5-r.5); 145155d2c5bdd8d23475cef9cc3ab46d3220190c | Removes APIs used upstream; official renderer fixes do not certify custom renderer. PR 2B. |
| SRC-030 | [GDCubism v0.9.1 release](https://github.com/MizunagiKB/gd_cubism/releases/tag/v0.9.1); 3aaa3c9001808732c40aa3fa07460a95125d9ccc | Identifiable released source baseline with mask/editor fixes. PR 1. |
| SRC-031 | [Upstream issue reports](https://github.com/MizunagiKB/gd_cubism/issues); 2026-09-07 | Plan issue identities verified; all open; no Redot reproductions. Regression triage. |
| SRC-032 | [Live2D publication terms](https://www.live2d.com/en/sdk/license/); 2026-09-07 | Publication route varies by product; Core and model rights remain separate. PR 12. |
| SRC-033 | [Expandable application terms](https://www.live2d.com/en/sdk/license/expandable/); 2026-09-07 | Covered applications require review/agreement; addon classification unresolved. PR 12. |
| SRC-034 | [TrueGDCubism alternative](https://github.com/VulpxVenandi25/TrueGDCubism/tree/b62554beecad41cd893f12be833c135b9fc008ed); b62554beecad41cd893f12be833c135b9fc008ed | Godot 4.3+ fork retaining upstream binding gitlink; no verified Redot/R5 advantage. Baseline choice. |
| SRC-035 | [Live2D community directory](https://docs.live2d.com/en/cubism-sdk-tutorials/community-sdk/); 2026-09-07; older compatibility listing | Lists community GDCubism; no Live2D maintenance/current compatibility guarantee. Identity cross-check. |
| SRC-036 | [Cubism runtime export formats](https://docs.live2d.com/en/cubism-editor-manual/export-moc3-motion3-files/); 2026-09-07 documentation | Exports model and motion data for embedded applications. Section 8.5 / PR 7 cues. |
| SRC-037 | [Editor motion-sync baking](https://docs.live2d.com/en/cubism-editor-manual/motion-sync-bake/); 2026-09-07 documentation | Bakes audio-driven mouth motion into timeline keyframes. Section 8.5 / PR 7 cues. |
| SRC-038 | [Native WAV lip sync](https://docs.live2d.com/en/cubism-sdk-tutorials/native-lipsync-from-wav-native/); 2026-09-07 documentation | Optional Sound association and volume-driven mouth movement. Section 8.5 / PR 7 cues. |
| SRC-039 | [Record parameter animation](https://docs.live2d.com/en/cubism-editor-manual/recording-parameters/); 2026-09-07 documentation | Records parameter operations and generates animation in Cubism Editor. Section 8.5 / PR 7 cues. |
| SRC-040 | [Author scenes with audio](https://docs.live2d.com/en/cubism-editor-manual/generating-scene-from-audio-file/); 2026-09-07 documentation | Uses audio in animation authoring; runtime coordinates separate exported assets. Section 8.5 / PR 7 cues. |

The [workbook](source-of-truth.xlsx) records creators, licenses, dispositions and adaptation notes. Native/library sources were read, not built or executed. Source licenses do not confer proprietary Core/model redistribution rights.

Follow-up clarification: the intended workflow is authored/recorded animation exported from Cubism Editor and assigned to game cues, with recorded voice audio or without audio. Section 8.5 now explicitly covers motion-only cues, voice/motion coordination, authored/baked mouth curves versus envelope lip sync, and audio-clock alignment/drift tests. The ordinary motion playback path remains separate from runtime MotionSync integration.

## Alternatives and maintenance

GDCubism v0.9.1 remains the baseline because its source and native integration are identifiable and the requested plan already builds on it. TrueGDCubism at b62554beecad41cd893f12be833c135b9fc008ed was inspected as an alternative: it identifies itself as a Godot 4.3+ fork and retains the upstream godot-cpp gitlink. The inspected artifact provides no demonstrated Redot/R5 compatibility advantage, so it is not selected as the new baseline. This does not reject all of its changes; targeted patch reuse needs diff/provenance review.

An engine module or fresh integration is not selected: no minimal GDExtension blocker has been reproduced, and either expands the port before native parity exists. Live2D's community directory confirms identity but distinguishes community maintenance from Live2D maintenance; its older Godot listing is not current compatibility proof.

## Query and access ledger

| Surface / query | Outcome |
|---|---|
| Local folder, plan, workspace rules and tooling README | Planning-only folder; REDOT_BIN/GODOT_BIN/SDK/model variables unset. Workspace config names a Windows editor. |
| Memory registry quick search for cubism/redot/port | No relevant hits; no memory-derived compatibility claims. |
| Public GitHub exact commits, tree, releases and R5 tag | Source identities, API files and upstream gitlink inspected. |
| Upstream #7, #93, #104, #126, #127, #142, #156–159, #161–166 | Listed identities verified, all open in accessed snapshot. No issue reproduced here. |
| Search: redot cubism plugin/fork, redot-cubism/redot_cubism | No verified ready-made Redot port identified in returned results; not an exhaustive absence claim. |
| Search: Godot Cubism GDExtension alternative | Original integration, TrueGDCubism and broader VTubing projects surfaced; bounded alternative review used TrueGDCubism. |
| Godot Asset Library query/direct filtered page | No usable registry result; direct access failed. No marketplace support claim made. |
| Live2D community SDK directory | Opened; points to community integration with old-version caveat. |
| Official publication/expandable terms | Opened; product-specific release gate retained. No fee/classification conclusion invented. |
| Shell curl for public raw source | No file obtained under restricted network; switched to GitHub/web read tools. |
| Old editor_file_system.cpp path | 404; resolved to editor/file_system/editor_file_system.cpp at the same commit. |
| Binding extension_api.json via GitHub/web | Oversized response rejected; web reported over 4 MiB limit. Generate/inspect the exact target API in PR 2A. |
| Mounted Windows editor --version | Failed: cannot execute binary file on Linux. No usable redot/godot/wine command found. |

## Adversarial audit

One read-only critic independently reviewed interface and internal-consistency risks while the main reviewer checked pinned source. The main reviewer also performed SELF_REVIEW passes for compatibility, licensing and execution scope. Agreement is not runtime evidence.

| ID | Lens / challenged claim | Evidence | Result and resolution |
|---|---|---|---|
| AUD-001 | Compatibility: unchanged source builds with R5 before migration | SRC-014/019–022/029 | FAIL in original; fixed sequence/substitution table in PR 2B. |
| AUD-002 | Engine API: path metadata/void callbacks guarantee valid import/export | SRC-004–006 | FAIL in original; explicit invalidation and checked export; RSK-003/004 remain open. |
| AUD-003 | Interface: settings adapter preserves complete model data | SRC-023/024; critic | FAIL: Layout and pointer lifetime omitted. Added interface/storage/layout tests. |
| AUD-004 | Animation: unconditional blink/per-model seed match native behavior | SRC-025/026; critic | FAIL: motion ownership/global RNG. Added timing adapter and independence tests. |
| AUD-005 | Security: contained typed resource loads cannot execute scripts | SRC-027; critic | FAIL: post-load checks too late. Added pre-load allowlist. |
| AUD-006 | Lifecycle: exit disposal plus ready-only load supports reentry | SRC-028; critic | FAIL: READY may not repeat. Added reentry contract/test. |
| AUD-007 | Consistency: private-model export smoke excludes its only real fixture | Original plan Sections 19/20; critic | FAIL: separated private test/public artifact audit modes. |
| AUD-008 | API: setter/await/animation-key contracts are already usable | SRC-007 and original plan; main/critic | FAIL: specified one-step writes, speech handles, key mapping and pause separation. |
| AUD-009 | SELF_REVIEW compatibility: source pins prove native parity | Local version failure, oversized API fetch | BLOCKED: actual ABI/render/export proof absent; no platform support advertised. |
| AUD-010 | SELF_REVIEW rights: MIT source settles native addon publication | SRC-032/033 | BLOCKED: product-specific Core/model/publication decision required before release. |
| AUD-011 | SELF_REVIEW scope: this request requires implementing/publishing code | User request and directory | PASS: only planning artifacts changed. |

Rejected hypotheses: descriptor options are not absent (SRC-002); multi-part suffixes are not categorically unsupported (SRC-003/004); Framework initialization is not per-model (SRC-015). Preserve the supported behavior and verify its boundaries.

## Open gates

| ID | Area | Missing evidence / next step | Blocks |
|---|---|---|---|
| RSK-001 | Runtime/ABI | Windows engine cannot execute on this Linux host. Provide native Windows/Linux runners and engine/template hashes. | PR 2A/2B |
| RSK-002 | SDK/fixtures | No configured R5 SDK or licensed model root. Provision lawful exact package/model and record hashes/permissions. | PR 2B |
| RSK-003 | Importer | Complete suffix discovery and UID restart untested. Run synthetic stock-editor spike; explicit import action is provisional fallback. | PR 5 |
| RSK-004 | Export | Stock Export-menu abort not established. Use checked export action; prove UI hook or document limitation. | PR 9 |
| RSK-005 | Publication | Addon/Core/model rights and product classification unresolved. Record specific publication decision and approved artifacts. | PR 12 |
| RSK-006 | Rendering | Canvas renderer parity/model-feature limits untested. Qualify gl_compatibility then Forward+ with oracle captures. | PR 4 |
| RSK-007 | Build identity | API JSON too large for connector; toolchain/Core hashes unpinned. Generate target API; pin precision, interface, toolchain and SDK. | PR 0/2A |

## Revision validation

The entire original plan was read. Edited Markdown is checked for local links, balanced code fences, section structure, milestone ordering and duplicated test IDs. The critic's material findings were incorporated. The workbook indexes evidence/decisions/risks without fabricated build or runtime PASS entries.

No game/plugin source was changed, no candidate repository code was executed, and no proprietary SDK/model was downloaded. Native compilation, actual engine execution, graphical parity, import/reimport and exported-game verification remain future gates because executable hosts and configured SDK/model prerequisites are absent.
