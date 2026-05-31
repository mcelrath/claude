# E4 (symbol-anchored, NO LLM) summary

| label | idents | kb_picks | bd_picks | top idents |
| --- | --- | --- | --- | --- |
| braidinfer/text/0 | 0 | 0 | 0 |  |
| braidinfer/text/1 | 4 | 3 | 0 | w_gate, w_up, w_down, as_bf16_ptr |
| braidinfer/edit/0 | 5 | 3 | 0 | op_moe_ffn, dump_base, OP_MOE_FFN, OP_BARRIER, dump_instruction_output |
| braidinfer/edit/1 | 5 | 3 | 0 | braidinfer_hip, DeviceId, DeviceBuffer, HipResult, ModelConfig |
| braidinfer/read/0 | 0 | 0 | 0 |  |
| braidinfer/read/1 | 5 | 3 | 0 | BRAIDINFER_KV_LOAD_AUX, PathBuf, rocm_path, BRAIDINFER_USE_DOT2, unwrap_or_else |
| exterior-algebra/text/0 | 1 | 3 | 0 | QUERY_MES_STATUS |
| exterior-algebra/text/1 | 1 | 3 | 0 | SET_SHADER_DEBUGGER |
| exterior-algebra/edit/0 | 2 | 3 | 0 | ROCM_IDX, HIP_VISIBLE_DEVICES |
| exterior-algebra/edit/1 | 5 | 3 | 0 | amdgpu_diag_fault_dump, diag_fault_dump, gfxhub_v3_0, gfxhub_v3_0_3, gfxhub_v11_5_0 |
| exterior-algebra/read/0 | 2 | 3 | 0 | amdgpu_gfx, amdgpu_psp |
| exterior-algebra/read/1 | 3 | 3 | 0 | amdgpu_reset, soc15_common, gfx_v11_0 |
| llama-cpp/text/0 | 0 | 0 | 0 |  |
| llama-cpp/text/1 | 4 | 3 | 0 | shard_attention_for_tp, wo_tp, ssm_out_tp, cparams.tensor_parallel |
| llama-cpp/edit/0 | 2 | 0 | 0 | exterior_algebra, peer_topology_sdma_vs_compute |
| llama-cpp/edit/1 | 5 | 3 | 0 | int64_t, ep_no_graph, GGML_MOE_EP_NO_WAIT_KERNEL, ep_sync_wait_kernel, done_events |
| llama-cpp/read/0 | 5 | 3 | 0 | int64_t, ggml_tensor, conv_state_all, conv_state_size, element_size |
| llama-cpp/read/1 | 5 | 3 | 0 | GGML_ASSERT, nextn_predict_layers, embed_tokens, llm_build_qwen35, rope_sections |

**Medians**: idents/sample=3.5, kb_picks/sample=3.0, bd_picks/sample=0.0
