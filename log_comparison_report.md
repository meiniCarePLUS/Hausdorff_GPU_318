# Hausdorff 日志对比报告

## 1. 对比范围与口径

- 对比目录：
  - `logs_cpu_serial`
  - `logs_cpu_parallel`
  - `logs_gpu_comparison_v1`
  - `logs_gpu_comparison_v2`
- 对比指标：
  - 耗时：`[bvh_build_cost]`、`[first_travel_cost]`、`[reduce_bound_cost]`、`[total_cost]`
  - 结果：`[mean_distance]`、`[reverse_check_result]`
- 以 `cpu serial` 为 baseline。
- 正确性判定：
  - `mean_distance` 与 baseline 的相对误差 <= 1%
  - `reverse_check_result` 与 baseline 的相对误差 <= 1%
  - 两项都满足时视为“正确”
- 最终共对齐到 17 个模型：
  - `arm`、`armadillo`、`bimba`、`bumpy`、`bunny`、`camel_b`、`cow`、`elephant`、`face`、`hand-tri`、`happy`、`homer`、`horse`、`inspired_mesh`、`lilium`、`snail`、`truck`
- 额外说明：
  - `logs_gpu_comparison_v1/beast_gpu.log` 和 `logs_gpu_comparison_v2/beast_gpu.log` 解析失败，日志中没有目标统计字段，因此未纳入比较。

## 2. 总体结论

- `cpu_parallel` 相比 `cpu_serial`：
  - `bvh_build_cost` 没有整体加速，平均仅为 `0.929x`，中位数 `0.972x`
  - `first_travel_cost` 中位加速 `4.291x`
  - `reduce_bound_cost` 中位加速 `2.898x`
  - `total_cost` 中位加速 `4.115x`
  - 正确性 `17/17` 全部通过
- `gpu_v1` 相比 `cpu_serial`：
  - `bvh_build_cost` 平均 `4.770x`
  - `first_travel_cost` 平均 `16.970x`
  - `reduce_bound_cost` 平均 `24.559x`
  - `total_cost` 平均 `17.284x`，中位数 `17.003x`
  - 正确性 `16/17`，仅 `homer` 未通过
- `gpu_v2` 相比 `cpu_serial`：
  - `bvh_build_cost` 平均 `5.002x`
  - `first_travel_cost` 平均 `17.069x`
  - `reduce_bound_cost` 平均 `28.194x`
  - `total_cost` 平均 `17.420x`，中位数 `17.206x`
  - 正确性 `16/17`，仅 `homer` 未通过
- `gpu_v2` 相比 `gpu_v1`：
  - `total_cost` 平均再下降 `0.79%`
  - 17 个模型里有 16 个更快
  - 提升最明显的几个模型：`bunny`、`truck`、`armadillo`、`cow`、`bimba`
  - 唯一略慢的是 `bumpy`，退化约 `0.16%`

## 3. 分项耗时对比

| 实现 | bvh_build_cost | first_travel_cost | reduce_bound_cost | total_cost | 正确性 |
| --- | ---: | ---: | ---: | ---: | ---: |
| cpu_parallel | 平均 0.929x / 中位 0.972x | 平均 -0.096x / 中位 4.291x | 平均 3.291x / 中位 2.898x | 平均 -0.166x / 中位 4.115x | 17/17 |
| gpu_v1 | 平均 4.770x / 中位 4.004x | 平均 16.970x / 中位 17.006x | 平均 24.559x / 中位 17.840x | 平均 17.284x / 中位 17.003x | 16/17 |
| gpu_v2 | 平均 5.002x / 中位 4.072x | 平均 17.069x / 中位 17.181x | 平均 28.194x / 中位 18.158x | 平均 17.420x / 中位 17.206x | 16/17 |

说明：

- `cpu_parallel` 的 `first_travel_cost` 和 `total_cost` 平均值为负，是因为 `bunny` 的并行日志中：
  - `[first_travel_cost] = -178.917`
  - `[total_cost] = -176.416`
- 因此 `cpu_parallel` 更适合看中位数，整体上仍然表现为大约 `4x` 的总耗时加速。

## 4. 逐模型总耗时对比

下表中的加速比均为：`cpu_serial total_cost / 当前实现 total_cost`。

