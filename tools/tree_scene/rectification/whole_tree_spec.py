"""第二轮统一整树：低分叉宽冠、高根颈、顶端幼叶与同源框纸。"""
import math
from mathutils import Vector


def create_spec():
    nodes, radii, recipes = [(0, 0, .38)], [.64], [{"kind": "base"}]
    edges, groups, leaves, plaques = [], [], [], []

    def node(parent, p, radius, kind, birth=0, duration=1):
        index = len(nodes)
        nodes.append(tuple(p))
        radii.append(radius)
        recipes.append({"kind": kind, "parent": parent, "birth": birth, "duration": duration})
        edges.append((parent, index))
        return index, len(edges)-1

    trunk_ids, trunk_group = [0], []
    for i, p in enumerate([
        (-.10, .04, 1.18, .68), (.10, .02, 2.25, .61),
        (-.16, .12, 3.35, .55), (.13, .22, 4.35, .46),
        (-.08, .35, 5.45, .35), (.15, .40, 6.50, .24),
        (-.05, .38, 7.50, .13), (.12, .36, 8.50, .035),
    ]):
        index, edge = node(trunk_ids[-1], p[:3], p[3], 'trunk', i*.018-.08, .90)
        trunk_ids.append(index)
        trunk_group.append(edge)
    groups.append(trunk_group)
    # 根颈从较高干节点落向地面，各粗根有自身弯曲和坡度，不铺一圈扁裙边。
    for i in range(7):
        angle = i*math.tau/7+.27
        reach = 1.25+.36*math.sin(i*1.73)
        group, parent = [], trunk_ids[1]
        for t, height, radius in [(.37, .63, .25), (.72, .23, .16), (1, .09, .065)]:
            bend = angle+.13*math.sin(t*math.pi+i)
            parent, edge = node(parent, (math.cos(bend)*reach*t,
                math.sin(bend)*reach*t, height), radius, 'root')
            group.append(edge)
        groups.append(group)

    limbs = [(3, (-4.15, .25, 5.85)), (3, (4.10, .35, 6.20)),
             (4, (-3.35, .40, 7.80)), (4, (3.10, .65, 8.00)),
             (5, (-1.80, .25, 8.95)), (5, (1.85, .40, 9.20)),
             (6, (.20, .25, 9.55))]
    for branch, (host, end) in enumerate(limbs):
        start, end = Vector(nodes[trunk_ids[host]]), Vector(end)
        path_ids, path_edges = [trunk_ids[host]], []
        birth = .045+branch*.035
        base_radius = min(.34-branch*.020, radii[path_ids[0]]*.76)
        for step in range(1, 6):
            t = step/5
            p = start.lerp(end, math.sin(t*math.pi/2))
            p.z = start.z+(end.z-start.z)*(.65*t+.35*t*t)
            p.y += .13*math.sin(t*math.pi+branch)
            index, edge = node(path_ids[-1], p, base_radius*(1-t)+.045,
                               'branch', birth, .64)
            path_ids.append(index)
            path_edges.append(edge)
        for twig in range(10):
            host = path_ids[2+twig%4]
            anchor = Vector(nodes[host])
            phase = twig*2.399+branch*.83
            tip = anchor+Vector((.72*math.cos(phase), .72*math.sin(phase),
                                  .65+.40*(.5+.5*math.sin(phase*1.7))))
            middle = anchor.lerp(tip, .48)
            a, ea = node(host, middle, .065, 'branch', birth+.08, .58)
            _, edge = node(a, tip, .040, 'branch', birth+.12, .58)
            path_edges.extend([ea, edge])
            # 叶片沿枝两侧交错，局部偏移形成疏密，避免绕同一点转成花球。
            for cluster in range(7):
                t = .10+cluster*.14
                for leaf in range(3):
                    seed = phase+cluster*1.91+leaf*2.17
                    side = -1 if (cluster+leaf)%2 else 1
                    offset = [side*(.12+.18*(.5+.5*math.sin(seed))),
                              .18*math.sin(seed*1.3), .12*math.sin(seed*.7)]
                    leaves.append({"edge": edge, "t": t, "offset": offset,
                        "angle": side*(.52+.65*(.5+.5*math.sin(seed))),
                        "variant": (cluster+twig+branch+leaf)%4,
                        "length": .24+.10*(.5+.5*math.sin(seed*1.23)),
                        "birth": birth+.14+cluster*.018, "duration": .26})
        groups.append(path_edges)
    # 初龄叶依附上部主干，随着同一主干伸展抬升，不另放一张幼苗图。
    for cluster, edge in enumerate(trunk_group[-3:]):
        for leaf in range(6):
            side = -1 if leaf%2 else 1
            leaves.append({"edge": edge, "t": .35+leaf*.10,
                "offset": [side*.16, -.08, .02], "angle": side*(.65+cluster*.15),
                "variant": leaf%4, "length": .26, "birth": -.25, "duration": .20})

    for right, parent in [(False, trunk_ids[2]), (True, trunk_ids[3])]:
        side = 1 if right else -1
        start = Vector(nodes[parent])
        center = Vector((side*1.65, -.75, start.z+.30))
        birth = .24 if right else .12
        a, ea = node(parent, (side*.78, -.40, start.z-.05), .17, 'branch', birth, .40)
        bottom = center+Vector((-.41, 0, -.59))
        anchor, eb = node(a, bottom, .075, 'frame', birth, .40)
        ring_ids, frame_edges = [anchor], [ea, eb]
        # 沿环逐段连接；四个角节点同时定义纸面，不再画独立定尺寸矩形。
        for x, z in [(0, -.61), (.41, -.59), (.43, 0), (.41, .59),
                     (0, .61), (-.41, .59), (-.43, 0)]:
            index, edge = node(ring_ids[-1], center+Vector((x, 0, z)),
                               .075, 'frame', birth, .40)
            ring_ids.append(index)
            frame_edges.append(edge)
        edges.append((ring_ids[-1], anchor))
        frame_edges.append(len(edges)-1)
        groups.append(frame_edges)
        plaques.append({"corners": [ring_ids[i] for i in [6, 4, 2, 0]],
            "birth": birth, "duration": .40, "title": "第一节" if right else "第九章"})
    return {"nodes": nodes, "edges": edges, "radii": radii, "groups": groups,
            "growth": recipes, "leaves": leaves, "plaques": plaques,
            "leafAtlas": {"columns": 2, "rows": 2, "anchor": [.52, .93], "blade": .82},
            "camera": {"position": (0, -19, 7.3), "target": (0, 0, 5.0), "scale": 12.8}}


def pose(spec, age):
    smooth = lambda t: max(0, min(1, t))**2*(3-2*max(0, min(1, t)))
    rest, grown = [Vector(p) for p in spec['nodes']], []
    for index, recipe in enumerate(spec['growth']):
        p = rest[index]
        if recipe['kind'] == 'base':
            grown.append(Vector((0, 0, .045+.335*smooth(age))))
        elif recipe['kind'] == 'root':
            reach = .11+.89*smooth(age)
            grown.append(Vector((p.x*reach, p.y*reach, p.z*(.10+.90*smooth(age)))))
        else:
            parent = recipe['parent']
            progress = smooth((age-recipe['birth'])/recipe['duration'])
            minimum = .21 if recipe['kind']=='trunk' else .003
            grown.append(grown[parent]+(p-rest[parent])*(minimum+(1-minimum)*progress))
    return grown


def radial(spec, edge_index, age):
    _, b = spec['edges'][edge_index]
    recipe = spec['growth'][b]
    base = .055+.945*(age*age*(3-2*age))
    if recipe['kind'] in ('branch', 'frame'):
        t = max(0, min(1, (age-recipe['birth'])/recipe['duration']))
        return base*(.025+.975*math.sqrt(t*t*(3-2*t)))
    return base
