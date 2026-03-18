#include "lbvh.cuh"

#include <algorithm>
#include <stdexcept>
#include <thrust/device_vector.h>
#include <thrust/execution_policy.h>
#include <thrust/extrema.h>
#include <thrust/sort.h>
#include <vector>

static inline uint32_t expand_bits_h(uint32_t v) {
    v = (v * 0x00010001u) & 0xFF0000FFu;
    v = (v * 0x00000101u) & 0x0F00F00Fu;
    v = (v * 0x00000011u) & 0xC30C30C3u;
    v = (v * 0x00000005u) & 0x49249249u;
    return v;
}

static inline uint32_t morton3D_h(float x, float y, float z) {
    x = fminf(fmaxf(x * 1024.f, 0.f), 1023.f);
    y = fminf(fmaxf(y * 1024.f, 0.f), 1023.f);
    z = fminf(fmaxf(z * 1024.f, 0.f), 1023.f);
    return (expand_bits_h((uint32_t)x) << 2) |
           (expand_bits_h((uint32_t)y) << 1) |
           expand_bits_h((uint32_t)z);
}
// GPU version of expand_bits
__device__ inline uint32_t expand_bits_d(uint32_t v) {
    v = (v * 0x00010001u) & 0xFF0000FFu;
    v = (v * 0x00000101u) & 0x0F00F00Fu;
    v = (v * 0x00000011u) & 0xC30C30C3u;
    v = (v * 0x00000005u) & 0x49249249u;
    return v;
}

// GPU version of morton3D
__device__ inline uint32_t morton3D_d(float x, float y, float z) {
    x = fminf(fmaxf(x * 1024.f, 0.f), 1023.f);
    y = fminf(fmaxf(y * 1024.f, 0.f), 1023.f);
    z = fminf(fmaxf(z * 1024.f, 0.f), 1023.f);
    return (expand_bits_d((uint32_t)x) << 2) |
           (expand_bits_d((uint32_t)y) << 1) |
           expand_bits_d((uint32_t)z);
}

// Kernel: compute bounding box for each triangle
__global__ void compute_triangle_bounds_kernel(
    const float3x3 *__restrict__ tris,
    float *__restrict__ aabb_min,
    float *__restrict__ aabb_max,
    int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n)
        return;

    const float3x3 &tri = tris[i];
    for (int k = 0; k < 3; ++k) {
        float a = tri.v[k], b = tri.v[k + 3], c = tri.v[k + 6];
        aabb_min[i * 3 + k] = fminf(fminf(a, b), c);
        aabb_max[i * 3 + k] = fmaxf(fmaxf(a, b), c);
    }
}

// Kernel: compute Morton codes
__global__ void compute_morton_kernel(
    const float3x3 *__restrict__ tris,
    const float *__restrict__ scene_min,
    const float *__restrict__ scene_inv,
    uint32_t *__restrict__ morton,
    int *__restrict__ indices,
    int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n)
        return;

    const float3x3 &tri = tris[i];
    float cx = (tri.v[0] + tri.v[3] + tri.v[6]) * (1.f / 3.f);
    float cy = (tri.v[1] + tri.v[4] + tri.v[7]) * (1.f / 3.f);
    float cz = (tri.v[2] + tri.v[5] + tri.v[8]) * (1.f / 3.f);

    float nx = (cx - scene_min[0]) * scene_inv[0];
    float ny = (cy - scene_min[1]) * scene_inv[1];
    float nz = (cz - scene_min[2]) * scene_inv[2];

    morton[i] = morton3D_d(nx, ny, nz);
    indices[i] = i;
}

// Helper: compute common prefix length of two Morton codes
__device__ inline int delta(const uint32_t *morton, int i, int j, int n) {
    if (j < 0 || j >= n)
        return -1;
    if (morton[i] == morton[j]) {
        return __clz(morton[i] ^ morton[j]) + __clz(i ^ j);
    }
    return __clz(morton[i] ^ morton[j]);
}

// Helper: find split position
__device__ inline int find_split(const uint32_t *morton, int first, int last) {
    uint32_t first_code = morton[first];
    uint32_t last_code = morton[last];

    if (first_code == last_code) {
        return (first + last) >> 1;
    }

    int common_prefix = __clz(first_code ^ last_code);
    int split = first;
    int step = last - first;

    do {
        step = (step + 1) >> 1;
        int new_split = split + step;
        if (new_split < last) {
            uint32_t split_code = morton[new_split];
            int split_prefix = __clz(first_code ^ split_code);
            if (split_prefix > common_prefix) {
                split = new_split;
            }
        }
    } while (step > 1);

    return split;
}

