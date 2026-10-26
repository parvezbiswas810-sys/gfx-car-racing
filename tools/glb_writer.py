"""Minimal glTF 2.0 binary (.glb) writer.

Builds a single mesh from primitives (boxes, cylinders, quads) grouped by
material name, then serialises it as a valid GLB with POSITION / NORMAL /
TEXCOORD_0 accessors and indexed triangles.

Godot 4 imports these directly. Kept dependency-free on purpose so the asset
pipeline can be re-run anywhere.
"""

import base64
import json
import math
import struct

FLOAT = 5126
UNSIGNED_INT = 5125

ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963


class MeshBuilder:
    """Accumulates triangles grouped per material slot."""

    def __init__(self):
        self._verts = []          # (x, y, z)
        self._normals = []        # (x, y, z)
        self._uvs = []            # (u, v)
        self._groups = []         # (material_name, [index, ...])
        self._current = None

    # -- material grouping -------------------------------------------------
    def begin(self, material_name):
        if self._current is not None:
            self._groups.append(self._current)
        self._current = (material_name, [])

    def end(self):
        if self._current is not None:
            self._groups.append(self._current)
            self._current = None

    # -- low level ---------------------------------------------------------
    def _add_vertex(self, pos, normal, uv):
        self._verts.append(pos)
        self._normals.append(normal)
        self._uvs.append(uv)
        return len(self._verts) - 1

    def add_triangle(self, a, b, c, normal=None, uvs=((0.0, 0.0), (1.0, 0.0), (1.0, 1.0))):
        if normal is None:
            normal = _face_normal(a, b, c)
        i0 = self._add_vertex(a, normal, uvs[0])
        i1 = self._add_vertex(b, normal, uvs[1])
        i2 = self._add_vertex(c, normal, uvs[2])
        self._current[1].extend((i0, i1, i2))

    def add_quad(self, a, b, c, d, normal=None, uvs=((0, 0), (1, 0), (1, 1), (0, 1))):
        if normal is None:
            normal = _face_normal(a, b, c)
        i0 = self._add_vertex(a, normal, uvs[0])
        i1 = self._add_vertex(b, normal, uvs[1])
        i2 = self._add_vertex(c, normal, uvs[2])
        i3 = self._add_vertex(d, normal, uvs[3])
        self._current[1].extend((i0, i1, i2, i0, i2, i3))

    # -- shapes ------------------------------------------------------------
    def add_box(self, center, size, uv_scale=1.0, taper=None):
        """Axis aligned box. `taper` scales the +Z face (x_scale, y_scale)."""
        cx, cy, cz = center
        sx, sy, sz = (s * 0.5 for s in size)
        tx, ty = taper if taper else (1.0, 1.0)

        def corner(xs, ys, zs):
            fx = tx if zs > 0 else 1.0
            fy = ty if zs > 0 else 1.0
            return (cx + sx * xs * fx, cy + sy * ys * fy, cz + sz * zs)

        # -X / +X
        self.add_quad(corner(-1, -1, -1), corner(-1, -1, 1), corner(-1, 1, 1), corner(-1, 1, -1))
        self.add_quad(corner(1, -1, 1), corner(1, -1, -1), corner(1, 1, -1), corner(1, 1, 1))
        # -Y / +Y
        self.add_quad(corner(-1, -1, 1), corner(-1, -1, -1), corner(1, -1, -1), corner(1, -1, 1))
        self.add_quad(corner(-1, 1, -1), corner(-1, 1, 1), corner(1, 1, 1), corner(1, 1, -1))
        # -Z / +Z
        self.add_quad(corner(1, -1, -1), corner(-1, -1, -1), corner(-1, 1, -1), corner(1, 1, -1))
        self.add_quad(corner(-1, -1, 1), corner(1, -1, 1), corner(1, 1, 1), corner(-1, 1, 1))

    def add_cylinder_x(self, center, radius, half_length, segments=20, cap=True):
        """Cylinder whose axis runs along the X axis (wheels)."""
        cx, cy, cz = center
        for i in range(segments):
            a0 = 2.0 * math.pi * i / segments
            a1 = 2.0 * math.pi * (i + 1) / segments
            y0, z0 = cy + radius * math.cos(a0), cz + radius * math.sin(a0)
            y1, z1 = cy + radius * math.cos(a1), cz + radius * math.sin(a1)
            # side quad
            n = _normalise((0.0, math.cos(0.5 * (a0 + a1)), math.sin(0.5 * (a0 + a1))))
            self.add_quad(
                (cx - half_length, y0, z0),
                (cx + half_length, y0, z0),
                (cx + half_length, y1, z1),
                (cx - half_length, y1, z1),
                normal=n,
            )
            if cap:
                # outer cap fan (approximate with triangle to centre)
                self.add_triangle(
                    (cx + half_length, cy, cz),
                    (cx + half_length, y0, z0),
                    (cx + half_length, y1, z1),
                    normal=(1.0, 0.0, 0.0),
                )
                self.add_triangle(
                    (cx - half_length, cy, cz),
                    (cx - half_length, y1, z1),
                    (cx - half_length, y0, z0),
                    normal=(-1.0, 0.0, 0.0),
                )

    def add_quad_flat(self, a, b, c, d):
        self.add_quad(a, b, c, d)

    # -- serialise ---------------------------------------------------------
    def build(self, materials):
        self.end()
        buffer = bytearray()
        accessors = []
        buffer_views = []
        primitives = []

        def push_view(data, target):
            offset = len(buffer)
            buffer.extend(data)
            while len(buffer) % 4:
                buffer.append(0)
            buffer_views.append({
                "buffer": 0,
                "byteOffset": offset,
                "byteLength": len(data),
                "target": target,
            })
            return len(buffer_views) - 1

        def push_accessor(view, component_type, count, type_name, minimum=None, maximum=None):
            acc = {
                "bufferView": view,
                "componentType": component_type,
                "count": count,
                "type": type_name,
            }
            if minimum is not None:
                acc["min"] = minimum
                acc["max"] = maximum
            accessors.append(acc)
            return len(accessors) - 1

        pos_data = b"".join(struct.pack("<3f", *v) for v in self._verts)
        nrm_data = b"".join(struct.pack("<3f", *v) for v in self._normals)
        uv_data = b"".join(struct.pack("<2f", *v) for v in self._uvs)

        pos_view = push_view(pos_data, ARRAY_BUFFER)
        nrm_view = push_view(nrm_data, ARRAY_BUFFER)
        uv_view = push_view(uv_data, ARRAY_BUFFER)

        xs = [v[0] for v in self._verts]
        ys = [v[1] for v in self._verts]
        zs = [v[2] for v in self._verts]

        pos_acc = push_accessor(
            pos_view, FLOAT, len(self._verts), "VEC3",
            [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)],
        )
        nrm_acc = push_accessor(nrm_view, FLOAT, len(self._normals), "VEC3")
        uv_acc = push_accessor(uv_view, FLOAT, len(self._uvs), "VEC2")

        material_names = []
        for name, indices in self._groups:
            if name not in material_names:
                material_names.append(name)
            idx_data = b"".join(struct.pack("<I", i) for i in indices)
            idx_view = push_view(idx_data, ELEMENT_ARRAY_BUFFER)
            idx_acc = push_accessor(idx_view, UNSIGNED_INT, len(indices), "SCALAR")
            primitives.append({
                "attributes": {"POSITION": pos_acc, "NORMAL": nrm_acc, "TEXCOORD_0": uv_acc},
                "indices": idx_acc,
                "material": material_names.index(name),
                "mode": 4,
            })

        gltf = {
            "asset": {"version": "2.0", "generator": "gfx-racing-asset-tool"},
            "scene": 0,
            "scenes": [{"nodes": [0]}],
            "nodes": [{"mesh": 0, "name": "Mesh"}],
            "meshes": [{"name": "Mesh", "primitives": primitives}],
            "materials": [materials[n] for n in material_names],
            "accessors": accessors,
            "bufferViews": buffer_views,
            "buffers": [{"byteLength": len(buffer)}],
        }

        json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
        json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
        bin_chunk = bytes(buffer)

        total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
        out = bytearray()
        out.extend(b"glTF")
        out.extend(struct.pack("<II", 2, total))
        out.extend(struct.pack("<I", len(json_chunk)))
        out.extend(b"JSON")
        out.extend(json_chunk)
        out.extend(struct.pack("<I", len(bin_chunk)))
        out.extend(b"BIN\x00")
        out.extend(bin_chunk)
        return bytes(out)


def _face_normal(a, b, c):
    ux, uy, uz = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    vx, vy, vz = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
    return _normalise(n)


def _normalise(n):
    length = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2)
    if length < 1e-9:
        return (0.0, 1.0, 0.0)
    return (n[0] / length, n[1] / length, n[2] / length)


def standard_material(name, base_color, metallic=0.0, roughness=0.6, emissive=None):
    mat = {
        "name": name,
        "pbrMetallicRoughness": {
            "baseColorFactor": list(base_color),
            "metallicFactor": metallic,
            "roughnessFactor": roughness,
        },
        "doubleSided": False,
    }
    if emissive:
        mat["emissiveFactor"] = list(emissive)
    return mat
