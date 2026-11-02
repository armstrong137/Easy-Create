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

    def boundary(rings, i, j, span=2):
        if span == 1:
            return [rings[row][column % len(rings[0])] for row,column in
                    [(i,j),(i,j+1),(i+1,j+1),(i+1,j)]]
        return [rings[row % len(rings)][column % len(rings[0])]
            for row, column in [(i,j), (i,j+1), (i,j+2), (i+1,j+2),
                                (i+2,j+2), (i+2,j+1), (i+2,j), (i+1,j)]]

    def foliage(edge, seed, birth, count=58, bearing=0):
        for k in range(count):
            phase = seed+k*2.39996
            leaves.append({"edge": edge, "t": .08+.90*(k%11)/10,
                "offset": [math.cos(phase)*(.055+.065*(k%3)/2),
                           math.sin(phase)*.14, .09*math.sin(phase*1.3)],
                "angle": bearing+1.9*math.sin(phase),
                "variant": 2 if (k+seed)%13==0 else [0,1,3][k%3],
                "length": .155+.075*(.5+.5*math.sin(phase*1.7)),
                "birth": birth+(k%7)*.014, "duration": .40})

    def frame(support, parent, center, right):
        shape = [(.015,-.60), (.35,-.56), (.40,-.07), (.34,.56),
                 (-.035,.62), (-.36,.55), (-.43,.06), (-.37,-.55)]
        centers = [center+Vector((x, 0, z)) for x, z in shape]
        rings, ids = [], []
        for i, p in enumerate(centers):
            tangent = centers[(i+1)%8]-centers[(i-1)%8]
            rings.append(ring(p, [.10,.075,.065,.095,.08,.10,.065,.095][i], tangent, 8, 0))
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

    def tube(path, sides, role, parent=None, incoming=None, children=(), terminal=None, seed=0, window=2):
        centers = [Vector(p[:3]) for p in path]
        radii = [p[3] for p in path]
        rings, ids, incoming_center = [], [], None
        if incoming:
            incoming_center = sum((Vector(vertices[i]) for i in incoming), Vector())/len(incoming)
        for i, (p, radius) in enumerate(zip(centers, radii)):
            tangent = centers[min(i+1,len(centers)-1)]-(centers[max(0,i-1)] if i else
                incoming_center if incoming_center is not None else p-Vector((0,0,1)))
            tangent.normalize()
            x = tangent.cross(Vector((0,1,0))).normalized()
            y = tangent.cross(x).normalized()
            reference = (Vector(vertices[rings[-1][0]])-centers[i-1]) if i else (
                Vector(vertices[incoming[0]])-incoming_center if incoming else x)
            phase = math.atan2(reference.dot(y),reference.dot(x))
            rings.append(ring(p, radius, tangent, sides, phase))
            if role=='root':
                flatten = 1-.65*i/(len(path)-1)
                for index in rings[-1]:
                    v = Vector(vertices[index])
                    v.z = p.z+(v.z-p.z)*flatten
                    vertices[index] = tuple(v)
            ids.append(skeleton(p, role, parent if i==0 else ids[-1]))
        holes = {(i+di,(j+dj)%sides) for i,j,d in children
                 for di in range(d.get('window',2)) for dj in range(d.get('window',2))}
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
            tube(parent=ids[i+1], incoming=boundary(rings,i,j,definition.get('window',2)), **definition)
        if role=='twig':
            direction = centers[-1]-centers[-2]
            foliage(len(edges)-1, seed, .20+.025*(seed%7), bearing=math.atan2(direction.x,direction.z))
        return ids

    # 各主枝控制路径直接制作，避免以统一角度和高度层层复制。
    ends = [(-3.45,.35,5.40),(3.55,.48,5.95),(-1.30,.40,8.65),(1.55,.45,8.95)]
    grafts = [(5,11),(6,23),(11,11),(12,23)]
    trunk = [(0,0,.08,.48),(-.03,0,.32,.64),(-.08,.02,.68,.70),(-.10,.05,1.13,.66),
             (-.04,.05,1.70,.59),(.06,.04,2.30,.55),(.13,.08,2.88,.50),
             (.07,.14,3.42,.46),(-.08,.20,3.98,.42),(-.16,.24,4.54,.38),
             (-.12,.30,5.08,.33),(.04,.36,5.64,.28),(.16,.38,6.18,.24),
             (.12,.40,6.72,.20),(-.02,.38,7.25,.16),(-.12,.36,7.78,.12),
             (-.04,.34,8.25,.08),(.10,.30,8.70,.045),(.14,.28,9.10,.02)]
    children = []
    for j,reach in zip(range(0,24,4),[1.85,1.45,1.95,1.62,1.40,1.73]):
        angle = (j+1)*math.tau/24
        d = Vector((math.cos(angle),math.sin(angle),0))
        path = [tuple(d*.85+Vector((0,0,.54)))+(.27,),
                tuple(d*(reach*.62)+Vector((.13*math.sin(j),.07*math.cos(j),.27)))+(.18,),
                tuple(d*(reach*.86)+Vector((.16*math.sin(j+.4),.08*math.cos(j),.095)))+(.11,),
                tuple(d*reach+Vector((.19*math.sin(j+.5),.10*math.cos(j),.022)))+(.065,)]
        children.append((1,j,{"path":path,"sides":8,"role":"root"}))

    def limb_path(start,end,radius):
        start,end = Vector(start),Vector(end)
        delta = end-start
        a = start+Vector((delta.x*.43,delta.y*.25,delta.z*.20))
        b = end-Vector((delta.x*.22,delta.y*.15,delta.z*.25))
        result = []
        for step in range(12):
            t = (step+1)/12
            p = start*(1-t)**3+a*3*t*(1-t)**2+b*3*t*t*(1-t)+end*t**3
            result.append(tuple(p)+(radius*(1-t)+.022,))
        return result

    def shoots(path,seed,branches=()):
        result = list(branches)
        occupied = {(i+di,(j+dj)%8) for i,j,d in branches for di in range(2) for dj in range(2)}
        for host in [1,3,5,7,9,10]:
            for azimuth in [(host+seed)%8,(host+seed+4)%8]:
                if (host,azimuth) in occupied:
                    continue
                a,b = Vector(path[host][:3]),Vector(path[host+1][:3])
                tangent = (b-a).normalized()
                x = tangent.cross(Vector((0,1,0))).normalized()
                y = tangent.cross(x).normalized()
                theta = (azimuth+.5)*math.tau/8
                outward = x*math.cos(theta)+y*math.sin(theta)
                radius = (path[host][3]+path[host+1][3])/2
                anchor = a.lerp(b,.5)+outward*radius
                tip = anchor+outward*(.52+.13*math.sin(host+seed))+Vector((0,0,.68))
                collar = anchor+outward*.075+Vector((0,0,.025))
                middle = collar.lerp(tip,.48)
                shoot_seed = seed*19+host*2+azimuth
                result.append((host,azimuth,{"path":[tuple(collar)+(.040,),tuple(middle)+(.032,),tuple(tip)+(.012,)],
                    "sides":4,"role":"twig","window":1,"seed":shoot_seed}))
        return result

    for branch, ((i,j),end) in enumerate(zip(grafts,ends)):
        start = Vector(trunk[i+1][:3])+Vector((-.43 if branch%2==0 else .43,0,0))
        path = limb_path(start,end,.34 if branch<2 else .24)
        branches = []
        if branch<2:
            secondary_ends = [(-2.00,.55,7.65),(-3.45,.70,6.65)] if branch==0 else [(2.10,.60,8.05),(3.45,.68,7.05)]
            for k,(host,azimuth) in enumerate([(3,2),(7,6)]):
                secondary = limb_path(path[host+1][:3],secondary_ends[k],.18)
                branches.append((host,azimuth,{"path":secondary,"sides":8,"role":"branch",
                    "children":shoots(secondary,branch*5+k+9),"seed":branch*5+k+9}))
        children.append((i,j,{"path":path,"sides":8,"role":"branch","children":shoots(path,branch,branches),"seed":branch}))
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
    foliage(top_edge,81,-.50,28)
    foliage(top_edge,82,.30,58)
    return {"vertices":vertices,"faces":faces,"face_uv":face_uv,"rest_nodes":rest_nodes,
        "edges":edges,"node_roles":node_roles,"leaves":leaves,"plaques":plaques,
        "leafAtlas":{"columns":2,"rows":2,"anchor":[.52,.93],"blade":.82}}
