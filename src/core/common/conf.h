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

#ifndef _BDH_CONF_H_
#define _BDH_CONF_H_

#include <limits>
#include <memory>
#include <utility>

#include <cstddef>

#include <Eigen/Dense>

#include "log_helper.h"

// Mesh storage: keep the hot path in fixed-row matrices.
typedef Eigen::Matrix<double, 3, Eigen::Dynamic> matrixd_t;
typedef Eigen::Matrix<int, 3, Eigen::Dynamic> matrixst_t;
typedef Eigen::Matrix<double, 3, 2> minmax_t;
typedef Eigen::Matrix<double, Eigen::Dynamic, Eigen::Dynamic> dyn_matrixd_t;
typedef Eigen::Vector3d point_t;
typedef std::pair<size_t, size_t> edge_t;

inline Eigen::Index rows(const matrixd_t &m) { return m.rows(); }
inline Eigen::Index cols(const matrixd_t &m) { return m.cols(); }
inline Eigen::Index rows(const matrixst_t &m) { return m.rows(); }
inline Eigen::Index cols(const matrixst_t &m) { return m.cols(); }
inline point_t cross(const point_t &a, const point_t &b) { return a.cross(b); }
inline double dot(const point_t &a, const point_t &b) { return a.dot(b); }
inline double norm(const point_t &a) { return a.norm(); }

struct tri_with_id {
    Eigen::Matrix3d points;   // 3x3: each column is a vertex
    Eigen::Vector3i point_id; // 3 vertex indices
    point_t barycenter;
    size_t id;
    tri_with_id() {
        points = Eigen::Matrix3d::Zero();
        point_id = Eigen::Vector3i::Zero();
        barycenter = point_t::Zero();
        id = (size_t)-1;
    }
};
typedef tri_with_id primitive_t;

// performance record
extern long point_triangle_count;
extern long triangle_triangle_count;

#endif
