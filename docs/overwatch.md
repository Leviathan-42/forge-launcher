# Overwatch / Forge Wine handoff

This is a standalone handoff for the next agent. It captures the current Overwatch-on-Forge/Wine compatibility state, important paths, source changes, diagnostics, logs, and next steps.

## Goal

Make Overwatch launch and render under Forge Launcher/Wine through the legitimate Steam-authenticated path.

Current state: **not rendering yet**. Steam launches Overwatch, the real game/loader DLLs load, but the loader VM loops/faults before DXVK/D3D11 initialization.

## Hard constraints

Do **not** do any of the following:

- No anti-cheat evasion.
- No process hiding/spoofing.
- No Overwatch binary patching.
- No DLL injection into Overwatch.
- No forced loader-global value writes as a fix.
- No bypassing the legitimate Steam launch/auth path.

Allowed scope: Wine compatibility debugging/fixes only, with env-gated diagnostics.

Also:

- Always kill bounded tests before/after with `npm run kill`.
- Avoid unbounded Overwatch/Steam runs.
- If the user is actively using Steam or playing games, do **not** run `npm run kill`, do **not** launch the Steam helper, and do **not** touch Steam DevTools/prompt automation. Limit work to source, docs, static analysis, builds, and other non-launch tasks until the user confirms Steam is free.
- Avoid noisy `+virtual` unless specifically needed; `+seh,+loaddll` is usually enough.
- Preserve the exact `KiUserExceptionDispatcher` prologue.
- Keep temporary diagnostics env-gated or remove before final runtime.

## Repo / runtime paths

Launcher repo:

```txt
/Users/levi/Documents/forge-launcher
```

Main active bottle:

```txt
~/Wine/Bottles/default
```

CrossOver baseline clone:

```txt
~/Wine/Bottles/cx-ow-baseline
```

Active runtime:

```txt
~/Wine/Runtimes/forge-cx-wine-11-open-wow64
```

Active Wine source/build:

```txt
~/Downloads/crossover-sources-26.1.0/sources/wine
~/Downloads/crossover-sources-26.1.0/sources/wine/build-forge-cx64-wow64-open
```

Runtime files currently copied after latest build:

```txt
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/lib/wine/x86_64-unix/ntdll.so
~/Wine/Runtimes/forge-cx-wine-11-open-wow64/lib/wine/x86_64-windows/ntdll.dll
```

Important build note:

```bash
cd ~/Downloads/crossover-sources-26.1.0/sources/wine/build-forge-cx64-wow64-open
arch -x86_64 make dlls/ntdll/ntdll.so dlls/ntdll/x86_64-windows/ntdll.dll
```

PE ntdll target is:

```txt
dlls/ntdll/x86_64-windows/ntdll.dll
```

Do **not** try `dlls/ntdll/ntdll.dll`; there is no make rule for that.

Copy after build:

```bash
BUILD="$HOME/Downloads/crossover-sources-26.1.0/sources/wine/build-forge-cx64-wow64-open"
RUNTIME="$HOME/Wine/Runtimes/forge-cx-wine-11-open-wow64/lib/wine"
cp "$BUILD/dlls/ntdll/ntdll.so" "$RUNTIME/x86_64-unix/ntdll.so"
cp "$BUILD/dlls/ntdll/x86_64-windows/ntdll.dll" "$RUNTIME/x86_64-windows/ntdll.dll"
```

## Launcher-side test helper

Use:

```bash
scripts/overwatch-test-once.sh steam-dxvk 45
```

This helper:

- kills stale Wine/Steam processes first,
- stages DXVK into the Overwatch directory,
- launches via Steam with `-applaunch 2357570`,
- waits a bounded number of seconds,
- prints highlights,
- kills Wine/Steam afterwards.

Always run:

```bash
npm run kill
```

before and after manual tests.

Relevant committed launcher helper changes:

```txt
c1a1001 Make Overwatch test helper runtime-overridable
665ea1a Allow Overwatch worker thread test override
```

## Current useful test commands

Normal bounded Steam/DXVK test:

```bash
npm run kill
WINEDEBUG='fixme-all,+seh,+loaddll' scripts/overwatch-test-once.sh steam-dxvk 45
npm run kill
```

Global write-page guard:

