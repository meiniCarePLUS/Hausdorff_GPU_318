/*
	State Key Lab of CAD&CG Zhejiang Unv.

	Author: 
          Yicun Zheng (3130104113@zju.edu.cn)
          Haoran Sun (hrsun@zju.edu.cn)
          Jin Huang (hj@cad.zju.edu.cn)

	Copyright (c) 2004-2021 <Jin Huang>
	All rights reserved.

	Licensed under the MIT License.
*/

#ifndef MESH_UTIL_HPP
#define MESH_UTIL_HPP

#include <cstddef>
#include <vector>

#include "core/common/conf.h"
#include "mesh/mesh.hpp"

void build_primitive_array(const tri_mesh &mesh, std::vector<primitive_t> &tris) {
    const matrixd_t &v = *mesh.v_;
    const matrixst_t &t = *mesh.t_;
    tris.resize(static_cast<size_t>(t.cols())); // resize to number of triangles

#pragma omp parallel for schedule(static)
    for (size_t ti = 0; ti < tris.size(); ++ti) {
        const Eigen::Vector3i tri = t.col(static_cast<Eigen::Index>(ti));
        for (Eigen::Index local = 0; local < 3; ++local) {
            tris[ti].points.col(local) = v.col(tri(local));
        }
        tris[ti].barycenter = tris[ti].points.rowwise().mean();
        tris[ti].id = ti;
        tris[ti].point_id = tri;
    }
}

#endif