// Kernel: build internal nodes (Karras algorithm)
__global__ void build_internal_nodes_kernel(
    const uint32_t *__restrict__ morton,
    const int *__restrict__ sorted_idx,
    LBVHNode *__restrict__ nodes,
    int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n - 1)
        return; // n-1 internal nodes

    // Determine direction and range
    int d = (delta(morton, i, i + 1, n) - delta(morton, i, i - 1, n)) > 0 ? 1 : -1;
    int delta_min = delta(morton, i, i - d, n);

    int l_max = 2;
    while (delta(morton, i, i + l_max * d, n) > delta_min) {
        l_max *= 2;
    }

    int l = 0;
    for (int t = l_max / 2; t >= 1; t /= 2) {
        if (delta(morton, i, i + (l + t) * d, n) > delta_min) {
            l += t;
        }
    }

    int j = i + l * d;
    int delta_node = delta(morton, i, j, n);
    int s = 0;
    int t = l;

    do {
        t = (t + 1) / 2;
        int split = i + (s + t) * d;
        if (delta(morton, i, split, n) > delta_node) {
            s += t;
        }
    } while (t > 1);

    int split = i + s * d + min(d, 0);

    // Set children
    int left_child = (min(i, j) == split) ? (n - 1 + split) : split;
    int right_child = (max(i, j) == split + 1) ? (n - 1 + split + 1) : (split + 1);

    nodes[i].left = left_child;
    nodes[i].right = right_child;
    nodes[i].prim_idx = -1;
    nodes[left_child].parent = i;
    nodes[right_child].parent = i;
}

// Kernel: initialize leaf nodes
__global__ void init_leaf_nodes_kernel(
    const float3x3 *__restrict__ tris,
    const int *__restrict__ sorted_idx,
    LBVHNode *__restrict__ nodes,
    int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n)
        return;

    int leaf_idx = n - 1 + i;
    int prim_idx = sorted_idx[i];

    nodes[leaf_idx].prim_idx = prim_idx;
    nodes[leaf_idx].left = -1;
    nodes[leaf_idx].right = -1;

    const float3x3 &tri = tris[prim_idx];
    for (int k = 0; k < 3; ++k) {
        float a = tri.v[k], b = tri.v[k + 3], c = tri.v[k + 6];
        nodes[leaf_idx].aabb_min[k] = fminf(fminf(a, b), c);
        nodes[leaf_idx].aabb_max[k] = fmaxf(fmaxf(a, b), c);
    }
}

// Kernel: propagate AABBs upward
__global__ void propagate_aabb_kernel(
    LBVHNode *__restrict__ nodes,
    int *__restrict__ flags,
    int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= n)
        return;

    int leaf_idx = n - 1 + i;
    int current = nodes[leaf_idx].parent;

    while (current != -1) {
        int old = atomicAdd(&flags[current], 1);
        if (old == 0) {
            // First thread to reach this node, wait for sibling
            return;
        }

        // Second thread, merge AABBs
        int left = nodes[current].left;
        int right = nodes[current].right;

        for (int k = 0; k < 3; ++k) {
            nodes[current].aabb_min[k] = fminf(nodes[left].aabb_min[k], nodes[right].aabb_min[k]);
            nodes[current].aabb_max[k] = fmaxf(nodes[left].aabb_max[k], nodes[right].aabb_max[k]);
        }

        current = nodes[current].parent;
    }
}

// CPU recursive build: internal nodes [0..n-2], leaves [n-1..2n-2].
static int build_cpu(std::vector<LBVHNode> &nodes,
                     const std::vector<std::pair<uint32_t, int>> &sorted,
                     const float3x3 *tris,
                     int lo, int hi, int &ni, int &nl) {
    if (lo == hi) {
        int idx = nl++;
        int pi = sorted[lo].second;
        nodes[idx].prim_idx = pi;
        nodes[idx].left = nodes[idx].right = -1;
        for (int k = 0; k < 3; ++k) {
            float a = tris[pi].v[k], b = tris[pi].v[k + 3], c = tris[pi].v[k + 6];
            nodes[idx].aabb_min[k] = fminf(fminf(a, b), c);
            nodes[idx].aabb_max[k] = fmaxf(fmaxf(a, b), c);
        }
        return idx;
    }
    int idx = ni++;
    nodes[idx].prim_idx = -1;
    int mid = (lo + hi) / 2;
    int lc = build_cpu(nodes, sorted, tris, lo, mid, ni, nl);
    int rc = build_cpu(nodes, sorted, tris, mid + 1, hi, ni, nl);
    nodes[idx].left = lc;
    nodes[idx].right = rc;
    nodes[lc].parent = nodes[rc].parent = idx;
    for (int k = 0; k < 3; ++k) {
        nodes[idx].aabb_min[k] = fminf(nodes[lc].aabb_min[k], nodes[rc].aabb_min[k]);
        nodes[idx].aabb_max[k] = fmaxf(nodes[lc].aabb_max[k], nodes[rc].aabb_max[k]);
    }
    return idx;
}

