# KVMem + ROCmFP4 + DFlash2 for AMD

**在 AMD Radeon（gfx1100 / gfx1151）上跑满 256K 上下文的 Qwen3.8-27B，并用 DFlash2 把解码速度推到 48–53 tok/s。**

> 把三件事合进一个 llama.cpp 构建：**[KVMem](https://github.com/kvmem/kvmem-llama.cpp)** 的分层 KV（显存恒定、上下文可到 256K）、**[ROCmFP4](https://github.com/charlie12345/rocmfp4-llama)** 的 AMD 专用 4-bit 量化格式（类型 100/101），以及 **[DFlash2](https://inco.ai/blog/dflash2/)** 的块扩散并行草稿推测解码。
>
> One llama.cpp build that combines three things: **KVMem** tiered KV (constant VRAM, up to 256K context), **ROCmFP4** AMD-specific 4-bit formats (ggml types 100/101), and **DFlash2** block-diffusion speculative decoding.

📦 **开箱即用的预编译包：[v1.0.0 Release](https://github.com/A-ENTROPY/kvmem-rocmfp4/releases/tag/v1.0.0)** —— Windows x64 + ROCm 7.2，已含运行库（229 MB），无需自己编译。

---

## ✨ 为什么值得用 / Why

| 痛点 | 这个构建怎么解 |
|---|---|
| 27B 模型 + 256K 上下文，KV 缓存爆显存 | **KVMem** 把 GPU KV 压成固定预算（本机 256K 配置下约 2.4 GB），历史存主机内存、按查询检索回显存 |
| AMD 卡缺少高效 4-bit 内核 | **ROCmFP4**：`Q4_0_ROCMFP4`(4.50 bpw) / `Q4_0_ROCMFP4_FAST`(4.25 bpw)，带 HIP 向量点积 / MMQ / FlashAttention 内核 |
| 原生解码速度上不去 | **DFlash2** 一次验证一个草稿块，实测 **+24%**（首个长生成 38.8 → 48.1 tok/s） |
| 上游 llama.cpp 只认类型 0–42，加载不了 FP4 模型 | 本仓库的构建已含类型 100/101，可直接加载 |

**一句话**：这是目前能在消费级 AMD 卡上同时拿到「超长上下文 + FP4 量化 + 推测解码」的一条完整路径。

---

## 📊 实测性能 / Benchmarks

**测试平台**：AMD Radeon **RX 7900 XTX**（gfx1100，RDNA3，24 GB）· 24 核 / 32 线程 · 64 GB DDR4-3200 · Windows · ROCm 7.2（HIP 7.2.60201）

**模型**：`Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf`（13.75 GB）+ DFlash2 草稿 `Qwen3.8-27B-DFlash2-Q4_K_M.gguf`（1.06 GB）

**配置**：`-c 32768`、`--kvmem --kvmem-budget 8192 --kvmem-gen-reserve 4096`、`--kv-dtype q8_0`、greedy

| 配置 | 首次长生成 (≈470 tok) | 上下文增长后 (≈410 tok) |
|---|---:|---:|
| 原生解码（`--spec-type none`） | 38.8 tok/s | 38.9 tok/s |
| **+ DFlash2 (`--spec-draft-n-max 3`)** | **48.1 tok/s（+24%）** | 40.5 tok/s（+4%） |
| + DFlash2 (`--spec-draft-n-max 5`) | 45.8 tok/s | 36.7 tok/s |

- **峰值**：短上下文下 3 秒窗口瞬时速率最高观测到 **53.0 tok/s**
- **草稿数用 3 最好**；调到 5 或 7 反而更慢（草稿接受率下降 37% → 19%，验证开销抵消收益）
- 数字为逐请求归因到服务端 `eval time` 计时行，非平均值套算

> 另：**256K 上下文本身几乎没有速度惩罚**（同条件下 32K 时 51.5 vs 256K 时 52.0 tok/s），这正是 KVMem 的核心价值。

---

## 🚀 快速开始 / Quick Start

### 方式一：下载预编译包（推荐）

**三步，零参数：**

1. 到 [Releases](../../releases) 下载 `kvmem-rocmfp4-gfx1100-windows-rocm7.2-selfcontained.zip` 并解压
2. 把下载好的 `.gguf` 模型**丢进包内的 `models\` 目录**（下载清单见 [`models\把模型放这里.md`](release/models/把模型放这里.md)）
3. **双击 `start-kvmem.bat`**

脚本会**自动扫描 `models\`**，识别出「主模型 / DFlash2 草稿 / 视觉投影器」，自动组合出最优配置并启动：

```
============================================================
   KVMem + ROCmFP4 + DFlash2
============================================================
   模型目录: ...\models

   扫描结果:
      [视觉投影  ] mmproj-Qwen3.8-27B-BF16.gguf  (888.0 MB)  <- 选用
      [DFlash2草稿] Qwen3.8-27B-DFlash2-Q4_K_M.gguf  (1.06 GB)  <- 选用
      [主模型    ] Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf  (13.75 GB)  <- 选用

   将使用:
      主模型   : Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf
      草稿模型 : Qwen3.8-27B-DFlash2-Q4_K_M.gguf
      加速方式 : DFlash2（推荐，实测 +24%）
      上下文   : 262144   检索窗口: 36864   单轮上限: 32768

   界面: http://127.0.0.1:18200/
```

浏览器打开 `http://127.0.0.1:18200/` 即可。包内已含 ROCm 运行库（`amdhip64_7.dll` / `hipblas` / `rocblas`），**无需自行安装 ROCm**。

**没放模型会怎样？** 脚本会打印需要下载哪个文件、放哪里、下载链接是什么，然后退出——不会给你一堆看不懂的报错。

**智能降级**：只有主模型没有 DFlash2 草稿时，会自动改用主模型自带的 MTP；两者都没有就自动关闭推测解码，并提示你去下载草稿模型。

**可选参数**（都不需要就能跑）：

```powershell
.\start-kvmem.bat -List                    # 只列出识别结果，不启动
.\start-kvmem.bat -DryRun                  # 只打印将执行的命令
.\start-kvmem.bat -ModelsDir "D:\models"   # 模型放在别处
.\start-kvmem.bat -Spec none               # 关闭推测解码
.\start-kvmem.bat -Context 32768           # 小上下文，省显存
```

### 方式二：从源码编译

见 [`docs/BUILD.md`](docs/BUILD.md)。三步：

```powershell
# 1) 取 ROCmFP4 基线（与 KVMem 钉定版本仅差 8 个提交，补丁零冲突）
.\scripts\fetch-llama-and-patch.ps1
# 2) 编译（MSVC 14.44 + Ninja + ROCm 7.2，目标 gfx1100）
.\scripts\build-windows.bat
# 3) 打包
.\scripts\package-runtime.ps1
```

---

## 🧩 三个组件是怎么合的 / How it fits together

```
上游 llama.cpp（ROCmFP4 移植分支 rocmfp4-pre-3466812d-20260902）
        │  基线 3466812d 与 KVMem 钉定的 b81c99b 仅差 8 个提交
        ├─ + KVMem 补丁（patches/llama-kvmem-current.patch）   → 零冲突
        │     └─ 分层 KV：GPU 块-槽池 = budget + gen_reserve，历史落主机内存
        ├─ + ROCmFP4（该分支自带）                             → 类型 100/101 可加载
        └─ + DFlash2（该基线已含上游 PR #27342）               → --spec-type draft-dflash
              └─ 本仓库的改动：让 KVMem 的推测解码回路支持独立草稿模型
```

**本仓库在 KVMem 侧的关键改动**（4 个文件，见 `patches/dflash2-kvmem-tools.diff`）：

| 改动 | 说明 |
|---|---|
| 放开 `--spec-type` 白名单 | 原来硬编码只认 `draft-mtp \| none`，现支持 `draft-dflash` |
| 新增 `-md, --model-draft PATH` | 指定独立草稿模型 GGUF |
| `kvmem_spec_opts.spec_type` 可配置 | 原来硬编码 `COMMON_SPECULATIVE_TYPE_DRAFT_MTP` |
| **`kvmem_draft_rewind()` 统一回滚** | MTP 走 KVMem 逻辑接口；DFlash 走标准 `llama_memory_seq_rm` |
| 5 处 MTP 专用逻辑加 DFlash 分支 | 检查点 carry、行同步校验、草稿 KV 截断等 |

> 💡 **最后一个改动是让 DFlash2 真正跑通的关键**：KVMem 原本用自家的逻辑移除接口回滚草稿 KV，
> 但 DFlash 的草稿上下文是**原生 KV**（未经 KVMem 管理），必须换成标准序列 API 才能正确回滚。
> 否则草稿位置会持续超出目标，报 `llama_decode(ctx_dft) failed ... X <= Y`。

---

## ⚙️ 两种加速方式怎么选 / MTP vs DFlash2

| | MTP（`draft-mtp`） | DFlash2（`draft-dflash`） |
|---|---|---|
| 草稿来源 | 主模型自带的 nextn 头 | **独立草稿模型 GGUF** |
| 适用模型 | 文件名带 `-mtp` 的模型 | 任意 Qwen3.8-27B 目标模型 |
| 本机实测 | IQ3_S + MTP2 = 37.5 tok/s | FP4 + DFlash2(n=3) = 48.1 tok/s |
| 额外显存 | 很小（共享槽池） | 草稿模型 ~1 GB + 其 KV |

**结论**：模型带 MTP 头就用 MTP；想用 FP4 量化或追求更高速度就用 DFlash2。

⚠️ 实测 **DFlash2 配 IQ3_S（GDN 混合架构）反而慢到 12.6 tok/s**，故推荐两种组合：
`FP4 模型 + DFlash2`（速度优先）与 `IQ3_S + MTP2`（长上下文优先）。

---

## ⚠️ 两个会让速度腰斩的坑 / Two traps that halve your speed

实测（RX 7900 XTX，DFlash2 n=3）：

| 参数 | 错误值 | 后果 | 正确做法 |
|---|---|---|---|
| `--threads` | `0`（用满 32 线程） | 51.5 → **26.6** tok/s（-48%） | **不加 / 留空**（用 llama.cpp 默认） |
| `--flash-attn` | `on` | 52.0 → **29.3** tok/s（-44%） | **不加 / 留空**（auto） |

两项叠加能把 50 tok/s 打到 13 tok/s。GPU 全卸载时，空转的 CPU 线程会争抢采样与图调度，反而拖慢。

---

## 📋 测试过的模型 / Tested models

**模型不随本仓库分发**，请自行下载：

| 用途 | 模型 | 大小 | 来源 |
|---|---|---|---|
| ★ 推荐主模型（FP4） | `Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf` | 13.75 GB | ROCmFP4 量化产物（见 [ROCmFP4 仓库](https://github.com/charlie12345/rocmfp4-llama)说明） |
| KVMem 官方配方主模型 | `Qwen3.8-27B-GSQ-RCO-IQ3_S-mtp.gguf` | 11.29 GB | [ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF](https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF) |
| ★ DFlash2 草稿模型 | `Qwen3.8-27B-DFlash2-Q4_K_M.gguf` | 1.06 GB | [incoai/Qwen3.8-27B-DFlash2-GGUF](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF) |
| 视觉投影（可选） | `mmproj-Qwen3.8-27B-BF16.gguf` | 0.87 GB | [HermiHg/Qwen3.8-27B-mmproj-Q5_K-MIX-GGUF](https://huggingface.co/HermiHg/Qwen3.8-27B-mmproj-Q5_K-MIX-GGUF) |

以上均已实测可用。其他同架构的 Qwen3.8-27B 变体理论上兼容，但未逐一测试。

---

## 🖥️ 支持范围 / Support

| 项 | 状态 |
|---|---|
| GPU 架构 | **gfx1100（RX 7900 XTX）已实测**；构建脚本支持 gfx1030 / gfx1100 / gfx1151 / gfx1200 |
| 操作系统 | Windows x64（预编译包）；Linux 可参照 `scripts/` 自行编译 |
| ROCm | 7.2（HIP 7.2.60201）实测 |
| 多 GPU | ❌ KVMem 不支持 |
| NVMe offload | ❌ 当前 Windows 构建未启用 |

> ⚠️ RDNA3.5（Strix Halo / gfx1151）是 ROCmFP4 的官方调优目标，本仓库的 gfx1100 路径属社区验证方向。
> 两者都应能工作，但本文性能数字**仅对 gfx1100 有效**。

---

## 📌 已知限制 / Known limitations

1. **单轮生成受 `--kvmem-gen-reserve` 限制**（含思考内容）。要写长文就把它调大（用显存换长度）。
2. **DFlash2 收益随上下文增长而衰减**（首轮 +24% → 上下文变长后 +4%）。
3. **DFlash2 与 GDN 混合模型（如 IQ3_S）不合**，会显著变慢。
4. 草稿数不是越大越好，`3` 是本机最佳。
5. `--threads 0` / `--flash-attn on` 会让速度腰斩，务必留空。
6. ROCmFP4 在 gfx1151 上的路径未经本仓库验证。

---

## 📄 许可证与致谢 / License & Credits

本仓库是以下项目的集成与移植，**先向原作者致敬**：

- **[KVMem](https://github.com/kvmem/kvmem-llama.cpp)** —— 分层 KV 内存与检索式工作集（[论文 arXiv:2609.04852](https://arxiv.org/abs/2609.04852)）
- **[ROCmFP4 / charlie12345](https://github.com/charlie12345/rocmfp4-llama)** —— AMD 专用 4-bit 量化格式与 HIP 内核
- **[walcz-de/llama.cpp-ROCmFP4](https://github.com/walcz-de/llama.cpp-ROCmFP4)** —— 把 ROCmFP4 移植到新版上游基础上（本仓库的基线来源）
- **[DFlash2 / Inco AI](https://inco.ai/blog/dflash2/)** —— 块扩散并行草稿（上游 [llama.cpp PR #27342](https://github.com/ggml-org/llama.cpp/pull/27342)）
- **[llama.cpp](https://github.com/ggml-org/llama.cpp)** —— 推理引擎本体

本仓库自身的改动以 MIT 许可发布（见 [LICENSE](LICENSE)）；上游各组件的许可与署名见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。

**本仓库不分发模型权重**，使用模型请遵守其各自许可条款。
