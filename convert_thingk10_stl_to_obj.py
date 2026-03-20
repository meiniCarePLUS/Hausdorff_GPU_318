#!/usr/bin/env python3

import argparse
import math
import os
import struct
from pathlib import Path


def is_probably_ascii_stl(data: bytes) -> bool:
    if not data.startswith(b"solid"):
        return False
    head = data[:512].decode("utf-8", errors="ignore").lower()
    return "facet" in head and "vertex" in head


def read_ascii_stl(path: Path):
    triangles = []
    current = []
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line.lower().startswith("vertex "):
                continue
            parts = line.split()
            if len(parts) != 4:
                continue
            current.append((float(parts[1]), float(parts[2]), float(parts[3])))
            if len(current) == 3:
                triangles.append(tuple(current))
                current = []
    return triangles


def read_binary_stl(path: Path):
    with path.open("rb") as f:
        header = f.read(80)
        if len(header) != 80:
            raise ValueError(f"{path} is too short to be a valid STL file")
        tri_count_data = f.read(4)
        if len(tri_count_data) != 4:
            raise ValueError(f"{path} is missing triangle count")
        tri_count = struct.unpack("<I", tri_count_data)[0]
        triangles = []
        for _ in range(tri_count):
            record = f.read(50)
            if len(record) != 50:
                raise ValueError(f"{path} ended unexpectedly while reading triangles")
            # skip normal (12 bytes)
            values = struct.unpack("<12fH", record)
            v1 = (values[3], values[4], values[5])
            v2 = (values[6], values[7], values[8])
            v3 = (values[9], values[10], values[11])
            triangles.append((v1, v2, v3))
        return triangles


def read_stl(path: Path):
    with path.open("rb") as f:
        data = f.read(512)
    if is_probably_ascii_stl(data):
        triangles = read_ascii_stl(path)
        if triangles:
            return triangles
    return read_binary_stl(path)


def write_obj(path: Path, triangles):
    with path.open("w", encoding="utf-8") as f:
        f.write(f"# Converted from {path.stem}.stl\n")
        vertex_index = 1
        faces = []
        for tri in triangles:
            for vertex in tri:
                if any(math.isnan(c) or math.isinf(c) for c in vertex):
                    raise ValueError(f"{path} contains invalid coordinates")
                f.write(f"v {vertex[0]} {vertex[1]} {vertex[2]}\n")
            faces.append((vertex_index, vertex_index + 1, vertex_index + 2))
            vertex_index += 3
        for face in faces:
            f.write(f"f {face[0]} {face[1]} {face[2]}\n")


def convert_one(stl_path: Path, obj_path: Path, force: bool):
    if obj_path.exists() and not force:
        print(f"[skip] {obj_path} already exists")
        return
    triangles = read_stl(stl_path)
    if not triangles:
        raise ValueError(f"{stl_path} does not contain any triangles")
    write_obj(obj_path, triangles)
    print(f"[ok] {stl_path.name} -> {obj_path.name} ({len(triangles)} tris)")


def main():
    parser = argparse.ArgumentParser(description="Convert thingk10 STL files to OBJ")
    parser.add_argument(
        "--dir",
        default="./thingk10",
        help="Directory containing thingk10 models (default: ./thingk10)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Overwrite existing OBJ files",
    )
    args = parser.parse_args()

    model_dir = Path(args.dir).resolve()
    if not model_dir.is_dir():
        raise SystemExit(f"Model directory does not exist: {model_dir}")

    stl_files = sorted(model_dir.glob("*.stl"))
    if not stl_files:
        raise SystemExit(f"No STL files found in {model_dir}")

    for stl_path in stl_files:
        obj_path = stl_path.with_suffix(".obj")
        convert_one(stl_path, obj_path, args.force)


if __name__ == "__main__":
    main()
