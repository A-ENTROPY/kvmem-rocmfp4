# 基准测试 / Benchmarks

## 测试平台

| 项 | 值 |
|---|---|
| GPU | AMD Radeon **RX 7900 XTX**，gfx1100（RDNA3），24 GB |
| CPU / 内存 | 24 核 / 32 线程 · 64 GB DDR4-3200 四通道 |
| 系统 | Windows x64 |
| ROCm | 7.2（HIP 7.2.60201-38d754472），标准布局安装 |
| 编译 | MSVC 14.44.35207 · AMD Clang 21.0.0git · Ninja |

## 模型

| 角色 | 文件 | 大小 |
|---|---|---|
| 主模型 | `Qwen3.8-27B-Q4_0_ROCMFP4_STRIX.gguf` | 13.75 GB |
| DFlash2 草稿 | `Qwen3.8-27B-DFlash2-Q4_K_M.gguf` | 1.06 GB |

## 主基准：推测解码对照

**协议**：全新启动服务 → 预热一次 → 连续 3 次请求（每次约 400–480 token 输出），
逐请求把服务端 `eval time` 计时行归因到对应请求；采样 greedy（`temperature=0`），
关闭思考（`reasoning_effort=none`）。

**配置**：`-c 32768`、`-b 512`、`--kvmem --kvmem-budget 8192 --kvmem-gen-reserve 4096`、
`--kv-dtype q8_0`、**不传 `--threads`、不传 `--flash-attn`**。

| 配置 | 首次长生成 | 上下文增长后 |
|---|---:|---:|
| 原生（`--spec-type none`） | 38.8 tok/s | 38.9 tok/s |
| **DFlash2 `n_max=3`** | **48.1 tok/s（+24%）** | 40.5 tok/s（+4%） |
| DFlash2 `n_max=5` | 45.8 tok/s | 36.7 tok/s |

**草稿接受率**（`--kvmem-trace` 输出 `KVMEM_TRACE spec_stats`）：

| 草稿数 | 草稿 token | 接受 token | 接受率 |
|---:|---:|---:|---:|
| 3 | 993 | 369 | **37.2%** |
| 7 | 2127 | 395 | 18.6% |

→ 草稿越长接受率越低，`n_max=3` 是本机的收益拐点。

**瞬时峰值**：解析进度日志中的 3 秒窗口速率（`tg_3s`），最高观测 **52.96 tok/s**。

## 上下文长度的代价

同一配置、同一请求，只改上下文大小（DFlash2 n_max=3）：

| 上下文配置 | 解码速度 |
|---|---:|
| `-c 32768` | 51.96 tok/s |
| `-c 262144` | 51.45 tok/s |

→ **KVMem 让 256K 上下文几乎没有速度惩罚**，这正是分层的价值所在。

## 配置敏感性（会腰斩速度的两项）

固定其他条件，只加一个参数：

| 变体 | 解码速度 | 影响 |
|---|---:|---|
| 精简配置（基准） | 51.45 tok/s | — |
| **+ `--threads 0`** | **26.60 tok/s** | **-48%** |
| **+ `--flash-attn on`** | **29.26 tok/s** | **-44%** |
| + 采样参数 + 思考 | 50.93 tok/s | -1% |
| + `--webui` | 51.72 tok/s | 0% |
| + `--main-gpu 0 --split-mode none --no-mmproj-offload` | 50.74 tok/s | -1% |

→ GPU 全卸载时，`--threads 0`（用满 32 线程）空转会争抢采样与图调度；`--flash-attn on` 在此路径上也不划算。

## 三合一 vs 官方基线

| 方案 | 主模型 | 加速 | 解码速度 |
|---|---|---|---:|
| KVMem 官方配方 | IQ3_S（11.29 GB） | MTP2 | 37.5 tok/s |
| 本仓库 | ROCmFP4（13.75 GB） | 无 | 39.2 tok/s |
| **本仓库** | **ROCmFP4** | **DFlash2 (n=3)** | **48.1 tok/s** |
| 本仓库（不推荐组合） | IQ3_S | DFlash2 (n=3) | 12.6 tok/s |

⚠️ 最后一行：IQ3_S 是 GDN 混合架构，其回滚机制与独立草稿模型不合，DFlash2 会显著变慢。

## 复现方式

```powershell
# 1) 原生基线
.\start-kvmem.bat -Model "主模型.gguf" -Spec none
# 2) DFlash2
.\start-kvmem.bat -Model "主模型.gguf" -Draft "DFlash2.gguf" -DraftTokens 3
```

用任意 OpenAI 兼容客户端发一个约 600 token 的长请求，读取服务端日志中的：

```
slot   eval time =   13981.34 ms /   700 tokens (   50.07 tokens per second)
```

该行是纯解码速率（不含提示处理），跨运行可比性最好。

> 注意：不要把不同上下文长度、不同输出长度、不同采样设置的数字直接对比。
> 本文所有对照都在同一协议下完成。
