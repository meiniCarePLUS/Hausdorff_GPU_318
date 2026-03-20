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
#include "core/common/n_matrix.h"
#include "core/geometry/bbox.hpp"
#include "core/geometry/primitive_dis.hpp"

#include "bvh.h"

using namespace std;

double aabb::squared_distance(const point_t &p) const {
    double dis = 0, aux = 0;

    for (Eigen::Index d = 0; d < p.size(); ++d) {
        // less than min point
        if (p(d) < minmax_(d, 0)) {
            aux = minmax_(d, 0) - p(d);
            dis += aux * aux;
        }
        // more than max point
        else if (p(d) > minmax_(d, 1)) {
            aux = p(d) - minmax_(d, 1);
            dis += aux * aux;
        }
    }
    return dis;
}

double aabb::squared_distance_lower_bound(const primitive_t &primitive) const {
    bbox box;
    box.add(primitive.points);
    double sqr_dis = 0;

    for (size_t d_iter = 0; d_iter < 3; ++d_iter) {
        if (box.minmax_(d_iter, 0) > minmax_(d_iter, 1)) {
            sqr_dis += (box.minmax_(d_iter, 0) - minmax_(d_iter, 1)) * (box.minmax_(d_iter, 0) - minmax_(d_iter, 1));
        } else if (box.minmax_(d_iter, 1) < minmax_(d_iter, 0)) {
            sqr_dis += (minmax_(d_iter, 0) - box.minmax_(d_iter, 1)) * (minmax_(d_iter, 0) - box.minmax_(d_iter, 1));
        }
    }
    return sqr_dis;
}

bool aabb::intersect_to(const point_t &p) const {
    assert(minmax_.rows() == p.size());
    for (Eigen::Index di = 0; di < minmax_.rows(); ++di)
        if (p[di] < minmax_(di, 0) || p[di] > minmax_(di, 1))
            return false;
    return true;
}

void aabb::init_bounding_volume(const_iterator beg, const_iterator end) {
    minmax_.col(0).setConstant(std::numeric_limits<double>::max());
    minmax_.col(1).setConstant(-std::numeric_limits<double>::max());

    // iterate all vertices
    for (auto iter = beg; iter < end; ++iter) {
        const primitive_t &primitive = **iter;
        for (Eigen::Index pi = 0; pi < primitive.points.cols(); ++pi) {
            for (Eigen::Index di = 0; di < primitive.points.rows(); ++di) {
                if (minmax_(di, 0) > primitive.points(di, pi))
                    minmax_(di, 0) = primitive.points(di, pi);
                if (minmax_(di, 1) < primitive.points(di, pi))
                    minmax_(di, 1) = primitive.points(di, pi);
            }
        }
    }

    // assign mid
    mid_ = (minmax_.col(0) + minmax_.col(1)) / 2.0;
}

#ifdef MEDIAN_PIVOT
bvh::sorter_t *aabb::sorter(iterator beg, iterator end) const { // does this realy binds to aabb?  Except for minmax_, it looks also generally applied.
    const point_t range = minmax_.col(1) - minmax_.col(0);
    const Eigen::Index d = Eigen::Index(std::distance(range.data(), std::max_element(range.data(), range.data() + range.size())));
    unique_ptr<bvh::sorter_t> s(new bvh::sorter_t);
    *s = [d](const primitive_t *a, const primitive_t *b) {
        return a->barycenter(d) < b->barycenter(d);
    };
    return s.release();
}
#else
bvh::pivot_t *aabb::pivot(iterator beg, iterator end) const { // does this realy binds to aabb?  Except for minmax_, it looks also generally applied.
    point_t range = minmax_.col(1) - minmax_.col(0);
    Eigen::Index d = Eigen::Index(std::distance(range.data(), std::max_element(range.data(), range.data() + range.size())));
    double c = (minmax_(d, 1) + minmax_(d, 0)) / 2;
    unique_ptr<bvh::pivot_t> p(new bvh::pivot_t);
    *p = [d, c](const primitive_t *p) {
        return p->barycenter[d] < c;
    };
    return p.release();
}
#endif