```bash
npm run kill
FORGE_TRACE_OW_GLOBAL_GUARD=1 \
WINEDEBUG='fixme-all,+seh,+loaddll' \
scripts/overwatch-test-once.sh steam-dxvk 45
npm run kill
```

Global access guard, very noisy but useful:

```bash
npm run kill
FORGE_TRACE_OW_GLOBAL_ACCESS_GUARD=1 \
WINEDEBUG='fixme-all,+seh,+loaddll' \
scripts/overwatch-test-once.sh steam-dxvk 45
npm run kill
```

Filtered VM single-step after sentinel:

```bash
npm run kill
FORGE_TRACE_OW_VM_TF=1 \
FORGE_TRACE_OW_VM_TF_FILTERED=1 \
FORGE_TRACE_OW_DISPATCH_TF=1 \
FORGE_TRACE_OW_VM_TF_CAP=50000 \
FORGE_TRACE_OW_VM_TF_HEARTBEAT=5000 \
WINEDEBUG='fixme-all,+seh,+loaddll' \
scripts/overwatch-test-once.sh steam-dxvk 45
npm run kill
```

Pre-sentinel TF from global-guard page faults:

```bash
npm run kill
FORGE_TRACE_OW_GLOBAL_GUARD=1 \
FORGE_TRACE_OW_VM_TF=1 \
FORGE_TRACE_OW_VM_TF_FILTERED=1 \
FORGE_TRACE_OW_PRE_SENTINEL_TF=1 \
FORGE_TRACE_OW_VM_TF_CAP=140000 \
FORGE_TRACE_OW_VM_TF_HEARTBEAT=5000 \
WINEDEBUG='fixme-all,+seh,+loaddll' \
scripts/overwatch-test-once.sh steam-dxvk 75
npm run kill
```

Unwind trace:

```bash
npm run kill
FORGE_TRACE_OW_UNWIND=1 \
WINEDEBUG='fixme-all,+seh,+loaddll,+unwind' \
scripts/overwatch-test-once.sh steam-dxvk 45
npm run kill
```

## Logs

Logs are in:

```txt
~/Library/Application Support/com.forgelauncher.app/Logs
```

Most important logs:

```txt
manual-overwatch-steam-dxvk-bounded-20260618T230427Z.log
manual-overwatch-steam-dxvk-bounded-20260618T231847Z.log
manual-overwatch-steam-dxvk-bounded-20260619T051736Z.log
manual-overwatch-steam-dxvk-bounded-20260619T052220Z.log
manual-overwatch-steam-dxvk-bounded-20260619T054014Z.log
manual-overwatch-steam-dxvk-bounded-20260619T205422Z.log
manual-overwatch-steam-dxvk-bounded-20260619T210005Z.log
manual-overwatch-steam-dxvk-bounded-20260619T211608Z.log
```

HTML progress report also exists:

```txt
artifacts/overwatch-progress-report.html
```

## Current blocker summary

The Overwatch loader reaches a VM state where a global qword remains zero:

```txt
DAT_1804dbd48 == 0
```

That global is read and then decoded/xored with this constant:

```txt
0xbd40604461b42085
```

If the global stays zero, decoding yields the constant itself. That exact constant becomes bad `RDI`, and the loader repeatedly faults:

```txt
bad RDI:      0xbd40604461b42085
bad address: 0xbd40604461b420a5
bad fault:   Overwatch_loader.dll+0x605f8 / PE 0x1800605f8
```

Repeated bad fault example from `manual-overwatch-steam-dxvk-bounded-20260619T052220Z.log`:

```txt
Forge page fault rip=0x6fffe04f05f8 ... addr=0xbd40604461b420a5 ... rdi=0xbd40604461b42085
```

The loader thread then blocks the loader lock:

```txt
RtlpWaitForCriticalSection ... loader_section ... blocked by loader thread
```

No DXVK/D3D11 render entry has been reached yet:

```txt
DXVK: 0 hits
D3D11CreateDevice: 0 hits
CreateDXGIFactory: 0 hits
```

## Key Overwatch_loader addresses

Preferred image base:

```txt
0x180000000
```

Runtime base varies; examples:

```txt
0x6fffe0490000
0x6fffe0450000
```

Global under investigation:

```txt
DAT_1804dbd48
RVA: 0x004dbd48
```

If runtime base is `0x6fffe0490000`, runtime address is:

```txt
0x6fffe096bd48
```

Important addresses:

| Address | Meaning |
|---|---|
| `0x18031aac0` | Loader hook target for patched `dispatch_exception` |
| `0x180213d2a` | Sentinel caller area previously identified |
| `0x1800605f8` | Repeating bad VM fault site |
| `0x1800987d7` | Bad `RDI` loaded from VM stack path |
| `0x180112259` | Reads `DAT_1804dbd48` into `r9` |
| `0x180112260` | Stores `r9` to `[rsp+0x50]` |
| `0x1801127c9` | Bad value path from `[rsp+0x130]` |
| `0x1802fe667` | Expected writer: `mov [DAT_1804dbd48], rdi` |
| `0x1802863f0` | Helper called immediately before writer path |
| `0x18001cc20` | Helper called immediately before writer path |
| `0x1800421b0` | Helper called in writer path |

Writer instruction from objdump:

```asm
1802fe627: call 0x1800421b0
1802fe62c: mov  rdi, rax
1802fe63f: call 0x1802863f0
1802fe65f: call 0x18001cc20
1802fe664: xor  rdi, r13        ; r13 = 0xbd40604461b42085
1802fe667: mov  qword ptr [0x1804dbd48], rdi
```

Consumer instruction:

```asm
180112259: mov r9, qword ptr [0x1804dbd48]
180112260: mov qword ptr [rsp+0x50], r9
```

Note: Ghidra function boundaries are unreliable because this loader is heavily obfuscated. The writer at `0x1802fe667` is inside PE runtime-function range:

```txt
0x1802fa8c0 - 0x1802ffaa6
```

Earlier Ghidra analyses also named/labeled nearby obfuscated regions differently, including `FUN_1802cc7f0`. Prefer raw addresses / objdump / `.pdata` boundaries over Ghidra function names.

## Static call-chain clues

Potential writer path direct call chain observed by raw scan:

```txt
0x180118841 -> 0x1802a5c60
0x1802a693e -> 0x1802fa8c0
0x1802fa8c0 contains 0x1802fe667 writer
```

The call at `0x1802a693e` is inside function/runtime range:

```txt
0x1802a5c60 - 0x1802a6af3
```

Potential consumer path direct call chain:

```txt
0x1802047fe -> 0x18022309e
0x1802230cd -> 0x180111740
0x180111740 contains read/use path around 0x180112259
```

Also:

```txt
0x18010d757 -> 0x18011213c
```

Again, because the loader is obfuscated, these may be VM-generated/opaque-control paths rather than normal high-level calls.

## Dynamic findings so far

### What works

Confirmed earlier:

- Steam-auth launch path is preserved.
- Overwatch starts through Steam.
- Native `Overwatch.exe` loads.
- Native/app-local `dxgi.dll`, `d3d11.dll`, and `Overwatch_loader.dll` load.
- `Overwatch_loader.dll` patches PE ntdll `dispatch_exception` to loader hook target `0x18031aac0`.
- Steam/webhelper stability is mostly preserved by keeping Steam on safe builtin paths and handing game env separately.

### Ruled out / negative tests

These did **not** fix the loader loop:

- KUXD shadow-space experiments.
- Stock `int3` dispatcher behavior.
- CONTEXT home slots.
- Reporting helper changes.
- Nested exception chaining experiments.
- AMD64 flag experiments.
- XSTATE disable.
- Windows selectors / machine frame variants.
- `NtContinue` path changes.
- `SwitchToFiber` rollback.
- Worker counts `0`, `1`, `2`.
- `WINEESYNC=0`, `WINEMSYNC=0`.
- `ROSETTA_ADVERTISE_AVX=1`.
- CrossOver-like env subset.
- GPTK-like `SwitchToFiber` frame shape.
- Heap user-value path around the current helper call.

Important conclusion:

```txt
Bad RDI is not coming from Wine NtContinue.
No PE ntdll RtlLookupFunctionEntry / RtlVirtualUnwind* occurs between sentinel 0x907 and first bad-RDI fault.
```

### Dynamic helper / generated-stub finding

Recent helper-tail tracing around `0x1803282a0 -> 0x1803d616c` showed that the low-memory generated target called from the loader resolves through kernel32 into PE ntdll:

```txt
helper tail PE: 0x1803d616c
dynamic target: low generated stub around 0xbe15bb / 0xbe16bb
resolved API: ntdll!RtlFreeHeap
args: heap=0xdf0000, flags=0, ptr=NULL
return: 1
```

This moved the investigation forward but did **not** explain the missing global writer. The helper return is overwritten by later loader code, and `FORGE_TRACE_OW_HEAP_USER_VALUE=1` produced no matching `RtlGetUserInfoHeap` / `RtlSetUserValueHeap` evidence at the failing transition.

Key logs:

```txt
manual-overwatch-steam-dxvk-bounded-20260619T205422Z.log
manual-overwatch-steam-dxvk-bounded-20260619T210005Z.log
```

### State-machine trace finding

Latest focused state-machine tracing showed the loader spending substantial time in the selector loop:

```txt
state-machine range: 0x1801f34e0 - 0x1801f5120
selector slot:       [rsp+0x30]
progress slot:       [rsp+0x1a0]
later dispatcher:    0x18006ca80 - 0x180070330
```

The trace captured a repeating selector sequence. It did **not** enter the expected writer range `0x1802fa8c0-0x1802ffaa6` before the same bad VM fault.

Important transition from `manual-overwatch-steam-dxvk-bounded-20260619T211608Z.log`:

```txt
0x1801f4a62 writes q1a0 = 2
0x1801f4aa5 computes next selector rdx = 0x2512c487
0x1801f34e0 stores selector into [rsp+0x30]
0x1801f34e4 observes d30 = 0x2512c487
VM TF later reaches q1a0 = 3 around 0x1801f41fb / 0x1801f42c8
VM TF cap then hits near 0x18006e2a65 before the familiar bad-RDI fault
```

Practical result: the state sampler should default to change-oriented logging, with full comparator-walk logging only under `FORGE_TRACE_OW_VM_STATE_MACHINE_VERBOSE=1`, so one bounded run can see farther into the `q1a0 >= 2` path.

### SwitchToFiber / sentinel

The recurring sentinel exception:

```txt
addr=0x907
rcx=0x8ff
```

After GPTK-like `SwitchToFiber` call/ret-frame experiment, sentinel shape changed to e.g.:

```txt
rip=...b768 rsp=...dd0
```

But the loader VM still entered the same bad loop.

### Dispatcher-TF finding

Delivered CONTEXT TF produced zero useful steps, but arming TF on the dispatcher signal context worked and exposed the VM dataflow.

Useful env:

```txt
FORGE_TRACE_OW_VM_TF=1
FORGE_TRACE_OW_DISPATCH_TF=1
FORGE_TRACE_OW_VM_TF_FILTERED=1
```

TF showed:

```txt
RDI first becomes bad via mov rdi,[rsp+0x80] at Overwatch_loader+0x987d7.
Bad value first appears in RAX from [rsp+0x130] at Overwatch_loader+0x1127c9.
[rsp+0x130] becomes bad because [rsp+0x50] is zero.
[rsp+0x50] is loaded from DAT_1804dbd48 at 0x180112259 / 0x180112260.
```

### Global write guard

Env:

```txt
FORGE_TRACE_OW_GLOBAL_GUARD=1
```

This arms the page containing `DAT_1804dbd48` as read-only after `Overwatch_loader.dll` loads, logs writes, temporarily sets RW, single-steps, then rearms RO.

Log `manual-overwatch-steam-dxvk-bounded-20260618T231847Z.log`:

```txt
58 guarded-page writes
38 unique PE writers
0 writes touching DAT_1804dbd48 exactly
DAT remained 0
```

Guard arm example:

```txt
Forge OW global guard arm status=00000000 module=L"Overwatch_loader.dll" base=00006FFFE0490000 global=00006FFFE096BD48 page=00006FFFE096B000 size=1000 old=00000008 value=0000000000000000
```

Observed neighboring writers:

| Writer PE | Target RVA |
|---|---|
| `0x180288cd8` | `0x4dbd80` |
| `0x1802891d1` | `0x4dbd88` |
| `0x18028c25c` | `0x4dbd90` |
| `0x1802e3335` | `0x4db028` |
| `0x1802e333c` | `0x4db030` |
| `0x1802e35f6` | `0x4db030` |
| `0x180286570` | `0x4db038` |
| `0x1802850c9` | `0x4db380` |

