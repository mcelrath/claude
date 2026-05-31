# E6 results: meta-topic drift surfacing

One LLM call per project distills 6 per-fire topics into a meta-topic + 3 queries.
kb-ids found via meta-queries are compared against the union of per-fire kb-ids
(results_v2.jsonl kb_hits + results_e1.jsonl cosine/picked).

| project | meta_topic | meta_hits | new_vs_per_fire |
|---|---|---|---|
| braidinfer | Optimizing HIP kernel compilation and execution for quantized FFN models | 4 | 2 |
| exterior-algebra | AMDGPU driver debugging and ROCm GPU stability validation | 19 | 7 |
| llama-cpp | Optimizing MoE and MTP inference performance on RDNA3/HSA hardware | 4 | 0 |

## Qualitative: are new meta-topic entries drift-level?

### braidinfer
- meta_topic: Optimizing HIP kernel compilation and execution for quantized FFN models
- queries: ['HIP kernel synchronization barriers and dispatch loop optimization', 'Partial quantization strategies for fused FFN layers in HIP', 'Rust build.rs configuration for HIP kernel flags and cache hints']
- per-fire ids surfaced (union v2+e1): 34
- meta-only kb-ids (2): kb-20260306-233635-189072, kb-20260325-201645-e7d772

### exterior-algebra
- meta_topic: AMDGPU driver debugging and ROCm GPU stability validation
- queries: ['AMDGPU DRM driver architecture and MES subsystem internals', 'Diagnosing AMD GPU VM faults and heartbeat probe failures', 'ROCm GPU cold-start recovery and stress testing methodologies']
- per-fire ids surfaced (union v2+e1): 52
- meta-only kb-ids (7): kb-20260527-143104-6aa699, kb-20260527-181926-1f0e5f, kb-20260528-073232-1a101e, kb-20260528-181958-547045, kb-20260530-073200-69c195, kb-20260530-161019-4d0c0f, kb-20260530-161329-a474e3

### llama-cpp
- meta_topic: Optimizing MoE and MTP inference performance on RDNA3/HSA hardware
- queries: ['RDNA3 HSA fence serialization impact on MoE dispatch bandwidth', 'CUDA graph recapture strategies for RDNA3 memory optimization', 'Qwen35 MTP layer validation and TP all-reduce implementation']
- per-fire ids surfaced (union v2+e1): 20
- meta-only kb-ids: (none)