void LBVH::build(const float3x3 *h_tris, int n) {
    if (n <= 0)
        throw std::invalid_argument("LBVH::build: n must be > 0");
    n_prims = n;
    // Step 1: Compute scene bounding box on CPU (fast enough for small overhead)
    float smin[3] = {1e30f, 1e30f, 1e30f}, smax[3] = {-1e30f, -1e30f, -1e30f};
    for (int i = 0; i < n; ++i)
        for (int k = 0; k < 3; ++k) {
            float a = h_tris[i].v[k], b = h_tris[i].v[k + 3], c = h_tris[i].v[k + 6];
            smin[k] = fminf(smin[k], fminf(fminf(a, b), c));
            smax[k] = fmaxf(smax[k], fmaxf(fmaxf(a, b), c));
        }
    float inv[3];
    for (int k = 0; k < 3; ++k)
        inv[k] = 1.f / fmaxf(smax[k] - smin[k], 1e-10f);

    // Step 2: Allocate device memory and upload triangles
    float3x3 *d_tris;
    cudaMalloc(&d_tris, n * sizeof(float3x3));
    cudaMemcpy(d_tris, h_tris, n * sizeof(float3x3), cudaMemcpyHostToDevice);

       // Copy scene bounds to device
    float *d_scene_min, *d_scene_inv;
    cudaMalloc(&d_scene_min, 3 * sizeof(float));
    cudaMalloc(&d_scene_inv, 3 * sizeof(float));
    cudaMemcpy(d_scene_min, smin, 3 * sizeof(float), cudaMemcpyHostToDevice);
    cudaMemcpy(d_scene_inv, inv, 3 * sizeof(float), cudaMemcpyHostToDevice);

    // Step 3: Compute Morton codes on GPU
    cudaMalloc(&d_morton, n * sizeof(uint32_t));
    cudaMalloc(&d_sorted_idx, n * sizeof(int));
    int block = 256;
    int grid = (n + block - 1) / block;
    compute_morton_kernel<<<grid, block>>>(d_tris, d_scene_min, d_scene_inv, d_morton, d_sorted_idx, n);
    // cudaDeviceSynchronize();

    cudaFree(d_scene_min);
    cudaFree(d_scene_inv);

    // Step 4: Sort by Morton code using thrust
    thrust::device_ptr<uint32_t> morton_ptr(d_morton);
    thrust::device_ptr<int> idx_ptr(d_sorted_idx);
    thrust::sort_by_key(thrust::device, morton_ptr, morton_ptr + n, idx_ptr);

    // Step 5: Allocate and initialize nodes
    cudaMalloc(&d_nodes, (2 * n - 1) * sizeof(LBVHNode));
    cudaMemset(d_nodes, 0, (2 * n - 1) * sizeof(LBVHNode));

    // Initialize root parent
    LBVHNode root_init;
    root_init.parent = -1;
    cudaMemcpy(d_nodes, &root_init, sizeof(LBVHNode), cudaMemcpyHostToDevice);

    // Step 6: Build leaf nodes on GPU
    init_leaf_nodes_kernel<<<grid, block>>>(d_tris, d_sorted_idx, d_nodes, n);

    // Step 7: Build internal nodes on GPU (Karras algorithm)
    int internal_grid = (n - 1 + block - 1) / block;
    build_internal_nodes_kernel<<<internal_grid, block>>>(d_morton, d_sorted_idx, d_nodes, n);

    // Step 8: Propagate AABBs upward
    int *d_flags;
    cudaMalloc(&d_flags, (n - 1) * sizeof(int));
    cudaMemset(d_flags, 0, (n - 1) * sizeof(int));

    propagate_aabb_kernel<<<grid, block>>>(d_nodes, d_flags, n);
    cudaDeviceSynchronize();

    cudaFree(d_flags);
    cudaFree(d_tris);
}

void LBVH::free() {
    cudaFree(d_nodes);
    d_nodes = nullptr;
    cudaFree(d_sorted_idx);
    d_sorted_idx = nullptr;
    cudaFree(d_morton);
    d_morton = nullptr;
}