No hit at:

```txt
0x1802fe667 -> DAT_1804dbd48
```

### Pre-sentinel TF from guard faults

Added env:

```txt
FORGE_TRACE_OW_PRE_SENTINEL_TF=1
```

This arms VM TF from the first guarded-page fault before the sentinel, instead of waiting for `addr=0x907`.

Log `manual-overwatch-steam-dxvk-bounded-20260619T051736Z.log`:

```txt
pre-sentinel TF arms: 4
VM TF cap reached: 3
parsed TF steps: 104
VM main range 0x180286c10-0x18028f138 hits: 57
writer chain 0x1802a5c60-0x1802a6b10 hits: 0
writer func 0x1802fa8c0-0x1802ffaa6 hits: 0
writer site 0x1802fe540-0x1802fe680 hits: 0
consumer range 0x180112240-0x180112800 hits: 0
bad-fault range 0x1800605d0-0x180060620 hits: 0 during that bounded run
```

Pre-sentinel TF showed the VM looping heavily in the `0x180286c10-0x18028f138` region after neighboring global writes, but still not reaching the expected `0x1802fe667` writer.

### Global access guard

Added env:

```txt
FORGE_TRACE_OW_GLOBAL_ACCESS_GUARD=1
```

This arms the guarded page as `PAGE_NOACCESS` / `PROT_NONE` so both reads and writes fault and get logged.

Log `manual-overwatch-steam-dxvk-bounded-20260619T052220Z.log`:

```txt
Overwatch.exe loaded: yes
Overwatch_loader.dll loaded: yes
global guard arm: 1
global guard access records: 9572
reads: 9514
writes: 58
unique PE accessors: 97
exact DAT_1804dbd48 accesses by exact-start address: 0
sentinel addr=0x907: 1
bad RDI fault loop: yes
loader_section timeout: yes
DXVK/D3D11: 0
```

Width-aware overlap check found only two 16-byte vector reads that overlapped the global bytes:

```txt
line 24247: read pe=0x18045214e rva=0x4dbd40 width=16 bytes=f30f6f6230660f7f
line 24759: read pe=0xffff9001a1fa214e rva=0x4dbd40 width=16 bytes=f30f6f6230660f7f
```

Still no exact scalar read at `0x180112259` in this access-guard run, even though the later bad loop reproduced. This may mean:

- the bad VM path consumed a value already staged on the VM stack before sentinel,
- or access guard perturbed timing/flow,
- or the `0x180112259` read path is reached in the dispatcher-TF run but not in this specific access-guard run,
- or the scalar read occurred while the page was temporarily readable and escaped guard due to the single-step/rearm timing.

Do not overinterpret this; the robust result is still: the global remains zero and the expected writer does not appear to run.

## Current Wine diagnostics implemented

Current modified Wine files include many earlier experiments. The most relevant active diagnostics are in:

```txt
dlls/ntdll/unix/signal_x86_64.c
dlls/ntdll/loader.c
dlls/ntdll/unwind.c
dlls/kernelbase/thread.c
```

### `dlls/ntdll/loader.c`

Current env-gated guard arming:

- `FORGE_TRACE_OW_GLOBAL_GUARD=1` -> `PAGE_READONLY` page guard for writes.
- `FORGE_TRACE_OW_GLOBAL_ACCESS_GUARD=1` -> `PAGE_NOACCESS` page guard for reads+writes.

It detects `Overwatch_loader.dll` and guards the page containing:

```txt
DllBase + 0x004dbd48
```

### `dlls/ntdll/unix/signal_x86_64.c`

Contains:

- sentinel detection for `addr=0x907`, `rcx=0x8ff`,
- bad VM fault detection for `addr=0xbd40604461b420a5`, `rdi=0xbd40604461b42085`,
- runtime loader base discovery via PE scan / PEB loader list / dispatcher-hook inference,
- filtered dispatcher-TF logging,
- global page write/access guard handling,
- pre-sentinel TF from guarded-page faults,
- expanded interesting PE ranges.

Important env vars:

