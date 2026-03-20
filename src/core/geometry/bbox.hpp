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

#ifndef _BBOX_HPP
#define _BBOX_HPP

#include "core/common/conf.h"

// bounding box
struct bbox {

    bbox() {
        minmax_.resize(3, 2);
        minmax_.col(0).setConstant(std::numeric_limits<double>::max());
        minmax_.col(1).setConstant(-std::numeric_limits<double>::max());
    }

    // column based, every column is a point
    void add(const matrixd_t &points) {
        assert(points.rows() == 3);
        for (Eigen::Index d_iter = 0; d_iter < 3; ++d_iter) {
            minmax_(d_iter, 0) = std::min(points.row(d_iter).minCoeff(), minmax_(d_iter, 0));
            minmax_(d_iter, 1) = std::max(points.row(d_iter).maxCoeff(), minmax_(d_iter, 1));
        }
    }

    double diagonal() const {
        return sqrt(sqr_diagonal());
    }

    double sqr_diagonal() const {
        const point_t diagonal = minmax_.col(1) - minmax_.col(0);
        return diagonal.squaredNorm();
    }

    matrixd_t minmax_;
};

#endif
