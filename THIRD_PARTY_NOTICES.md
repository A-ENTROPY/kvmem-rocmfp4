# 第三方组件与署名 / Third-Party Notices

本仓库是多个上游项目的集成。**所有核心算法与内核均来自下列项目**，本仓库只做了移植、集成与适配。

## 1. KVMem — 分层 KV 内存与检索式工作集

- 上游：https://github.com/kvmem/kvmem-llama.cpp （分支 `rocm-beta`）
- 论文：*KVMem: Virtualizing Million-Token Agent Workspaces on a Consumer GPU* — https://arxiv.org/abs/2609.04852
- 贡献者：Di Chai, Leye Wang, Zeshen Su, Zhiguo Xia, Zhihang Yu
- 本仓库包含的其源码：`kvmem/`、`src/adapter/`、`tools/`（KVMem 自有工具）、`patches/llama-kvmem-current.patch`
- 许可：上游 `rocm-beta` 树中未附 LICENSE 文件；上游说明为「llama.cpp remains under its upstream license. KVMem-qw3 source is Apache-2.0; this port should be treated the same unless a LICENSE file is added to this tree.」
- 引用：
  ```bibtex
  @misc{chai2026kvmem,
    title         = {{KVMem}: Virtualizing Million-Token Agent Workspaces on a Consumer {GPU}},
    author        = {Di Chai and Leye Wang and Zeshen Su and Zhiguo Xia and Zhihang Yu},
    year          = {2026},
    eprint        = {2609.04852},
    archivePrefix = {arXiv},
    primaryClass  = {cs.LG},
    url           = {https://arxiv.org/abs/2609.04852}
  }
  ```

## 2. ROCmFP4 — AMD 专用 4-bit 量化格式与 HIP 内核

- 上游（格式与内核原始作者）：https://github.com/charlie12345/rocmfp4-llama （MIT，作者 charlie12345）
- 相关仓库：https://github.com/charlie12345/rocmfp4 · https://github.com/charlie12345/ROCmFPX
- 新增格式：`GGML_TYPE_Q4_0_ROCMFP4 = 100`（双标度 UE4M3，4.50 bpw）、`GGML_TYPE_Q4_0_ROCMFP4_FAST = 101`（单标度，4.25 bpw）
- 本仓库**不包含**其源码，而是在构建时由 `scripts/fetch-llama-and-patch.ps1` 拉取

## 3. walcz-de/llama.cpp-ROCmFP4 — 本仓库使用的基线

- 上游：https://github.com/walcz-de/llama.cpp-ROCmFP4
- 使用的分支：`rocmfp4-pre-3466812d-20260902`
- 说明：该分支把 charlie12345 的 ROCmFP4 格式与内核**移植到较新的 llama.cpp 上游基础上**（post MMQ refactor）。其上游基线 commit `3466812d`（2026-09-01）与 KVMem 钉定的 `b81c99b`（2026-09-02）仅相差 8 个提交，因此 KVMem 补丁可零冲突套用。
- 该仓库自身的 README 声明其格式与 CPU 参考实现来自 charlie12345/ROCmFPX（MIT），并附有 `THIRD_PARTY_NOTICES.md`

## 4. DFlash2 — 块扩散并行草稿推测解码

- 作者：Inco AI（2026-08-18 发布）— https://inco.ai/blog/dflash2/
- 原始 DFlash：UCSD Z Lab — https://github.com/z-lab/dflash
- 上游 llama.cpp 实现：PR #27342 `spec : add DFlash2 support (local convolution + candidate selector)`（已合并）
- 草稿模型：`incoai/Qwen3.8-27B-DFlash2-GGUF`（HuggingFace）
- 本仓库**不包含**其代码，构建时随基线一并获得

## 5. llama.cpp

- 上游：https://github.com/ggml-org/llama.cpp （MIT）
- 本仓库对其的修改全部通过补丁表达：`patches/llama-kvmem-current.patch`（来自 KVMem）

## 6. Qwen3.8-27B 相关模型

- 主模型（官方配方）：ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF
- 视觉投影器：HermiHg/Qwen3.8-27B-mmproj-Q5_K-MIX-GGUF
- DFlash2 草稿模型：incoai/Qwen3.8-27B-DFlash2-GGUF
- **本仓库不分发任何模型权重**，请遵守各模型自身的许可条款

---

## 本仓库自行编写的部分

- `patches/dflash2-kvmem-tools.diff` —— 让 KVMem 的推测解码回路支持独立草稿模型（DFlash2）
- `scripts/fetch-llama-and-patch.ps1` / `scripts/build-windows.bat` / `scripts/package-runtime.ps1` —— 获取基线、编译、打包
- `tools/` 下 4 个文件的改动（已包含在仓库工作树中，并以补丁形式留档）
- `docs/`、`README.md`、`start-kvmem.bat`（发布包启动器）

以上以 MIT 发布（见 `LICENSE`）。