```txt
FORGE_TRACE_OW_VM_TF
FORGE_TRACE_OW_DISPATCH_TF
FORGE_TRACE_OW_VM_TF_FILTERED
FORGE_TRACE_OW_VM_TF_CAP
FORGE_TRACE_OW_VM_TF_HEARTBEAT
FORGE_TRACE_OW_VM_TF_KEEP_BAD
FORGE_TRACE_OW_VM_CALLS
FORGE_TRACE_OW_VM_CALLS_CAP
FORGE_TRACE_OW_DYNAMIC_TARGET_BYTES
FORGE_TRACE_OW_DYNAMIC_STUB_TF
FORGE_TRACE_OW_VM_STATE_MACHINE
FORGE_TRACE_OW_VM_STATE_MACHINE_CAP
FORGE_TRACE_OW_VM_STATE_MACHINE_VERBOSE
FORGE_TRACE_OW_PRE_SENTINEL_TF
FORGE_TRACE_OW_GLOBAL_GUARD
FORGE_TRACE_OW_GLOBAL_ACCESS_GUARD
```

Current interesting ranges include:

```txt
0x180118820-0x180118870
0x1802a5c60-0x1802a6b10
0x1802a6900-0x1802a6960
0x1802b75d0-0x1802b7600
0x1802cc7f0-0x1802cc900
0x1802fa8c0-0x1802fa980
0x1802fe540-0x1802fe680
0x1802ff0f0-0x1802ff140
0x180112240-0x1801122a0
0x1801127b0-0x180112800
0x1800987c0-0x180098800
0x1800605d0-0x180060620
0x18006ca80-0x180070330
0x1801f34e0-0x1801f5120
```

The latest `ntdll.so` build also removed local C warnings from the diagnostic source; only the existing linker search-path warning for `/tmp/forge-wine-devel-lib` remained during rebuild.

### `dlls/ntdll/unwind.c`

Contains env-gated unwind tracing:

```txt
FORGE_TRACE_OW_UNWIND=1
```

Earlier important finding from this trace class:

```txt
No RtlLookupFunctionEntry / RtlVirtualUnwind* occurs between sentinel addr=0x907 and the first bad-RDI fault.
```

### `dlls/kernelbase/thread.c`

Contains the GPTK-like `SwitchToFiber` frame-shape experiment.

Result:

```txt
Changed sentinel RIP/RSP shape but did not fix VM loop.
```

## Other modified files / dirty state

Launcher repo is dirty with unrelated changes. Do not blindly commit everything.

Known modified launcher files from previous session state included:

```txt
Handoff.md
docs/ENV_VARS.md
docs/overwatch.md
macos/ForgeNative/Sources/ForgeNative/ForgeNativeApp.swift
scripts/build-forge-wine-from-sources.sh
scripts/overwatch-test-once.sh
scripts/test-steam-launch.sh
artifacts/overwatch-progress-report.html
```

Known modified Wine files from previous session state included:

```txt
dlls/kernelbase/debug.c
dlls/kernelbase/process.c
dlls/kernelbase/thread.c
dlls/ntdll/exception.c
dlls/ntdll/loader.c
dlls/ntdll/signal_x86_64.c
dlls/ntdll/unix/signal_x86_64.c
dlls/ntdll/unix/virtual.c
dlls/ntdll/unwind.c
dlls/win32u/class.c
dlls/win32u/window.c
dlls/win32u/winstation.c
```

Wine source trees are not git repos. If you need to preserve diffs, create patch artifacts manually under:

```txt
/Users/levi/Documents/forge-launcher/artifacts/wine-debug-patches/
```

Existing patch artifacts include older snapshots such as:

```txt
*-kernelbase-switchtofiber-frame.diff
*-ntdll-unwind-trace.diff
*-ntdll-unix-vm-tf-trace.diff
```

## Things that look tempting but are probably wrong

Do not directly set `DAT_1804dbd48` to a guessed value. That would be game-loader state tampering, not a Wine compatibility fix.

Do not patch `Overwatch_loader.dll` or `Overwatch.exe`.

Do not force writes into loader memory from outside.

Do not assume Ghidra function names are correct in obfuscated regions.

Do not assume `NtContinue` is the root cause; prior traces strongly argue against it.

Do not keep `PAGE_NOACCESS` access guard on during ordinary tests; it is very noisy and may perturb timing.

## Most likely next useful work

The likely issue is still a Wine compatibility mismatch that changes loader VM control flow or exception/dispatch timing so that the VM consumes the zero global before the initialization/writer path runs.

