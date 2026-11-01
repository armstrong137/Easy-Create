"""只读检查既有源资产，为淘汰样件后的实现方法评估提供证据。"""
import json
from pathlib import Path
import bpy

root = Path(__file__).resolve().parents[3]
meshes = []
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    meshes.append({
        "name": obj.name,
        "vertices": len(obj.data.vertices),
        "polygons": len(obj.data.polygons),
        "uv_layers": [layer.name for layer in obj.data.uv_layers],
        "shape_keys": list(obj.data.shape_keys.key_blocks.keys()) if obj.data.shape_keys else [],
        "materials": [slot.material.name if slot.material else None for slot in obj.material_slots],
    })
materials = []
for material in bpy.data.materials:
    images = []
    if material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                images.append({"node": node.name, "image": node.image.name if node.image else None})
    materials.append({"name": material.name, "image_nodes": images})
output = root / "build/qa/rectification-source-audit.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({
    "source": bpy.data.filepath,
    "mesh_count": len(meshes),
    "meshes": meshes,
    "materials": materials,
    "note": "只读结构检查，不保存源模型，不证明模型视觉质量或可直接复用",
}, ensure_ascii=False, indent=2), encoding="utf-8")
print(str(output))