| 模型 | cpu_serial total | cpu_parallel total | parallel 加速比 | gpu_v1 total | gpu_v1 加速比 | gpu_v2 total | gpu_v2 加速比 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| arm | 1513.170 | 352.712 | 4.290x | 89.023 | 16.998x | 88.278 | 17.141x |
| armadillo | 9346.210 | 1917.710 | 4.874x | 545.558 | 17.131x | 538.565 | 17.354x |
| bimba | 20161.800 | 3912.850 | 5.153x | 1185.750 | 17.003x | 1171.790 | 17.206x |
| bumpy | 358.429 | 115.281 | 3.109x | 17.410 | 20.588x | 17.438 | 20.555x |
| bunny | 12003.800 | -176.416 | -68.043x | 686.266 | 17.491x | 676.697 | 17.739x |
| camel_b | 407.071 | 98.912 | 4.115x | 23.063 | 17.650x | 23.025 | 17.679x |
| cow | 376.775 | 128.467 | 2.933x | 23.138 | 16.284x | 22.859 | 16.482x |
| elephant | 1292.460 | 292.506 | 4.419x | 76.758 | 16.838x | 76.220 | 16.957x |
| face | 9931.420 | 1648.430 | 6.025x | 645.448 | 15.387x | 641.897 | 15.472x |
| hand-tri | 319.376 | 78.319 | 4.078x | 19.817 | 16.116x | 19.787 | 16.141x |
| happy | 8332.590 | 1769.550 | 4.709x | 615.589 | 13.536x | 609.726 | 13.666x |
| homer | 1164.270 | 242.416 | 4.803x | 70.181 | 16.590x | 69.757 | 16.690x |
| horse | 7517.720 | 1216.840 | 6.178x | 428.226 | 17.555x | 424.270 | 17.719x |
| inspired_mesh | 5681.770 | 2443.360 | 2.325x | 259.073 | 21.931x | 256.295 | 22.169x |
| lilium | 555.063 | 216.607 | 2.563x | 30.441 | 18.234x | 30.154 | 18.407x |
| snail | 224.581 | 93.981 | 2.390x | 11.163 | 20.118x | 11.130 | 20.178x |
| truck | 634.255 | 194.306 | 3.264x | 44.091 | 14.385x | 43.495 | 14.582x |

## 5. 正确性检查

### 5.1 cpu_parallel

- 17/17 全部通过
- 虽然部分模型的 `mean_distance` 和 `cpu_serial` 不完全相同，但误差都在 1% 以内

### 5.2 gpu_v1

- 16/17 通过
- 未通过模型：`homer`
  - `mean_distance`
    - baseline: `0.00481821`
    - gpu_v1: `0.00461967`
    - 相对误差: `4.12%`
  - `reverse_check_result`
    - baseline: `0.00479687`
    - gpu_v1: `0.00461967`
    - 相对误差: `3.69%`

### 5.3 gpu_v2

- 16/17 通过
- 未通过模型：`homer`
  - `mean_distance`
    - baseline: `0.00481821`
    - gpu_v2: `0.00461967`
    - 相对误差: `4.12%`
  - `reverse_check_result`
    - baseline: `0.00479687`
    - gpu_v2: `0.00461967`
    - 相对误差: `3.69%`

## 6. 重点观察

- 从总耗时看，GPU 两版都明显优于 CPU 两版：
  - `cpu_parallel` 的典型总加速约为 `4x`
  - `gpu_v1/gpu_v2` 的典型总加速约为 `17x`
- `gpu_v2` 在几乎所有模型上都比 `gpu_v1` 更快，但提升幅度整体不大，属于稳定优化而不是数量级变化。
- `cpu_parallel` 的 `bvh_build_cost` 没有体现出明显收益，甚至平均略慢于 `cpu_serial`。
- `reduce_bound_cost` 是 GPU 提升最明显的阶段之一，尤其在 `homer`、`face`、`inspired_mesh` 等模型上优势非常显著。
- 正确性方面，`cpu_parallel` 最稳定；两版 GPU 都只在 `homer` 上超过 1% 阈值，说明 GPU 结果总体可靠，但 `homer` 需要单独排查。