Next concrete steps, once Steam/game launches are allowed again:

1. Continue with the lean state-machine trace, not the verbose comparator trace.
   - Use `FORGE_TRACE_OW_VM_STATE_MACHINE=1`.
   - Leave `FORGE_TRACE_OW_VM_STATE_MACHINE_VERBOSE` unset unless you need individual comparator-ladder steps.
   - Increase `FORGE_TRACE_OW_VM_TF_CAP` enough to pass the `q1a0 = 2` and `q1a0 = 3` transitions.

2. Compare the path into the bad consumer chain versus expected writer chain.
   - Consumer chain candidates:
     ```txt
     0x1802047fe -> 0x18022309e -> 0x1802230cd -> 0x180111740 -> 0x180112259
     ```
   - Writer chain candidates:
     ```txt
     0x180118841 -> 0x1802a5c60 -> 0x1802a693e -> 0x1802fa8c0 -> 0x1802fe667
     ```

3. Add narrower, less perturbing TF or breakpoint-style diagnostics around those chains.
   - Log only when PE RIP enters these specific ranges.
   - Avoid page-wide access guard unless necessary.

4. Determine whether `0x1802fe667` is:
   - never reached,
   - reached only after the bad loop starts,
   - skipped due to an opaque branch decision,
   - blocked by an exception-dispatch/unwind difference,
   - or reached but stores something unexpected.

5. If a Wine-visible API/behavior controls the branch decision, compare with CrossOver/GPTK/Windows-like behavior for only that API.

6. If testing new Wine changes, use the normal bounded Steam-DXVK helper and check for:
   - `DXVK` log lines,
   - `D3D11CreateDevice`,
   - `CreateDXGIFactory`,
   - visible Overwatch window/render,
   - absence of loader-section stall.

7. Once rendering works:
   - remove or keep only env-gated diagnostics,
   - build clean runtime,
   - wire validated runtime/env profile into Forge Launcher.

## Useful one-off parsing snippets

Count important markers in a log:

```bash
python3 - <<'PY'
from pathlib import Path
log = Path('/path/to/log.log')
s = log.read_text(errors='replace')
for key in [
    'Overwatch.exe', 'Overwatch_loader.dll', 'global guard arm',
    'global guard access', 'addr=0x907', 'bd40604461b42085',
    'RtlpWaitForCriticalSection', 'DXVK', 'D3D11CreateDevice',
    'CreateDXGIFactory'
]:
    print(key, s.count(key))
PY
```

Parse guarded global accesses:

```bash
python3 - <<'PY'
import re, collections
from pathlib import Path
log = Path('/path/to/log.log')
lines = log.read_text(errors='replace').splitlines()
arm = [l for l in lines if 'global guard arm' in l][-1]
m = re.search(r'base=0*([0-9A-Fa-f]+).*?global=0*([0-9A-Fa-f]+)', arm)
base, glob = int(m.group(1),16), int(m.group(2),16)
pat = re.compile(r'global guard access=(\w+) .*?pe=(0x[0-9a-fA-F]+).*?addr=(0x[0-9a-fA-F]+).*?global_before=(0x[0-9a-fA-F]+).*?bytes=([0-9a-fA-F]+)')
recs = []
for i,l in enumerate(lines,1):
    mm = pat.search(l)
    if mm:
        recs.append((i, mm.group(1), int(mm.group(2),16), int(mm.group(3),16), int(mm.group(4),16), mm.group(5)))
print('records', len(recs), 'reads', sum(r[1]=='read' for r in recs), 'writes', sum(r[1]=='write' for r in recs))
print('exact-start DAT accesses', [r for r in recs if r[3] == glob][:10])
for (typ, pe, rva), count in collections.Counter((r[1], r[2], r[3]-base) for r in recs).most_common(30):
    print(typ, hex(pe), hex(rva), count)
PY
```

## Bottom line

The launcher/Steam/DXVK plumbing is mostly past the initial blockers. The remaining blocker is a specific `Overwatch_loader.dll` VM state problem:

```txt
DAT_1804dbd48 remains zero.
Expected writer 0x1802fe667 is not observed.
The VM later decodes zero into 0xbd40604461b42085 and faults repeatedly.
```

The next agent should focus on why the legitimate writer path is not executed under Wine, not on patching the global or game binaries.
