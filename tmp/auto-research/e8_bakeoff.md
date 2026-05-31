# E8 Bake-off (user-scoring table)

For each of 18 samples, side-by-side top picks from each baseline.
Score each cell as RELEVANT (R) / TANGENT (T) / NOISE (N) inline. Replace each cell's `_` with R/T/N.

## Per-sample table

### braidinfer/text/0
Activity: Empty-packet warmup as cure for kernel execution issues
Input snippet: Closed. bd 4e2m cure mechanism is now firmly settled: **empty-packet warmup (num_inst=0) is the minimum correct cure** at 10/10 PASS. In-kernel barrier alone is partial cure with new failure mode. Emp

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260526-053324-db9730 | REVIEW: bd 7jej single-GPU MoE unify plan — APPROVED_WITH_NOTES | _ |
| B0 cos top-3 #2 | — | (no hit) | _ |
| B0 cos top-3 #3 | — | (no hit) | _ |
| B1 LLM rerank #1 | kb-20260529-101811-b27ac8 | Documents watchdog fix for GPU wedges, directly relevant to bd 4e2m wedge context. | _ |
| B1 LLM rerank #2 | kb-20260529-101834-7f19aa | Details race hunt for multi-GPU wedges, relevant to bd 4e2m wedge investigation. | _ |
| B1 LLM rerank #3 | kb-20260530-172802-f2752a | Explicitly references bd-4e2m class wedges and standing instructions for handling them. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | — | (no pick; idents=[]) | _ |
| B4 symbol #2 | — | (no pick; idents=[]) | _ |
| B4 symbol #3 | — | (no pick; idents=[]) | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260529-112155-46e808 | 4n5 re-review APPROVED_WITH_NOTES: B1 fix (page_table_dirty on PagedKvState) is correct and race-free; B2 quant-eviction | _ |
| B7 adversarial #2 | — | (no hit) | _ |
| B7 adversarial #3 | — | (no hit) | _ |

### braidinfer/text/1
Activity: Decompose fused FFN for partial quantization
Input snippet: The FFN fused kernels combine RMSNorm + linear_proj + SiLU into one kernel. They read bf16 weights directly. To support quantized weights in these fused kernels, I'd need to add quantized variants of 

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260527-181640-a7540b | srg6 | _ |
| B0 cos top-3 #2 | kb-20260514-211710-d8d570 | env-var sprawl audit 2026-05-14 (braidinfer-wuf | _ |
| B0 cos top-3 #3 | — | (no hit) | _ |
| B1 LLM rerank #1 | kb-20260514-211710-d8d570 | Documents quantization constraints and megakernel path limitations for weights. | _ |
| B1 LLM rerank #2 | — | (no pick) | _ |
| B1 LLM rerank #3 | — | (no pick) | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260326-161334-a3678f | OLMoE GPU crash root causes and fixes: 1 matched=[w_gate, w_up, w_down] | _ |
| B4 symbol #2 | kb-20260514-212410-30bddf | wuf cleanup epic light review 2026-05-14 (sonnet, agent a20843a24): matched=[w_gate, w_up, w_down] | _ |
| B4 symbol #3 | kb-20260527-161040-8f2dcd | REVIEW: bd srg6 matched=[w_up] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260512-040353-98fe0a | 5ax MROPE multi-GPU non-determinism research: 3 untried fixes ranked by P(fix)*P(cheap). H1 -ffp-contract=off compile fl | _ |
| B7 adversarial #2 | kb-20260529-205833-8944af | BraidInfer Architecture: Persistent Megakernel RDNA3 LLM Inference Engine (gfx1100/RX 7900 XTX) | _ |
| B7 adversarial #3 | kb-20260325-094229-e78338 | BraidInfer Codebase Architecture Review — Full Expert Panel | _ |

