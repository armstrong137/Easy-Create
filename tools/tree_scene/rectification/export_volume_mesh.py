"""导出实际网格、图集UV、法线与空间绑定；不导出树龄阶段图片。"""
from array import array
import json
from mathutils import Vector


def export_mesh(mesh, rest_nodes, edges, bindings, camera, target, output, deform, extra=None):
    mesh.calc_loop_triangles()
    payload = array('f')
    sections = {}

    def section(name, values):
        start = len(payload)
        payload.extend(values)
        sections[name] = {"offset": start * 4, "length": len(payload)-start}

    section('normals', (v for vertex in mesh.vertices for v in vertex.normal))
    section('bindings', (value for group in bindings for edge, t, offset, weight in group
                         for value in [float(edge), t, *offset, weight]))
    uv = mesh.uv_layers.active.data
    section('corners', (value for tri in mesh.loop_triangles for loop in tri.loops
                        for value in [float(mesh.loops[loop].vertex_index), *uv[loop].uv]))
    samples = []
    indices = [0, len(mesh.vertices)//3, len(mesh.vertices)-1]
    for age in [0, .5, 1]:
        deform(age)
        samples.append({"age": age, "vertices": [
            {"index": index, "position": list(mesh.vertices[index].co)} for index in indices]})
    deform(1)
    rotation = camera.rotation_euler.to_quaternion()
    metadata = {
        "format": "固定网格连续空间绑定-v1", "vertexCount": len(mesh.vertices),
        "triangleCount": len(mesh.loop_triangles), "sections": sections,
        "nodes": [list(p) for p in rest_nodes], "edges": edges,
        "camera": {"target": list(target), "right": list(rotation @ Vector((1, 0, 0))),
                   "up": list(rotation @ Vector((0, 1, 0))),
                   "back": list(rotation @ Vector((0, 0, 1))), "scale": camera.data.ortho_scale},
        "samples": samples, "byteLength": len(payload)*4,
        "note": "Float32小端；绑定每顶点三组[边,t,偏移xyz,权重]；角点[顶点索引,u,v]",
    }
    if extra:
        metadata.update(extra)
    (output / 'mesh.bin').write_bytes(payload.tobytes())
    (output / 'mesh.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    return {"bytes": len(payload)*4, "vertices": metadata['vertexCount'],
            "triangles": metadata['triangleCount'],
            "referenceSamples": sum(len(sample['vertices']) for sample in metadata['samples'])}
