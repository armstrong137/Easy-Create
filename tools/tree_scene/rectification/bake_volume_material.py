"""沿枝局部坐标的连续投影混合，只在离线烘焙使用复杂材质。"""
import math
import bpy
import numpy as np
from mathutils import Vector


def bake_material(body, rest_nodes, edges, nearest, image_source, output, groups=None):
    mesh = body.data
    whole_tree = groups is not None
    groups = groups or [[0, 1, 2, 3], [4, 5, 6], [7, 8, 9],
              [10, 11], [12, 13], [14, 15], [16, 17]]
    attributes = [f"枝向权重{i}" for i in range(len(groups))]
    for name in attributes:
        mesh.attributes.new(name, 'FLOAT', 'POINT')
    for vertex in mesh.vertices:
        distances = [min(nearest(vertex.co, rest_nodes[edges[i][0]],
                                  rest_nodes[edges[i][1]])[2] for i in group) for group in groups]
        weights = [1 / (distance + (.035 if whole_tree else .08))**2 for distance in distances]
        total = sum(weights)
        for name, weight in zip(attributes, weights):
            mesh.attributes[name].data[vertex.index].value = weight / total
    material = bpy.data.materials.new("沿枝投影混合烘焙源")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    links = material.node_tree.links

    def math_node(operation, a, b=None):
        node = nodes.new('ShaderNodeMath')
        node.operation = operation
        for socket, value in zip(node.inputs, [a, b]):
            if value is None:
                continue
            if isinstance(value, (int, float)):
                socket.default_value = value
            else:
                links.new(value, socket)
        return node.outputs[0]

    def color_mix(operation, a, b):
        node = nodes.new('ShaderNodeMixRGB')
        node.blend_type = operation
        node.inputs[0].default_value = 1
        links.new(a, node.inputs[1])
        links.new(b, node.inputs[2])
        return node.outputs[0]

    def dot(value, axis):
        node = nodes.new('ShaderNodeVectorMath')
        node.operation = 'DOT_PRODUCT'
        links.new(value, node.inputs[0])
        node.inputs[1].default_value = axis
        return node.outputs['Value']

    def source_batch(first, last):
        nodes.clear()
        coordinates = nodes.new('ShaderNodeTexCoord').outputs['Object']
        normal = nodes.new('ShaderNodeNewGeometry').outputs['Normal']
        color_sum = None
        for index in range(first, last):
            group = groups[index]
            start = rest_nodes[edges[group[0]][0]]
            end = rest_nodes[edges[group[-1]][1]]
            z = (end-start).normalized()
            x = z.cross(Vector((0, 1, 0))).normalized()
            y = z.cross(x).normalized()
            normal_weights = [math_node('POWER', math_node('ABSOLUTE', dot(normal, axis)), 4)
                              for axis in [x, y, z]]
            total = math_node('ADD', math_node('ADD', normal_weights[0], normal_weights[1]), normal_weights[2])
            group_weight = nodes.new('ShaderNodeAttribute')
            group_weight.attribute_name = attributes[index]
            for axis_index, (u, v) in enumerate([(y, z), (x, z), (x, y)]):
                uv = nodes.new('ShaderNodeCombineXYZ')
                links.new(math_node('MULTIPLY', dot(coordinates, u), .35 if whole_tree else .8), uv.inputs[0])
                links.new(math_node('MULTIPLY', dot(coordinates, v), .22 if whole_tree else .8), uv.inputs[1])
                texture = nodes.new('ShaderNodeTexImage')
                texture.image = image_source
                texture.extension = 'REPEAT'
                links.new(uv.outputs[0], texture.inputs['Vector'])
                weight = math_node('MULTIPLY', group_weight.outputs['Fac'],
                                   math_node('DIVIDE', normal_weights[axis_index], total))
                contribution = color_mix('MULTIPLY', texture.outputs['Color'], weight)
                color_sum = contribution if color_sum is None else color_mix('ADD', color_sum, contribution)
        emission = nodes.new('ShaderNodeEmission')
        links.new(color_sum, emission.inputs['Color'])
        result = nodes.new('ShaderNodeOutputMaterial')
        links.new(emission.outputs[0], result.inputs['Surface'])
    mesh.materials.clear()
    mesh.materials.append(material)
    bpy.ops.object.select_all(action='DESELECT')
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(55), island_margin=.025)
    bpy.ops.object.mode_set(mode='OBJECT')
    atlas = bpy.data.images.new("连通体烘焙基色", width=2048, height=2048, alpha=True)
    scene = bpy.context.scene
    previous_engine = scene.render.engine
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    accumulated = np.zeros(2048*2048*4, dtype=np.float32)
    pixels = np.empty_like(accumulated)
    # 每批最多六组，避免整树投影超出Cycles SVM栈；累加在线性像素空间进行。
    for first in range(0, len(groups), 6):
        source_batch(first, min(first+6, len(groups)))
        target = nodes.new('ShaderNodeTexImage')
        target.image = atlas
        nodes.active = target
        bpy.ops.object.bake(type='EMIT', margin=16, use_clear=True)
        atlas.pixels.foreach_get(pixels)
        accumulated += pixels
    np.clip(accumulated, 0, 1, out=accumulated)
    atlas.pixels.foreach_set(accumulated)
    atlas.update()
    atlas.filepath_raw = str(output / "baked-bark.png")
    atlas.file_format = 'PNG'
    atlas.save()
    # 运行时材质只保留一张图集；不把离线的多路采样负担带入二维验证。
    nodes.clear()
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.inputs['Roughness'].default_value = .88
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = atlas
    links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    bump = nodes.new('ShaderNodeBump')
    bump.inputs['Strength'].default_value = .28
    bump.inputs['Distance'].default_value = .045
    links.new(texture.outputs['Color'], bump.inputs['Height'])
    links.new(bump.outputs['Normal'], shader.inputs['Normal'])
    result = nodes.new('ShaderNodeOutputMaterial')
    links.new(shader.outputs[0], result.inputs['Surface'])
    scene.render.engine = previous_engine