### braidinfer/edit/0
Activity: HIP kernel dispatch loop synchronization and barrier handling
Input snippet: [EDIT /home/mcelrath/Projects/ai/braidinfer/kernels/megakernel.hip]         // OP_MOE_FFN manages its own blocks and grid.sync() internally         if (opcode == OP_MOE_FFN) {             op_moe_ffn(inst, grid);             // op_moe_ffn does its o

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260514-221012-850b5c | worktree archive 2026-05-14 (braidinfer-wuf | _ |
| B0 cos top-3 #2 | kb-20260529-125921-84cd28 | MULTI-GPU MoE DECODE DATAFLOW MAP (4n5 re-scope foundation) | _ |
| B0 cos top-3 #3 | kb-20260530-082230-357c19 | Multi-GPU MoE handoff is the sentinel/latency-hiding venue (NOT | _ |
| B1 LLM rerank #1 | kb-20260529-205833-8944af | Describes persistent_worker architecture and grid sync mechanisms in megakernel.hip. | _ |
| B1 LLM rerank #2 | kb-20260529-125921-84cd28 | Details persistent_worker entry point and block configuration in megakernel.hip. | _ |
| B1 LLM rerank #3 | kb-20260526-052112-b5ffed | Notes stale comments in megakernel.hip header regarding megakernel_f32 vs persistent_worker. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260527-171633-92ad68 | LIGHT REVIEW srg6 matched=[op_moe_ffn, OP_MOE_FFN, dump_instruction_output] | _ |
| B4 symbol #2 | kb-20260526-053324-db9730 | REVIEW: bd 7jej single-GPU MoE unify plan — APPROVED_WITH_NOTES matched=[op_moe_ffn, OP_MOE_FFN] | _ |
| B4 symbol #3 | kb-20260522-082450-25680e | bd 9gmh Phase 1 NaN-logits analysis (commit e9d339b, branch matched=[op_moe_ffn, OP_MOE_FFN] | _ |
| B5 beads #1 | braidinfer-pns | Unify all cooperative-grid launches into single persistent_worker matched=[megakernel.hip, kernels/megakernel.hip] | _ |
| B5 beads #2 | braidinfer-gs1 | perf: megakernel fused instructions Phase 3 — attack remaining grid.syncs matched=[megakernel.hip] | _ |
| B5 beads #3 | braidinfer-v8fh | block_alive_count co-residency diagnostic likely dead: atomicAdd to host-mapped UC broken on gfx11 (§11.20) matched=[megakernel.hip] | _ |
| B7 adversarial #1 | kb-20260514-221012-850b5c | worktree archive 2026-05-14 (braidinfer-wuf.6 cleanup). Removed worktrees + branches. UNMERGED branches archived here by | _ |
| B7 adversarial #2 | kb-20260529-101834-7f19aa | RACE HUNT: Braidinfer srg6.15 Multi-GPU Paged Decode Intermittent Wedge | _ |
| B7 adversarial #3 | kb-20260522-103625-77facd | bd 9gmh Phase 1 NaN FIXED (commit 98276be on finish-9gmh-phase1): multi-GPU MoE prefill produces coherent text. Root cau | _ |

### braidinfer/edit/1
Activity: HIP megakernel module structure and dependencies
Input snippet: [EDIT /home/mcelrath/Projects/ai/braidinfer/crates/braidinfer-runtime/src/megakernel/mod.rs] use braidinfer_core::types::DeviceId; use braidinfer_hip::memory::DeviceBuffer; use braidinfer_hip::module::Module; use braidinfer_hip::stream::Stream; use braidinfer_hip::HipResul

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260526-052112-b5ffed | braidinfer periodic architectural review (post unification arc | _ |
| B0 cos top-3 #2 | kb-20260325-094229-e78338 | BraidInfer Codebase Architecture Review — Full Expert Panel | _ |
| B0 cos top-3 #3 | kb-20260529-205833-8944af | BraidInfer Architecture: Persistent Megakernel RDNA3 LLM Inference | _ |
| B1 LLM rerank #1 | kb-20260529-205833-8944af | Describes persistent_worker entry point and launch bounds used in megakernel module. | _ |
| B1 LLM rerank #2 | kb-20260526-052112-b5ffed | Documents architectural drift regarding megakernel entry points and dead opcodes. | _ |
| B1 LLM rerank #3 | kb-20260527-181640-a7540b | Details implementation design for persistent_worker usage in paged prefill compilation. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260526-033506-59eda8 | expert-review APPROVED_WITH_NOTES for braidinfer-t8fl (CrossGpuStaging matched=[braidinfer_hip, DeviceId] | _ |
| B4 symbol #2 | kb-20260527-161040-8f2dcd | REVIEW: bd srg6 matched=[DeviceId, DeviceBuffer] | _ |
| B4 symbol #3 | kb-20260324-220438-d021b7 | Fixed three issues in braidinfer-runtime megakernel matched=[braidinfer_hip] | _ |
| B5 beads #1 | braidinfer-x7qp | INST_SIZE hardcoded in 2 places (C INST_SIZE_WORDS + Rust INST_SIZE) + prod_kernel_test silently red — add a drift guard matched=[mod.rs, megakernel/mod.rs] | _ |
| B5 beads #2 | braidinfer-t0i0 | Architect-A1/D1: delete k_trace_5ax_enabled() dead diagnostic gate matched=[mod.rs, megakernel/mod.rs] | _ |
| B5 beads #3 | braidinfer-pns | Unify all cooperative-grid launches into single persistent_worker matched=[mod.rs, megakernel/mod.rs] | _ |
| B7 adversarial #1 | kb-20260528-183355-e25513 | braidinfer GPU page-fault death triggers a DEFERRED MODE1 reset window that hangs subsequent HSA init for up to ~54min.  | _ |
| B7 adversarial #2 | kb-20260529-101834-7f19aa | RACE HUNT: Braidinfer srg6.15 Multi-GPU Paged Decode Intermittent Wedge | _ |
| B7 adversarial #3 | kb-20260514-221012-850b5c | worktree archive 2026-05-14 (braidinfer-wuf.6 cleanup). Removed worktrees + branches. UNMERGED branches archived here by | _ |

### braidinfer/read/0
Activity: Reading plan file
Input snippet: [READ /home/mcelrath/.claude/plans/PLAN-braidinfer.md]

**skip: no v2 queries**

### braidinfer/read/1
Activity: Rust build.rs HIP kernel flags and cache hints
Input snippet: [READ /home/mcelrath/Projects/ai/braidinfer/crates/braidinfer-hip/build.rs]

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260514-211710-d8d570 | env-var sprawl audit 2026-05-14 (braidinfer-wuf | _ |
| B0 cos top-3 #2 | kb-20260324-195934-e43d87 | HIP/hipcc compiler flags for FP precision control on RDNA3 (gfx1100): | _ |
| B0 cos top-3 #3 | kb-20260324-200158-7a0026 | Deterministic floating-point on AMD GPUs (HIP/ROCm): | _ |
| B1 LLM rerank #1 | kb-20260512-040353-98fe0a | Directly references build.rs lines and compiler flags relevant to current file. | _ |
| B1 LLM rerank #2 | kb-20260324-195934-e43d87 | Documents HIP compiler flags used in build.rs for FP precision control. | _ |
| B1 LLM rerank #3 | kb-20260529-205833-8944af | Describes megakernel architecture and launch bounds relevant to build configuration. | _ |
| B3 whole-file #1 | kb-20260529-205833-8944af | Describes persistent megakernel architecture compiled by this build script. | _ |
| B3 whole-file #2 | kb-20260512-040353-98fe0a | Discusses -ffp-contract flag used in this build script. | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260529-205833-8944af | BraidInfer Architecture: Persistent Megakernel RDNA3 LLM Inference matched=[BRAIDINFER_KV_LOAD_AUX, BRAIDINFER_USE_DOT2] | _ |
| B4 symbol #2 | kb-20260527-171633-92ad68 | LIGHT REVIEW srg6 matched=[PathBuf, unwrap_or_else] | _ |
| B4 symbol #3 | kb-20260527-161040-8f2dcd | REVIEW: bd srg6 matched=[PathBuf] | _ |
| B5 beads #1 | braidinfer-x7qp | INST_SIZE hardcoded in 2 places (C INST_SIZE_WORDS + Rust INST_SIZE) + prod_kernel_test silently red — add a drift guard matched=[build.rs, braidinfer-hip/build.rs] | _ |
| B5 beads #2 | braidinfer-000k | build.rs does not rerun-if-changed on kernels/rdna3/*.h headers — editing a header silently ships a STALE .hsaco matched=[build.rs, braidinfer-hip/build.rs] | _ |
| B5 beads #3 | braidinfer-pns | Unify all cooperative-grid launches into single persistent_worker matched=[build.rs, braidinfer-hip/build.rs] | _ |
| B7 adversarial #1 | kb-20260512-040353-98fe0a | 5ax MROPE multi-GPU non-determinism research: 3 untried fixes ranked by P(fix)*P(cheap). H1 -ffp-contract=off compile fl | _ |
| B7 adversarial #2 | kb-20260514-211710-d8d570 | env-var sprawl audit 2026-05-14 (braidinfer-wuf.3 prep). Per ENV_CONFIG.md mining session: (1) KV_DISPATCH_MODE=per_batc | _ |
| B7 adversarial #3 | kb-20260527-171633-92ad68 | LIGHT REVIEW srg6.5 (compile_prefill_paged_persistent): APPROVED_WITH_NOTES. Plan is implementable. Findings: (1) LfmCon | _ |

### exterior-algebra/text/0
Activity: Heartbeat probe misses dispatch-level wedge state
Input snippet: **Critical observation: 0033 heartbeat is NOT detecting the wedge.** Card 03 is in cold-start wedge state (hip-cold TIMEOUT) but `mes_wedged=0`, no `[mes-heartbeat]` dmesg lines after 40s+.  This empi

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260529-175545-78f82e | CORRECTION (supersedes the 'pivot' kb 20260529T195530Z-b160b6): 'ROCr | _ |
| B0 cos top-3 #2 | kb-20260530-233610-08705d | POSTMORTEM — 2026-05-30 5-card amdgpu cascade wedge (cold-start class) | _ |
| B0 cos top-3 #3 | kb-20260530-132534-a8a69d | MES SCH disasm forensic synthesis (Phase 5 of bd jhfb) — HEADLINE | _ |
| B1 LLM rerank #1 | kb-20260530-125956-d2df07 | Validates probe-safety and recommends Phase 1 timeout parameters for wedge detection. | _ |
| B1 LLM rerank #2 | kb-20260530-135025-5ab77b | Details implementation of mes_v11_0_probe_alive() primitive used in current wedge detection. | _ |
| B1 LLM rerank #3 | kb-20260531-130822-567e43 | Analyzes REMOVE_QUEUE root cause relevant to wedge detection and recovery mechanisms. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260530-135025-5ab77b | Phase 1 patch 0032 implemented: mes_v11_0_probe_alive() primitive + 2 matched=[QUERY_MES_STATUS] | _ |
| B4 symbol #2 | kb-20260531-105433-797784 | Expert review of bd exterior_algebra-2s26 matched=[QUERY_MES_STATUS] | _ |
| B4 symbol #3 | kb-20260530-125956-d2df07 | PHASE-0 PASS: empirical MES probe-safety validation (bd matched=[QUERY_MES_STATUS] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260530-125956-d2df07 | PHASE-0 PASS: empirical MES probe-safety validation (bd exterior_algebra-2s26.6, plan PLAN-amdgpu-mes-wedge-detect-recov | _ |
| B7 adversarial #2 | kb-20260530-140023-d1d8a2 | Phase 2 patch 0032.1 — MES wedge-detect WIRING at REMOVE_QUEUE completion (build-validated, NOT installed). | _ |
| B7 adversarial #3 | kb-20260530-145211-3a7fef | Phase 5 SAFE-MODE VALIDATION — partial PASS, design-foreclosure surfaced. | _ |

### exterior-algebra/text/1
Activity: AMDGPU health check and cold-start recovery validation
Input snippet: All 6 amdgpu cards healthy (including c3 which had been wedged earlier — fresh state after reload). 2 vfio-pci cards for am-rs (c6, c9). Patch-0029's `SET_SHADER_DEBUGGER` prime fired on all 6 = canon

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260530-141058-0b619e | Phase 3 of patch 0032 (MES wedge auto-recovery, gfx11) — IMPLEMENTATION | _ |
| B0 cos top-3 #2 | kb-20260530-145211-3a7fef | Phase 5 SAFE-MODE VALIDATION — partial PASS, design-foreclosure | _ |
| B0 cos top-3 #3 | kb-20260530-142420-89e5b9 | Phase 4 of linux-p2p amdgpu patch 0032 epic (bd exterior_algebra-2s26 | _ |
| B1 LLM rerank #1 | kb-20260526-144917-6393a8 | Validates Patch 0029, the active cold-start cure mentioned in agent activity. | _ |
| B1 LLM rerank #2 | kb-20260530-233610-08705d | Postmortem of recent cascade wedge; context for current healthy state and recovery. | _ |
| B1 LLM rerank #3 | kb-20260530-141058-0b619e | Details Patch 0032 Phase 3 implementation, relevant to ongoing wedge recovery work. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260526-144917-6393a8 | Patch 0029 (drm/amdgpu/mes: prime SET_SHADER_DEBUGGER at probe) matched=[SET_SHADER_DEBUGGER] | _ |
| B4 symbol #2 | kb-20260530-161215-3f837e | MES wedge patch 0032 Phase 5 — debugfs test-hook (0032 matched=[SET_SHADER_DEBUGGER] | _ |
| B4 symbol #3 | kb-20260526-071953-229d23 | exp22 rocmfp4_v2 PPL phase2 resume run status: script modified with matched=[SET_SHADER_DEBUGGER] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260526-144917-6393a8 | Patch 0029 (drm/amdgpu/mes: prime SET_SHADER_DEBUGGER at probe) validated against gfx11 cold-start race (bd-4e2m). Resul | _ |
| B7 adversarial #2 | kb-20260527-185034-cdf47d | exterior_algebra-p11.1 BLOCKED by exterior_algebra-alq.34 — IMU program_rlc_ram missing. | _ |
| B7 adversarial #3 | kb-20260524-135344-2a0043 | am-rs Phase 2 HW bringup blocker root cause: secondary GPUs bound to vfio-pci at boot are un-POSTed. BIOS POSTs only the | _ |

### exterior-algebra/edit/0
Activity: Bash script for ROCm GPU cold-load stress testing and dmesg fault detection
Input snippet: [EDIT /tmp/cold-load-cycle.sh] #!/bin/bash set -u N=${1:-30} ROCM_IDX=${2:-4} LOG=/tmp/cold-load-cycle.log HITS=/tmp/cold-load-cycle.hits  > $LOG > $HITS printf "starting %d cycles on ROCm%d\n" "$N" "$ROCM_IDX" 

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260530-233610-08705d | POSTMORTEM — 2026-05-30 5-card amdgpu cascade wedge (cold-start class) | _ |
| B0 cos top-3 #2 | kb-20260530-132534-a8a69d | MES SCH disasm forensic synthesis (Phase 5 of bd jhfb) — HEADLINE | _ |
| B0 cos top-3 #3 | kb-20260531-111651-90acb7 | Phase 2 validation run 2026-05-31: T1 PASS (v1/v2 both rc=1 for invalid | _ |
| B1 LLM rerank #1 | kb-20260529-185218-acbdac | Documents the exact script and bug2-diag fault being reproduced. | _ |
| B1 LLM rerank #2 | kb-20260527-142011-664e4b | Surveys approaches for bug 2 cold-start faults targeted by the script. | _ |
| B1 LLM rerank #3 | kb-20260529-201045-bbaab6 | Details fixes for GCVM faults relevant to the cold-start cycle testing. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260526-050946-dd740b | ROCmFP4 v2 HIP correctness + bench (phase4, exterior_algebra-a86 matched=[ROCM_IDX, HIP_VISIBLE_DEVICES] | _ |
| B4 symbol #2 | kb-20260526-050023-73d976 | ROCmFP4 v2 Phase 0 (exterior_algebra-a86 matched=[ROCM_IDX] | _ |
| B4 symbol #3 | kb-20260526-062552-297ca8 | ROCmFP4 Phase 1 v2 MSE evaluation on Qwen3 matched=[ROCM_IDX] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260523-152647-93be65 | D0.4 cold-start race script drafted at scripts/am_cold_start_race_test.py. 278 lines. Each trial is a fully separate sub | _ |
| B7 adversarial #2 | kb-20260526-144917-6393a8 | Patch 0029 (drm/amdgpu/mes: prime SET_SHADER_DEBUGGER at probe) validated against gfx11 cold-start race (bd-4e2m). Resul | _ |
| B7 adversarial #3 | kb-20260529-173930-cf7ec3 | Card 47:00.0 (gfx1100 RX 7900 XTX) wedged at llama-server model-load 2026-05-29 ~15:51-15:57. | _ |

### exterior-algebra/edit/1
Activity: amdgpu vm fault diagnostic dump
Input snippet: [EDIT /home/mcelrath/builds/linux-p2p/src/linux-7.0.9/drivers/gpu/drm/amd/amdgpu/gmc_v11_0.c] #include "gfxhub_v3_0.h" #include "gfxhub_v3_0_3.h" #include "gfxhub_v11_5_0.h"  static int amdgpu_diag_fault_dump; module_param_named(diag_fault_dump, amdgpu_diag_fault_dump, int,

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260529-185218-acbdac | bd-4e2m cid=5 cold-start fault FORENSIC CAPTURE 2026-05-29 via patch | _ |
| B0 cos top-3 #2 | kb-20260529-104144-056c01 | qm6 | _ |
| B0 cos top-3 #3 | kb-20260529-104838-68f8a4 | qm6 | _ |
| B1 LLM rerank #1 | kb-20260529-185218-acbdac | Documents the specific diag_fault_dump module parameter being added in the edit. | _ |
| B1 LLM rerank #2 | kb-20260529-202354-11da68 | Explains GCVM_L2_PROTECTION_FAULT_STATUS mechanics in gmc_v11_0.c, the file being edited. | _ |
| B1 LLM rerank #3 | kb-20260529-173930-cf7ec3 | Details fault signatures and VM stats issues relevant to the diagnostic dump feature. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260531-111744-f6b2be | 0033 matched=[amdgpu_diag_fault_dump, gfxhub_v3_0, gfxhub_v3_0_3, gfxhub_v11_5_0] | _ |
| B4 symbol #2 | kb-20260530-231850-d60d42 | GFX1100_ARCH matched=[gfxhub_v3_0, gfxhub_v3_0_3, gfxhub_v11_5_0] | _ |
| B4 symbol #3 | kb-20260529-185218-acbdac | bd-4e2m cid=5 cold-start fault FORENSIC CAPTURE 2026-05-29 via patch matched=[amdgpu_diag_fault_dump, diag_fault_dump] | _ |
| B5 beads #1 | exterior_algebra-qm6.4.6 | am-rs: implement GART aperture for GTT (proper fix for the ~114-page SYSTEM-PTE host-DMA cap) matched=[gmc_v11_0.c] | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260523-152647-93be65 | D0.4 cold-start race script drafted at scripts/am_cold_start_race_test.py. 278 lines. Each trial is a fully separate sub | _ |
| B7 adversarial #2 | kb-20260530-135025-5ab77b | Phase 1 patch 0032 implemented: mes_v11_0_probe_alive() primitive + 2 module params. | _ |
| B7 adversarial #3 | kb-20260526-144917-6393a8 | Patch 0029 (drm/amdgpu/mes: prime SET_SHADER_DEBUGGER at probe) validated against gfx11 cold-start race (bd-4e2m). Resul | _ |

### exterior-algebra/read/0
Activity: AMD GPU DRM driver file structure
Input snippet: [READ /home/mcelrath/builds/linux-p2p/src/linux-7.0.9/drivers/gpu/drm/amd/amdgpu/gfx_v11_0.c]

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260524-135334-4c18e3 | AM (tinygrad userspace AMD driver) GPU bringup sequence spec for Rust | _ |
| B0 cos top-3 #2 | kb-20260530-231850-d60d42 | GFX1100_ARCH | _ |
| B0 cos top-3 #3 | kb-20260524-154024-2f2e1c | FALSIFIED 2026-05-24: MES fallback firmware (gc_11_0_0_mes | _ |
| B1 LLM rerank #1 | kb-20260529-135444-972761 | Directly references gfx_v11_0.c line 2166 regarding scratch programming. | _ |
| B1 LLM rerank #2 | kb-20260524-154024-2f2e1c | Discusses gfx_v11_0 IP block initialization failure and firmware fallback. | _ |
| B1 LLM rerank #3 | kb-20260527-185034-cdf47d | References gfx_v11_0 init_hw calling imu_v11_0_program_rlc_ram. | _ |
| B3 whole-file #1 | — | n/a (too-large) | _ |
| B3 whole-file #2 | — | n/a (too-large) | _ |
| B3 whole-file #3 | — | n/a (too-large) | _ |
| B4 symbol #1 | kb-20260527-170426-d0d0a2 | exterior_algebra-p11 matched=[amdgpu_gfx] | _ |
| B4 symbol #2 | kb-20260524-135334-4c18e3 | AM (tinygrad userspace AMD driver) GPU bringup sequence spec for Rust matched=[amdgpu_gfx] | _ |
| B4 symbol #3 | kb-20260527-141245-230e72 | Expert review verdict (revision pass) on PLAN-am-rs-kiq-map-queues matched=[amdgpu_gfx] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260527-203300-62b303 | exterior_algebra-p11.1 trace-diff attempt: c6 was bound to amdgpu with dynamic_debug enabled. Reset c6 triggered runtime | _ |
| B7 adversarial #2 | kb-20260527-141732-4bc84c | gfx11 RELEASE_MEM PM4 packet requires 7 body dwords (8 total), not 6 (7 total). PACKET3(RELEASE_MEM, 6) header followed  | _ |
| B7 adversarial #3 | kb-20260528-073232-1a101e | exterior_algebra-p11.1 RESOLUTION: trace-diff settles it — amdgpu's PSP path on cold gfx11 is MES-FIRST. PATH 1 (avoid M | _ |

### exterior-algebra/read/1
Activity: AMDGPU MES driver file read
Input snippet: [READ /home/mcelrath/builds/linux-p2p/src/linux-7.0.9/drivers/gpu/drm/amd/amdgpu/mes_v11_0.c]

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260524-154024-2f2e1c | FALSIFIED 2026-05-24: MES fallback firmware (gc_11_0_0_mes | _ |
| B0 cos top-3 #2 | kb-20260530-161027-31d309 | am-rs MES firmware load: sign-extension bug in PRGRM_CNTR_START_HI | _ |
| B0 cos top-3 #3 | kb-20260530-161242-f4c866 | MES μC reset semantics across mode1_reset — Phase C of bd 9w7y | _ |
| B1 LLM rerank #1 | kb-20260530-161027-31d309 | Details MES firmware PC calculation bug fixed in mes_v11_0.c:1053. | _ |
| B1 LLM rerank #2 | kb-20260527-143202-74dafc | Explicitly references mes_v11_0.c:1053 logic for MES microcode start address. | _ |
| B1 LLM rerank #3 | kb-20260527-143146-b52527 | Describes MES KIQ startup stall requiring host register writes handled by driver. | _ |
| B3 whole-file #1 | — | n/a (too-large) | _ |
| B3 whole-file #2 | — | n/a (too-large) | _ |
| B3 whole-file #3 | — | n/a (too-large) | _ |
| B4 symbol #1 | kb-20260530-141058-0b619e | Phase 3 of patch 0032 (MES wedge auto-recovery, gfx11) — IMPLEMENTATION matched=[amdgpu_reset] | _ |
| B4 symbol #2 | kb-20260529-212434-f2d9fc | Finding not found: kb-20260529-212434-f2d9fc matched=[amdgpu_reset] | _ |
| B4 symbol #3 | kb-20260530-161138-9b61eb | MES μC reset semantics across mode1_reset — Phase C of bd 9w7y matched=[amdgpu_reset] | _ |
| B5 beads #1 | exterior_algebra-9w7y | Plan: MES SCH disasm — slot allocator + coop-bit clear + mode1_reset semantics matched=[amdgpu/mes_v11_0.c, /home/mcelrath/builds/linux-p2p/src/linux-7.0.9/drivers/gpu/drm/amd/amdgpu/mes_v11_0.c, mes_v11_0.c] | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260530-233610-08705d | POSTMORTEM — 2026-05-30 5-card amdgpu cascade wedge (cold-start class) | _ |
| B7 adversarial #2 | kb-20260530-132534-a8a69d | - kb-20260530-161019-4d0c0f  Phase A slot allocator (linear scan 3x5) - kb-20260530-161100-24ada3  Phase B coop-bit clea | _ |
| B7 adversarial #3 | kb-20260524-154024-2f2e1c | FALSIFIED 2026-05-24: MES fallback firmware (gc_11_0_0_mes.bin, the "legacy" SCH blob that amdgpu falls back to when gc_ | _ |

### llama-cpp/text/0
Activity: Exit code logic for stop signals and loop guards
Input snippet: All four cases correct: - User explicitly says good-night → allow stop (exit 0) - Normal task-complete response → allow stop (exit 0) - Hook already fired once (loop guard) → allow stop (exit 0) - Unp

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260530-161142-b7874b | llamacpp-upi0 (122B IQ4_NL garbage) PROVISIONAL RESOLUTION: same | _ |
| B0 cos top-3 #2 | kb-20260528-073938-b9fa95 | llamacpp-ed4u RESOLVED: FA-on garbage on 27B-Q6_K is spec-decode | _ |
| B0 cos top-3 #3 | kb-20260528-075016-caf83f | llamacpp-ed4u p_min sweep (27B-Q6_K, FA-on, --spec-type draft-mtp): | _ |
| B1 LLM rerank #1 | — | (no pick) | _ |
| B1 LLM rerank #2 | — | (no pick) | _ |
| B1 LLM rerank #3 | — | (no pick) | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | — | (no pick; idents=[]) | _ |
| B4 symbol #2 | — | (no pick; idents=[]) | _ |
| B4 symbol #3 | — | (no pick; idents=[]) | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260528-080248-1f09ea | llamacpp-ed4u verify-path analysis: common/sampling.cpp:622 does strict argmax comparison: 'if (draft[i] != id) break'.  | _ |
| B7 adversarial #2 | kb-20260528-082754-f62236 | llamacpp-ed4u FULLY RESOLVED: not a bug. | _ |
| B7 adversarial #3 | kb-20260528-075016-caf83f | llamacpp-ed4u p_min sweep (27B-Q6_K, FA-on, --spec-type draft-mtp): - 0.0:  garbage (cascading degeneration) - 0.1:  gar | _ |

### llama-cpp/text/1
Activity: Verify TP all-reduce and gated shard loops
Input snippet: Build still running (no binaries yet). Audit complete with all 26 items verified. Will resume when build agent completes.  **Audit results (already verified):** - All TP enum + CLI + weight shards + K

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260309-214018-b61ee2 | ## Expert Parallelism: Complete Implementation History and Performance | _ |
| B0 cos top-3 #2 | kb-20260529-020501-95e962 | EP-mode MTP regression localized: ggml_moe_fused multi-token (n_tokens | _ |
| B0 cos top-3 #3 | kb-20260324-122927-a31fbd | ## EP Prefill Optimization History: All Approaches Attempted | _ |
| B1 LLM rerank #1 | — | (no pick) | _ |
| B1 LLM rerank #2 | — | (no pick) | _ |
| B1 LLM rerank #3 | — | (no pick) | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260324-123037-7c381b | ## row_expert and expert_tp Split Mode Implementation Status (March 24, matched=[shard_attention_for_tp, wo_tp] | _ |
| B4 symbol #2 | kb-20260529-020501-95e962 | EP-mode MTP regression localized: ggml_moe_fused multi-token (n_tokens matched=[wo_tp, cparams.tensor_parallel] | _ |
| B4 symbol #3 | kb-20260307-004114-a9adb4 | ## TP Implementation State: mtp-qwen35 Branch Compilation Errors matched=[wo_tp, ssm_out_tp] | _ |
| B5 beads #1 | llamacpp-4s0.9 | Port SP (sequence-parallel) op pattern to gated_delta_net matched=[qwen35moe.cpp] | _ |
| B5 beads #2 | llamacpp-tt14 | MTP draft acceptance is 0% — graph correctness / sampling tuning matched=[qwen35moe.cpp] | _ |
| B5 beads #3 | llamacpp-f64 | hygiene: remove unused moe_n_embd at llama-model.cpp:5922 matched=[llama-model.cpp] | _ |
| B7 adversarial #1 | kb-20260528-081153-a9fb38 | llamacpp-ed4u ROOT CAUSE CANDIDATE: ctx_dft and ctx_tgt use DIFFERENT SSM math paths. | _ |
| B7 adversarial #2 | kb-20260529-020501-95e962 | EP-mode MTP regression localized: ggml_moe_fused multi-token (n_tokens > 1) path produces wrong activations on multi-GPU | _ |
| B7 adversarial #3 | kb-20260528-082754-f62236 | llamacpp-ed4u FULLY RESOLVED: not a bug. | _ |

### llama-cpp/edit/0
Activity: SDMA bandwidth gains limited by HSA fence serialization in MoE dispatch
Input snippet: [EDIT /home/mcelrath/.claude/plans/PLAN-topology-aware-sdma.md] | Q3.5-35B | 4-GPU `-sm expert` | 1664 | **floor 1960 / stretch 2100** | **floor 1.18× / stretch 1.26×** | | Q3.5-122B | 4-GPU | (measure first) | **floor +18%** | 1.18× | | Q3.5-3

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260228-100522-e27c19 | # MoE GPU Kernel Optimization: Comprehensive Analysis & Techniques | _ |
| B0 cos top-3 #2 | kb-20260302-130214-2fe790 | ## EP Optimization Landscape: Ideas, Profiling Data, and Implementation | _ |
| B0 cos top-3 #3 | kb-20260302-123411-7bf9b2 | ## EP Idea 2 Investigation: Peer-Write Down Kernel | _ |
| B1 LLM rerank #1 | kb-20260302-130214-2fe790 | Provides EP optimization landscape and bottleneck analysis relevant to SDMA performance planning. | _ |
| B1 LLM rerank #2 | kb-20260302-123411-7bf9b2 | Details EP pipeline structure and kernel flows, essential for understanding SDMA integration points. | _ |
| B1 LLM rerank #3 | kb-20260302-125602-bae487 | Analyzes specific EP optimization ideas and kernel structures relevant to SDMA implementation. | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | — | (no pick; idents=['exterior_algebra', 'peer_topology_sdma_vs_compute']) | _ |
| B4 symbol #2 | — | (no pick; idents=['exterior_algebra', 'peer_topology_sdma_vs_compute']) | _ |
| B4 symbol #3 | — | (no pick; idents=['exterior_algebra', 'peer_topology_sdma_vs_compute']) | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260517-165316-a2ba5d | TRACK L (#569) 4-GPU EP validation on master 95e137ea6, Qwen3.5-35B-A3B-Q4_K_M, ROCm4-7, llama-server one-shot. j3z cras | _ |
| B7 adversarial #2 | kb-20260528-080248-1f09ea | llamacpp-ed4u verify-path analysis: common/sampling.cpp:622 does strict argmax comparison: 'if (draft[i] != id) break'.  | _ |
| B7 adversarial #3 | — | (no hit) | _ |

### llama-cpp/edit/1
Activity: CUDA graph recapture and RDNA3 memory fence optimization
Input snippet: [EDIT /home/mcelrath/Projects/ai/llama.cpp/ggml/src/ggml-cuda/moe-ep.cu]     static bool ep_no_graph = (getenv("GGML_MOE_EP_GRAPH") == nullptr);     // Optional: drop the post-combine ep_sync_wait_kernel spin/acquire.     // Cross-stream cudaStreamWaitE

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260527-211333-208daf | llamacpp-ed4u: GPU work paused — host reboot required | _ |
| B0 cos top-3 #2 | — | (no hit) | _ |
| B0 cos top-3 #3 | — | (no hit) | _ |
| B1 LLM rerank #1 | — | (no pick) | _ |
| B1 LLM rerank #2 | — | (no pick) | _ |
| B1 LLM rerank #3 | — | (no pick) | _ |
| B3 whole-file #1 | — | (no pick) | _ |
| B3 whole-file #2 | — | (no pick) | _ |
| B3 whole-file #3 | — | (no pick) | _ |
| B4 symbol #1 | kb-20260319-115037-e2975b | Implementation review: ff5a526c6 — feat: slot/cancel endpoint + matched=[int64_t] | _ |
| B4 symbol #2 | kb-20260307-002340-90fae0 | TP+EP Implementation Status (mtp-qwen35 branch) matched=[int64_t] | _ |
| B4 symbol #3 | kb-20260517-165316-a2ba5d | TRACK L (#569) 4-GPU EP validation on master 95e137ea6, Qwen3 matched=[ep_no_graph] | _ |
| B5 beads #1 | llamacpp-ws2x | moe-ep ep_combine_uc Finegrained-fallback risk: SDMA from cached source if hipDeviceMallocUncached fails matched=[ggml-cuda/moe-ep.cu, moe-ep.cu] | _ |
| B5 beads #2 | llamacpp-m8p | Epic: single-decode-graph + host-mapped pointer-patching (eliminates vzd/dle/j3z by design) matched=[moe-ep.cu] | _ |
| B5 beads #3 | llamacpp-qqk | Diagnose why T3.2 SDMA dispatch path isn't firing at 8-GPU matched=[moe-ep.cu] | _ |
| B7 adversarial #1 | kb-20260309-223147-3bc971 | ## EP/TP P2P Status: Graph Capture, threadfence_system, SDMA Fixes (2026-03-09) | _ |
| B7 adversarial #2 | kb-20260306-232413-a81e11 | "gfx1100 __threadfence_system hang: HARDWARE limitation, NOT fixable in LLVM or ROCm device libs" | _ |
| B7 adversarial #3 | — | (no hit) | _ |

### llama-cpp/read/0
Activity: Kimi Linear Causal Conv1D State Layout
Input snippet: [READ /home/mcelrath/Projects/ai/llama.cpp/src/models/kimi-linear.cpp]

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260528-081153-a9fb38 | llamacpp-ed4u ROOT CAUSE CANDIDATE: ctx_dft and ctx_tgt use DIFFERENT | _ |
| B0 cos top-3 #2 | kb-20260315-212252-af84b0 | SGLang SSM/Mamba State Management During MTP Speculative Decoding | _ |
| B0 cos top-3 #3 | kb-20260312-101205-51fb8a | # Qwen35MOE Model: Complete Architecture & Graph Building | _ |
| B1 LLM rerank #1 | — | (no pick) | _ |
| B1 LLM rerank #2 | — | (no pick) | _ |
| B1 LLM rerank #3 | — | (no pick) | _ |
| B3 whole-file #1 | kb-20260528-081153-a9fb38 | SSM math path differences relevant to KDA implementation. | _ |
| B3 whole-file #2 | kb-20260327-192713-13bff5 | NaN root cause analysis relevant to attention/conv stability. | _ |
| B3 whole-file #3 | kb-20260327-140136-ab3525 | SP tensor descriptor issues relevant to graph construction. | _ |
| B4 symbol #1 | kb-20260319-115037-e2975b | Implementation review: ff5a526c6 — feat: slot/cancel endpoint + matched=[int64_t] | _ |
| B4 symbol #2 | kb-20260307-002340-90fae0 | TP+EP Implementation Status (mtp-qwen35 branch) matched=[int64_t] | _ |
| B4 symbol #3 | kb-20260307-004344-f8592b | Build Failure Investigation: llama matched=[ggml_tensor] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260528-081153-a9fb38 | llamacpp-ed4u ROOT CAUSE CANDIDATE: ctx_dft and ctx_tgt use DIFFERENT SSM math paths. | _ |
| B7 adversarial #2 | kb-20260527-211333-208daf | llamacpp-ed4u: GPU work paused — host reboot required. | _ |
| B7 adversarial #3 | kb-20260529-020501-95e962 | EP-mode MTP regression localized: ggml_moe_fused multi-token (n_tokens > 1) path produces wrong activations on multi-GPU | _ |

### llama-cpp/read/1
Activity: Qwen35 MTP layer validation and setup
Input snippet: [READ /home/mcelrath/Projects/ai/llama.cpp/src/models/qwen35.cpp]

|     | id | title/why | score |
|---|---|---|---|
| B0 cos top-3 #1 | kb-20260529-020501-95e962 | EP-mode MTP regression localized: ggml_moe_fused multi-token (n_tokens | _ |
| B0 cos top-3 #2 | kb-20260528-081153-a9fb38 | llamacpp-ed4u ROOT CAUSE CANDIDATE: ctx_dft and ctx_tgt use DIFFERENT | _ |
| B0 cos top-3 #3 | kb-20260225-101156-549199 | MTP (Multi-Token Prediction) support for Qwen3.5 models implemented in llama.cpp | _ |
| B1 LLM rerank #1 | kb-20260528-081153-a9fb38 | Explains MTP graph branching logic in delta-net-base.cpp relevant to qwen35.cpp. | _ |
| B1 LLM rerank #2 | kb-20260225-101156-549199 | Documents MTP implementation details and graph builder for Qwen3.5 models. | _ |
| B1 LLM rerank #3 | kb-20260308-073603-08dc48 | Details MTP fused decode implementation history and graph construction issues. | _ |
| B3 whole-file #1 | kb-20260528-081153-a9fb38 | Identifies different SSM math paths for draft/target contexts in Qwen3.5. | _ |
| B3 whole-file #2 | kb-20260529-020501-95e962 | Localizes MTP regression on multi-GPU EP, relevant to Qwen3.5 MTP graph. | _ |
| B3 whole-file #3 | kb-20260528-075834-8ea310 | Confirms spec-decode acceptance bug affects Qwen3.5-35B-A3B MoE models. | _ |
| B4 symbol #1 | kb-20260225-101156-549199 | MTP (Multi-Token Prediction) support for Qwen3.5 models implemented in llama.cpp matched=[nextn_predict_layers, llm_build_qwen35] | _ |
| B4 symbol #2 | kb-20260517-160651-259eec | smoke-ladder row8 PASS — Qwen3 matched=[nextn_predict_layers, llm_build_qwen35] | _ |
| B4 symbol #3 | kb-20260301-093523-d75443 | Expert review of MOE EP MMVQ fusion plan (melodic-wiggling-treehouse matched=[GGML_ASSERT] | _ |
| B5 beads #1 | — | (no pick) | _ |
| B5 beads #2 | — | (no pick) | _ |
| B5 beads #3 | — | (no pick) | _ |
| B7 adversarial #1 | kb-20260529-020501-95e962 | EP-mode MTP regression localized: ggml_moe_fused multi-token (n_tokens > 1) path produces wrong activations on multi-GPU | _ |
| B7 adversarial #2 | kb-20260528-081153-a9fb38 | llamacpp-ed4u ROOT CAUSE CANDIDATE: ctx_dft and ctx_tgt use DIFFERENT SSM math paths. | _ |
| B7 adversarial #3 | kb-20260528-075834-8ea310 | llamacpp-ed4u SCOPE EXPANDED: spec-decode acceptance bug affects 35B-A3B-Q4_K MoE TOO, not just 27B-Q6_K dense. | _ |

## Per-project meta (B6)

| project | meta_topic | meta-only kb_ids | score |
|---|---|---|---|
| braidinfer | Optimizing HIP kernel compilation and execution for quantized FFN models | kb-20260306-233635-189072, kb-20260325-201645-e7d772 | _ |
| exterior-algebra | AMDGPU driver debugging and ROCm GPU stability validation | kb-20260527-143104-6aa699, kb-20260527-181926-1f0e5f, kb-20260528-073232-1a101e, kb-20260528-181958-547045, kb-20260530-073200-69c195, kb-20260530-161019-4d0c0f, kb-20260530-161329-a474e3 | _ |
| llama-cpp | Optimizing MoE and MTP inference performance on RDNA3/HSA hardware | (0 — meta collapsed onto per-fire) | _ |

## Tally (to be filled after user scoring)

| baseline | R | T | N | total | precision = R/(R+T+N) |
|---|---|---|---|---|---|
| B0 | _ | _ | _ | _ | _ |
| B1 | _ | _ | _ | _ | _ |
| B3 | _ | _ | _ | _ | _ |
| B4 | _ | _ | _ | _ | _ |
| B5 | _ | _ | _ | _ | _ |
| B6 | _ | _ | _ | _ | _ |
| B7 | _ | _ | _ | _ | _ |

## Gate for E9

Plan requires >=70% precision on winner baseline. Lowest cell in the
Precision column wins/blocks E9.
