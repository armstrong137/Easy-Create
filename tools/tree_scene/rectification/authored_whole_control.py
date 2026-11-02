"""整树控制笼：所有分叉和木框通过开口边界连接，UV沿解剖部位展开。"""
import math
from mathutils import Vector


def build():
    vertices, faces, face_uv, rest_nodes, edges, node_roles = [], [], [], [], [], []
    leaves, plaques = [], []

    def point(p):
        vertices.append(tuple(p))
        return len(vertices)-1

    def skeleton(p, role, parent=None):
        rest_nodes.append(Vector(p))
        node_roles.append((role, parent))
        index = len(rest_nodes)-1
        if parent is not None:
            edges.append((parent, index))
        return index

    def face(ids, uv):
        faces.append(ids)
        face_uv.append(uv)

    def bridge(a, b, va, vb, width):
        for k in range(len(a)):
            n = (k+1) % len(a)
            face([a[k], a[n], b[n], b[k]], [(k/len(a)*width, va),
                 ((k+1)/len(a)*width, va), ((k+1)/len(a)*width, vb), (k/len(a)*width, vb)])

    def ring(center, radius, tangent, sides, phase):
        tangent = Vector(tangent).normalized()
        x = tangent.cross(Vector((0, 1, 0))).normalized()
        y = tangent.cross(x).normalized()
        return [point(center+radius*(math.cos(phase+k*math.tau/sides)*x+
            math.sin(phase+k*math.tau/sides)*y)) for k in range(sides)]

    def boundary(rings, i, j):
        return [rings[row % len(rings)][column % len(rings[0])]
            for row, column in [(i,j), (i,j+1), (i,j+2), (i+1,j+2),
                                (i+2,j+2), (i+2,j+1), (i+2,j), (i+1,j)]]

    def foliage(edge, seed, birth, count=46):
        for k in range(count):
            phase = seed+k*2.39996
            side = -1 if k%2 else 1
            leaves.append({"edge": edge, "t": .15+.83*(k%7)/6,
                "offset": [math.cos(phase)*(.055+.09*(k%3)/2),
                           math.sin(phase)*.13, .08*math.sin(phase*1.3)],
                "angle": side*(.30+1.2*(.5+.5*math.sin(phase))),
                "variant": k%4, "length": .23+.11*(.5+.5*math.sin(phase*1.7)),
                "birth": birth+(k%7)*.009, "duration": .30})

    def frame(support, parent, center, right):
        shape = [(0,-.62), (.38,-.57), (.42,0), (.38,.57),
                 (0,.62), (-.38,.57), (-.42,0), (-.38,-.57)]
        centers = [center+Vector((x, 0, z)) for x, z in shape]
        rings, ids = [], []
        for i, p in enumerate(centers):
            tangent = centers[(i+1)%8]-centers[(i-1)%8]
            rings.append(ring(p, .075, tangent, 8, 0))
            ids.append(skeleton(p, 'frame', parent if i==0 else ids[-1]))
        edges.append((ids[-1], ids[0]))
        # 木框底部开口与承托枝末圈共用桥接面，闭环不靠叠放两个封口伪装。
        hole_i, hole_j = 6, 3
        removed = {((hole_i+di)%8, (hole_j+dj)%8) for di in range(2) for dj in range(2)}
        for i in range(8):
            for j in range(8):
                if (i,j) in removed:
                    continue
                face([rings[i][j], rings[i][(j+1)%8], rings[(i+1)%8][(j+1)%8], rings[(i+1)%8][j]],
                     [(j/8*.25,i/8), ((j+1)/8*.25,i/8), ((j+1)/8*.25,(i+1)/8), (j/8*.25,(i+1)/8)])
        bridge(support, boundary(rings, hole_i, hole_j), 0, .13, .30)
        plaques.append({"corners": [ids[i] for i in [5,3,1,7]],
            "birth": .24 if right else .13, "duration": .40,
            "title": "第一节" if right else "第九章"})

    def tube(path, sides, role, parent=None, incoming=None, children=(), terminal=None, seed=0):
        centers = [Vector(p[:3]) for p in path]
        radii = [p[3] for p in path]
        rings, ids, incoming_center = [], [], None
        if incoming:
            incoming_center = sum((Vector(vertices[i]) for i in incoming), Vector())/len(incoming)
        for i, (p, radius) in enumerate(zip(centers, radii)):
            tangent = centers[min(i+1,len(centers)-1)]-(centers[max(0,i-1)] if i else
                incoming_center if incoming_center is not None else p-Vector((0,0,1)))
            rings.append(ring(p, radius, tangent, sides, .06*math.sin(i*.73+seed)))
            ids.append(skeleton(p, role, parent if i==0 else ids[-1]))
        holes = {(i+di,(j+dj)%sides) for i,j,_ in children for di in range(2) for dj in range(2)}
        length, values = 0, [centers[0].z*.16]
        for a,b in zip(centers,centers[1:]):
            length += (b-a).length
            values.append(values[0]+length*.16)
        width = .95 if role=='trunk' else .54 if role=='root' else .52
        if incoming:
            bridge(incoming, rings[0], values[0]-.08, values[0], width)
        else:
            face(rings[0][::-1], [(.5+.08*math.cos(k*math.tau/sides),.1+.08*math.sin(k*math.tau/sides)) for k in range(sides)])
        for i in range(len(rings)-1):
            for j in range(sides):
                if (i,j) in holes:
                    continue
                face([rings[i][j],rings[i][(j+1)%sides],rings[i+1][(j+1)%sides],rings[i+1][j]],
                     [(j/sides*width,values[i]),((j+1)/sides*width,values[i]),
                      ((j+1)/sides*width,values[i+1]),(j/sides*width,values[i+1])])
        if terminal:
            frame(rings[-1], ids[-1], Vector(terminal['center']), terminal['right'])
        else:
            face(rings[-1], [(.5+.02*math.cos(k*math.tau/sides),values[-1]+.02*math.sin(k*math.tau/sides)) for k in range(sides)])
        for i,j,definition in children:
            tube(parent=ids[i+1], incoming=boundary(rings,i,j), **definition)
        if role=='twig':
            foliage(len(edges)-1, seed, .20+.018*(seed%7))
        return ids

    # 各主枝控制路径直接制作，避免以统一角度和高度层层复制。
    ends = [(-3.55,.35,5.45), (3.70,.48,5.95), (-2.80,.55,7.25),
            (2.85,.70,7.55), (-1.45,.40,8.65), (1.55,.45,8.95)]
    grafts = [(5,11),(6,23),(9,11),(10,23),(13,11),(14,23)]
    trunk = [(0,0,.08,.48),(-.03,0,.32,.64),(-.08,.02,.68,.70),(-.10,.05,1.13,.66),
             (-.04,.05,1.70,.59),(.06,.04,2.30,.55),(.13,.08,2.88,.50),
             (.07,.14,3.42,.46),(-.08,.20,3.98,.42),(-.16,.24,4.54,.38),
             (-.12,.30,5.08,.33),(.04,.36,5.64,.28),(.16,.38,6.18,.24),
             (.12,.40,6.72,.20),(-.02,.38,7.25,.16),(-.12,.36,7.78,.12),
             (-.04,.34,8.25,.08),(.10,.30,8.70,.045),(.14,.28,9.10,.02)]
    children = []
    for j,reach in zip(range(0,24,4),[1.55,1.30,1.68,1.38,1.20,1.48]):
        angle = (j+1)*math.tau/24
        d = Vector((math.cos(angle),math.sin(angle),0))
        path = [tuple(d*.85+Vector((0,0,.54)))+(.27,),
                tuple(d*(reach*.77)+Vector((.07*math.sin(j),.03*math.cos(j),.20)))+(.15,),
                tuple(d*reach+Vector((.09*math.sin(j),0,.045)))+(.025,)]
        children.append((1,j,{"path":path,"sides":8,"role":"root"}))
    for branch, ((i,j),end) in enumerate(zip(grafts,ends)):
        start, end = Vector(trunk[i+1][:3]),Vector(end)
        path = []
        for step in range(10):
            t = (step+1)/10
            p = start.lerp(end,t)
            p.z -= .22*math.sin(t*math.pi)
            p.y += .12*math.sin(t*math.pi+branch)
            path.append(tuple(p)+(.32*(1-t)+.024,))
        twigs = []
        for index,(host,azimuth) in enumerate([(1,0),(1,4),(4,1),(4,5),(7,0),(7,4)]):
            anchor = Vector(path[host+1][:3])
            phase = branch*.91+index*2.399
            tip = anchor+Vector((.65*math.cos(phase),.65*math.sin(phase),.65+.40*(.5+.5*math.sin(phase))))
            middle = anchor.lerp(tip,.48)
            twigs.append((host,azimuth,{"path":[tuple(middle)+(.055,),tuple(tip)+(.018,)],
                "sides":8,"role":"twig","seed":branch*13+index}))
        children.append((i,j,{"path":path,"sides":8,"role":"branch","children":twigs,"seed":branch}))
    for right,i,j in [(False,4,15),(True,6,19)]:
        side = 1 if right else -1
        z = trunk[i+1][2]+.15
        center = Vector((side*1.62,-.78,z))
        path = [(side*.70,-.38,z-.18,.16),(side*1.10,-.60,z-.55,.11),
                tuple(center+Vector((-.25,0,-.78)))+(.075,)]
        children.append((i,j,{"path":path,"sides":8,"role":"frame",
            "terminal":{"center":list(center),"right":right}}))
    ids = tube(trunk,24,'trunk',children=children)
    # 顶部中轴仍是真实主干，幼龄早生叶在末端成簇，而非沿干横排长柄。
    top_edge = next(index for index,(a,b) in enumerate(edges) if b==ids[-1])
    foliage(top_edge,81,-.40,28)
    foliage(top_edge,82,.25,58)
    return {"vertices":vertices,"faces":faces,"face_uv":face_uv,"rest_nodes":rest_nodes,
        "edges":edges,"node_roles":node_roles,"leaves":leaves,"plaques":plaques,
        "leafAtlas":{"columns":2,"rows":2,"anchor":[.52,.93],"blade":.82}}
