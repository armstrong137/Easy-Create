"""统一整树造型和出生规则；所有挂点来自同一连接图。"""
import math
from mathutils import Vector


def create_spec():
    nodes = [(0, 0, .50)]
    radii = [.78]
    recipes = [{"kind": "base"}]
    edges, groups, leaves, plaques = [], [], [], []

    def node(parent, p, radius, kind, birth=0, duration=1):
        index = len(nodes)
        nodes.append(tuple(p))
        radii.append(radius)
        recipes.append({"kind": kind, "parent": parent, "birth": birth, "duration": duration})
        edges.append((parent, index))
        return index, len(edges)-1

    trunk_group = []
    trunk_ids = [0]
    for i, (x, y, z, r) in enumerate([
        (-.12, .03, 1.35, .67), (.08, -.02, 2.35, .56),
        (-.16, .08, 3.35, .47), (.12, .15, 4.45, .38),
        (.02, .20, 5.50, .31), (.20, .18, 6.50, .24),
        (.04, .15, 7.35, .15), (.18, .10, 8.12, .045),
    ]):
        index, edge = node(trunk_ids[-1], (x, y, z), r, 'trunk', i*.035-.12, .78)
        trunk_ids.append(index)
        trunk_group.append(edge)
    groups.append(trunk_group)
    for i in range(9):
        angle = i*math.tau/9+.17
        reach = 1.45+.40*math.sin(i*1.73)
        middle = (math.cos(angle)*reach*.50, math.sin(angle)*reach*.50, .18)
        tip = (math.cos(angle)*reach, math.sin(angle)*reach, .035)
        a, edge_a = node(0, middle, .29+.07*math.sin(i), 'root')
        _, edge_b = node(a, tip, .045, 'root')
        groups.append([edge_a, edge_b])
    ends = [(-3.25, .20, 4.10), (3.35, .30, 4.35),
            (-3.10, .45, 5.90), (3.15, .55, 6.10),
            (-2.05, .30, 7.35), (2.10, .35, 7.55), (.30, .20, 8.55)]
    for branch, end in enumerate(ends):
        parent = trunk_ids[min(2+branch, 7)]
        start = Vector(nodes[parent])
        end = Vector(end)
        path_ids, path_edges = [parent], []
        birth = .08+branch*.045
        base_radius = min(.30-branch*.014, radii[parent]*.75)
        for step in range(1, 5):
            t = step/4
            p = start.lerp(end, t)
            p.z -= .28*math.sin(t*math.pi)
            p.y += .12*math.sin(t*math.pi+branch)
            index, edge = node(path_ids[-1], p,
                base_radius*(1-t)+.045, 'branch', birth, .55)
            path_ids.append(index)
            path_edges.append(edge)
        groups.append(path_edges)
        for twig in range(6):
            host = path_ids[1+twig%4]
            anchor = Vector(nodes[host])
            side = -1 if branch%2==0 else 1
            dx = side*(.30+.34*math.sin(twig*2.13+branch))
            dy = .65*math.sin(twig*1.77+branch*1.25)
            length = .72+.26*math.sin(twig*2.4+branch)
            tip = anchor+Vector((dx, dy, length))
            middle = anchor.lerp(tip, .52)
            a, _ = node(host, middle, .095, 'branch', birth+.10, .48)
            _, edge = node(a, tip, .045, 'branch', birth+.16, .48)
            # 叶位和叶柄固定绑定真实末段；只有对应母枝出生后才舒展。
            for cluster in range(5):
                t = .32+cluster*.13
                phase = twig*1.7+branch*2.1+cluster*.83
                for leaf in range(9):
                    angle = leaf*math.tau/9+phase
                    reach = .12+.10*math.sin(leaf*1.43+phase)**2
                    leaves.append({"edge": edge, "t": t,
                        "offset": [math.cos(angle)*reach, math.sin(angle)*reach*.60, .08*math.sin(phase)],
                        "angle": angle, "length": .18+.09*(.5+.5*math.sin(leaf*2.17+phase)),
                        "birth": birth+.20+cluster*.025, "duration": .22})
    # 幼苗的早生叶直接依附主干，不靠缩小成年叶冠充数。
    for cluster, edge in enumerate(trunk_group[:3]):
        for leaf in range(7):
            angle = leaf*math.tau/7+cluster
            leaves.append({"edge": edge, "t": .72, "offset": [math.cos(angle)*.14, -.04, math.sin(angle)*.10],
                "angle": angle, "length": .18, "birth": -.15, "duration": .20})
    for right, parent in [(False, trunk_ids[2]), (True, trunk_ids[3])]:
        side = 1 if right else -1
        start = Vector(nodes[parent])
        center = Vector((side*1.45, -.65, start.z+.18))
        birth = .23 if right else .10
        a, ea = node(parent, (side*.70, -.40, start.z-.20), .19, 'branch', birth, .35)
        bottom = center+Vector((-.30, 0, -.52))
        anchor, eb = node(a, bottom, .095, 'branch', birth, .35)
        ring_ids = [anchor]
        points = [(.25, -.52), (.38, -.31), (.36, .39), (.17, .54),
                  (-.23, .52), (-.38, .29), (-.37, -.30)]
        for x, z in points:
            index, _ = node(anchor, center+Vector((x, 0, z)), .07, 'frame', birth, .35)
            ring_ids.append(index)
        edges.append((ring_ids[-1], anchor))
        groups.append([ea, eb])
        plaques.append({"anchor": anchor, "offset": list(center-Vector(nodes[anchor])),
            "birth": birth, "duration": .35, "title": "第一节" if right else "第九章"})
    return {"nodes": nodes, "edges": edges, "radii": radii, "groups": groups,
            "growth": recipes, "leaves": leaves, "plaques": plaques,
            "camera": {"position": (0, -18, 7.1), "target": (0, 0, 4.75), "scale": 11.4}}


def pose(spec, age):
    smooth = lambda t: max(0, min(1, t))**2*(3-2*max(0, min(1, t)))
    rest = [Vector(p) for p in spec['nodes']]
    grown = []
    for index, recipe in enumerate(spec['growth']):
        p = rest[index]
        if recipe['kind'] == 'base':
            grown.append(Vector((0, 0, .12+.38*smooth(age))))
        elif recipe['kind'] == 'root':
            reach = .30+.70*smooth(age)
            grown.append(Vector((p.x*reach, p.y*reach, p.z if p.z<.05 else p.z*(.35+.65*smooth(age)))))
        else:
            parent = recipe['parent']
            progress = smooth((age-recipe['birth'])/recipe['duration'])
            minimum = .12 if recipe['kind']=='trunk' else .025
            grown.append(grown[parent]+(p-rest[parent])*(minimum+(1-minimum)*progress))
    return grown


def radial(spec, edge_index, age):
    a, b = spec['edges'][edge_index]
    recipe = spec['growth'][b]
    base = .13+.87*(age*age*(3-2*age))
    if recipe['kind'] in ('branch', 'frame'):
        t = max(0, min(1, (age-recipe['birth'])/recipe['duration']))
        return base*(.08+.92*math.sqrt(t*t*(3-2*t)))
    return base
