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

#include <fstream>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "io.h"

#include "igl/readOBJ.h"

using namespace std;

namespace meshio {

int load_obj(const char *filename, matrixst &faces, matrixd &nodes) {
    Eigen::MatrixXd V;
    Eigen::MatrixXi F;
    if (!igl::readOBJ(filename, V, F)) {
        return -1;
    }
    if (V.cols() != 3 || F.cols() != 3) {
        return -1;
    }

    nodes.resize(3, V.rows());
    faces.resize(3, F.rows());

    nodes = V.transpose();
    faces = F.transpose();
    cerr << "# [info] vertex " << V.rows() << " face " << F.rows() << endl;

    return 0;
}

} // namespace meshio
