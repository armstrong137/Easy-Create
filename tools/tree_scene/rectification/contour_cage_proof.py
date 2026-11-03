"""截面控制笼验证；--whole制作同源冠层和枝牌完整候选，不接入正式业务。"""
from array import array
import hashlib
import json
import shutil
import math
import sys
from pathlib import Path
import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
REFERENCE='--reference' in sys.argv
ROUND2='--round2' in sys.argv
WHOLE='--whole' in sys.argv or ROUND2 or REFERENCE
OUT=ROOT/('build/qa/reference-crown-proof' if REFERENCE else 'build/qa/cage-whole-round2-proof' if ROUND2 else 'build/qa/cage-whole-proof' if WHOLE else 'build/qa/contour-cage-proof')
OUT.mkdir(parents=True,exist_ok=True)
source=ROOT/'assets/source/magic_tree/textures_source'/('reference_wood_v1.png' if REFERENCE else 'continuous_wood_tips_v2.png' if WHOLE else 'continuous_wood_core_v1.png')
bpy.ops.wm.read_factory_settings(use_empty=True)
image=bpy.data.images.load(str(source));width,height=image.size
pixels=np.empty(width*height*4,dtype=np.float32);image.pixels.foreach_get(pixels)
mask=pixels.reshape(height,width,4)[::-1,:,3]>.5
yy,xx=np.where(mask)
x0,x1=max(0,int(xx.min())-3),min(width-1,int(xx.max())+3)
y0,y1=max(0,int(yy.min())-3),min(height-1,int(yy.max())+3)
columns,rows=48,64
source_points=[(x0+(x1-x0)*c/columns,y0+(y1-y0)*r/rows)
    for r in range(rows+1) for c in range(columns+1)]
quads=[]
for r in range(rows):
    for c in range(columns):
        xa=int(x0+(x1-x0)*c/columns);xb=int(x0+(x1-x0)*(c+1)/columns)+1
        ya=int(y0+(y1-y0)*r/rows);yb=int(y0+(y1-y0)*(r+1)/rows)+1
        if mask[ya:yb,xa:xb].any():
            a=r*(columns+1)+c;quads.append((a,a+columns+1,a+columns+2,a+1))
used=sorted({i for quad in quads for i in quad});remap={old:i for i,old in enumerate(used)}
points=[source_points[i] for i in used]

# 每条横截面左右有序，纵向高度严格有序；枝肩外侧和主干内侧独立伸展。
levels=[0,122,290,463,730,900,1090,1190,1300,1370,1445]
heights=[
    [3.1,2.55,2.1,1.65,1.0,.65,.3,.14,.05,0,-.04],
    [5.8,5.1,4.2,3.3,2.2,1.55,.9,.5,.14,0,-.12],
    [(1370-y)*.006 for y in levels],
]
radii=[65,65,75,100,125,100,135,200,420,545,545]
inner_scales=[
    [.00085,.00085,.00085,.00085,.00085,.00085,.00075,.0005,.00035,.0003,.0003],
    [.0032]*len(levels),
    [.006]*len(levels),
]
outer_scales=[.00002,.0022,.006]
if WHOLE:
    heights[2]=[9.4,8.3,7.0,5.5,3.1,2.1,1.1,.6,.2,0,-.15]
    inner_scales[2]=[.0052]*len(levels)
    outer_scales[2]=.0052

if REFERENCE:
    # 新木体按实际枝肩分段，保持截面严格有序；不是旧五肩枝的第三轮调参。
    levels=[0,100,240,400,560,740,900,1080,1200,1320,1445]
    radii=[35,45,65,95,115,145,130,150,210,410,545]
    heights=[[3.7,3.4,2.9,2.3,1.7,1.1,.65,.30,.14,.04,-.04],
             [6.8,6.3,5.4,4.4,3.5,2.6,1.7,.85,.40,.1,-.1],
             [(1380-y)*.006 for y in levels]]
    inner_scales=[[.0007]*len(levels),[.0028]*len(levels),[.006]*len(levels)]
    outer_scales=[.00002,.0028,.006]

def point_at(stage,x,y):
    distance=x-548;radius=float(np.interp(y,levels,radii))
    inside=float(np.interp(y,levels,inner_scales[stage]))
    span=min(abs(distance),radius)*inside+max(0,abs(distance)-radius)*outer_scales[stage]
    center=0
    if ROUND2 and stage<2:
        offsets=[[.03,.07,.02,-.045,.035,.012,-.01,0,0,0,0],
                 [0,.03,-.03,.04,-.02,.012,0,0,0,0,0]][stage]
        center=float(np.interp(y,levels,offsets))
    return [center+(span if distance>=0 else -span),0,float(np.interp(y,levels,heights[stage]))]

poses=[[point_at(i,x,y) for x,y in points] for i in range(3)]
faces=[[remap[i] for i in quad] for quad in quads]
uv_points=[(x/width,1-y/height) for x,y in points]
face_textures=[0]*len(faces)
parts=[];plaques=[];extras=[]
frame_nodes=[[[0,0,0],[0,0,heights[i][0]]] for i in range(3)]
if WHOLE:
    # 明确核心三角，挂点按该三角的源UV重心权重读取当前几何。
    faces=[tri for q in faces for tri in [(q[0],q[1],q[2]),(q[0],q[2],q[3])]]
    core_faces=list(faces);face_textures=[0]*len(faces)
    texture_names=['reference_canopy_v1.png','reference_frames_v1.png'] if REFERENCE else ['canopy_boughs_v1.png','illustrated_frame_left_v1.png','illustrated_components_v1.png']
    extras=[source.parent/name for name in texture_names]
    textures=[image]+[bpy.data.images.load(str(p)) for p in extras]
    alpha=[]
    for texture in textures:
        data=np.empty(texture.size[0]*texture.size[1]*4,dtype=np.float32);texture.pixels.foreach_get(data)
        alpha.append(data.reshape(texture.size[1],texture.size[0],4)[::-1,:,3]>.5)
    analysis=json.loads((ROOT/('build/qa/reference-canopy-analysis/components.json' if REFERENCE else 'build/qa/canopy-boughs-analysis/components.json')).read_text(encoding='utf-8'))
    if analysis['sha256']!=hashlib.sha256(extras[0].read_bytes()).hexdigest():
        raise RuntimeError('冠层标签过期，请重跑--canopy-boughs透明分析')
    labels=np.frombuffer((ROOT/('build/qa/reference-canopy-analysis/labels.bin' if REFERENCE else 'build/qa/canopy-boughs-analysis/labels.bin')).read_bytes(),dtype='<u4').reshape(analysis['height'],analysis['width'])

    def anchor_at(pixel):
        x,y=pixel
        if not alpha[0][round(y),round(x)]:raise RuntimeError(f'挂点不在实际木体内：{pixel}')
        for triangle in core_faces:
            a,b,c=[points[j] for j in triangle]
            d=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
            u=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/d
            v=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/d
            weights=[u,v,1-u-v]
            if min(weights)>=-1e-7:
                return [[sum(poses[s][j][k]*w for j,w in zip(triangle,weights)) for k in range(3)] for s in range(3)],triangle,weights
        raise RuntimeError(f'挂点没有对应的核心三角：{pixel}')

    def append_patch(name,material,selection,base,anchor,scale,angle=0,middle=.55,early=False,paper=None,title=None):
        anchors,triangle,weights=anchor_at(anchor)
        if (ROUND2 or REFERENCE) and not alpha[material][round(base[1]),round(base[0])]:
            raise RuntimeError(f'子件基点不在实体素材内：{name} {base}')
        ay,ax=np.where(selection);xa,xb=max(0,int(ax.min())-3),min(selection.shape[1]-1,int(ax.max())+3)
        ya,yb=max(0,int(ay.min())-3),min(selection.shape[0]-1,int(ay.max())+3)
        start=len(points);cols,lines=12,12;c,s=math.cos(angle),math.sin(angle)
        growth=[.8,.95,1] if early else [.001,middle,1]
        depth=-.003*(len(parts)+1)
        def position(stage,x,y):
            dx=(x-base[0])*scale;dz=(base[1]-y)*scale
            local_depth=depth
            # 承托枝端口置于母体后，外侧牌框在前，避免整片横压主干。
            if (ROUND2 or REFERENCE) and material in [2,3]:
                front=max(0,min(1,(1050-x)/200)) if material==2 else max(0,min(1,(x-1140)/150))
                if REFERENCE:front=max(0,min(1,abs(x-base[0])/240))
                local_depth=.01+(-.055-.01)*front
            return [anchors[stage][0]+(c*dx+s*dz)*growth[stage],local_depth,
                anchors[stage][2]+(-s*dx+c*dz)*growth[stage]]
        for row in range(lines+1):
            for col in range(cols+1):
                x=xa+(xb-xa)*col/cols;y=ya+(yb-ya)*row/lines
                points.append((x,y));uv_points.append((x/textures[material].size[0],1-y/textures[material].size[1]))
                for stage in range(3):poses[stage].append(position(stage,x,y))
        for row in range(lines):
            for col in range(cols):
                x=int(xa+(xb-xa)*col/cols);xx=int(xa+(xb-xa)*(col+1)/cols)+1
                y=int(ya+(yb-ya)*row/lines);yy=int(ya+(yb-ya)*(row+1)/lines)+1
                if selection[y:yy,x:xx].any():
                    a=start+row*(cols+1)+col;faces.append((a,a+cols+1,a+cols+2,a+1));face_textures.append(material)
        parts.append({'name':name,'anchorSource':anchor,'coreTriangle':triangle,'weights':weights,'material':material,
            'childBaseSource':base,'childBaseOpaque':bool(alpha[material][round(base[1]),round(base[0])]),
            'vertexRange':[start,len(points)]})
        if paper:
            ids=[]
            for x,y in paper:
                ids.append(len(frame_nodes[0]))
                for stage in range(3):frame_nodes[stage].append(position(stage,x,y))
            plaques.append({'corners':ids,'title':title or ('第九章' if material==2 else '第一节'),'birth':.18,'duration':.46,'unroll':True})

    if REFERENCE:
        # 仅在设计点附近选实际实体像素；记录最终坐标，不能把提示词位置当真实端口。
        def opaque_near(mask,desired,limit=60):
            yy,xx=np.where(mask);distance=(xx-desired[0])**2+(yy-desired[1])**2
            best=int(distance.argmin())
            if distance[best]>limit**2:raise RuntimeError(f'设计基点附近没有实体：{desired}')
            return (int(xx[best]),int(yy[best]))
        # C1..C9按真实图集的主连通区编号取图，不按等分格裁切。
        specifications=[(2,(275,351),(550,110),.0060),
            (1,(776,350),(330,270),.0064),(3,(880,345),(715,235),.0064),
            (5,(220,750),(535,420),.0060),(7,(749,735),(215,460),.0062),
            (6,(888,730),(835,400),.0062),(9,(370,1135),(155,720),.0060),
            (8,(480,1127),(940,710),.0060),(10,(897,1120),(695,625),.0052)]
        for i,(component,base,anchor,scale) in enumerate(specifications):
            selection=labels==component
            base=opaque_near(selection,base)
            anchor=opaque_near(alpha[0],anchor)
            append_patch(f'C{i+1}',1,selection,base,anchor,scale,middle=.70)
        # 幼苗保留两组局部早生叶；使用同一局部图集，不切换阶段整树。
        for i,(anchor,angle) in enumerate([((540,115),-.3),((525,340),.45)]):
            selection=labels==10;base=opaque_near(selection,(897,1120))
            append_patch(f'早生叶{i}',1,selection,base,opaque_near(alpha[0],anchor),.0014,angle,early=True)
        for name,base,anchor,paper,title in [
            ('左章牌',(710,725),(425,830),[(275,230),(420,230),(420,570),(275,570)],'第九章'),
            ('右节牌',(1060,725),(670,830),[(1365,230),(1500,230),(1500,570),(1365,570)],'第一节')]:
            selection=alpha[2].copy()
            if base[0]<900:selection[:,887:]=False
            else:selection[:,:887]=False
            append_patch(name,2,selection,opaque_near(selection,base),opaque_near(alpha[0],anchor),.0032,paper=paper,title=title)
    else:
        fan_bases={1:(585,560),2:(688,570),3:(375,1120),4:(987,1120)}
        placements=[(1,(140,565),.0037,-.15,.65),(2,(954,550),.0037,.10,.55),
            (1,(280,330),.0038,-.10,.55),(2,(900,260),.0037,.16,.52),
            (3,(590,180),.0046,0,.63),(1,(360,370),.0030,-.25,.60),
            (2,(720,350),.0030,.20,.58),(3,(560,350),.0035,-.10,.60),
            (1,(290,625),.0033,-.25,.65),(2,(800,650),.0033,.25,.52)]
        if ROUND2:
            placements=[(1,(64,420),.0030,-.20,.60),(2,(988,420),.0030,.16,.52),
                (1,(201,200),.0033,-.12,.53),(2,(946,180),.0032,.18,.58),
                (3,(606,100),.0044,-.08,.60),(3,(103,350),.0021,-.15,.57),
                (3,(1002,350),.0021,.18,.54),(1,(255,300),.0028,-.24,.50),
                (2,(845,300),.0028,.20,.60),(3,(560,350),.0030,-.10,.55),
                (3,(75,500),.0028,-.15,.62),(3,(946,500),.0028,.14,.52),
                (3,(565,500),.0024,.18,.60)]
        for i,(component,anchor,scale,angle,middle) in enumerate(placements):
            append_patch(f'冠层{i}',1,labels==component,fan_bases[component],anchor,scale,angle,middle)
        for i,(anchor,angle,scale) in enumerate([((616,130),0,.0030),((550,500),-.7,.0020),((570,350),.6,.0016)]):
            append_patch(f'早生叶{i}',1,labels==4,fan_bases[4],anchor,scale,angle,early=True)
        append_patch('左章牌',2,alpha[2],(1130,1070) if ROUND2 else (1160,1070),(400,705) if ROUND2 else (548,740),.0022,
            paper=[(248,213),(552,213),(552,902),(248,902)])
        right=alpha[3].copy();right[:500,:]=False;right[:,:1030]=False
        append_patch('右节牌',3,right,(1070,910),(700,720) if ROUND2 else (548,740),.0045,
            paper=[(1286,599),(1419,599),(1419,896),(1286,896)])
mesh=bpy.data.meshes.new('横截面有序控制笼局部木体')
mesh.from_pydata(poses[2],[],faces);mesh.update()
uv=mesh.uv_layers.new(name='固定源图UV')
for polygon in mesh.polygons:
    for loop in polygon.loop_indices:
        uv.data[loop].uv=uv_points[mesh.loops[loop].vertex_index]
body=bpy.data.objects.new('局部轮廓控制验证',mesh);bpy.context.collection.objects.link(body)
mesh.calc_loop_triangles()
payload=array('f');sections={}

def section(name,values):
    start=len(payload);payload.extend(values)
    sections[name]={'offset':start*4,'length':len(payload)-start}

section('normals',(v for _ in points for v in [0,-1,0]))
section('corners',(v for tri in mesh.loop_triangles for loop in tri.loops
    for v in [float(mesh.loops[loop].vertex_index),*uv.data[loop].uv]))
for stage in range(3):section(f'positions{stage}',(v for p in poses[stage] for v in p))
samples=[]
for age,stage in zip([0,.5,1],range(3)):
    # 覆盖全部顶点的源对照，区别于旧方案每姿态只对照三点。
    samples.append({'age':age,'vertices':[{'index':i,'position':p} for i,p in enumerate(poses[stage])]})
low=np.min(np.array(poses[2]),axis=0);high=np.max(np.array(poses[2]),axis=0)
target=[float((low[0]+high[0])/2),0,float((low[2]+high[2])/2)]
scale=max(float(high[2]-low[2])*1.16,float(high[0]-low[0])*760/600*1.15)
meta={'format':'局部截面控制笼-v1','vertexCount':len(points),'triangleCount':len(mesh.loop_triangles),
    'sections':sections,'byteLength':len(payload)*4,
    'nodes':frame_nodes[2],'edges':[[0,1]],
    'poseFrames':[{'age':age,'nodes':frame_nodes[i],'radial':[1]} for i,age in enumerate([0,.5,1])],
    'vertexPoseSections':['positions0','positions1','positions2'],'samples':samples,
    'camera':{'target':target,'right':[1,0,0],'up':[0,0,1],'back':[0,-1,0],'scale':scale},
    'unlitTexture':True,'textureStyles':['wood'],'groundShadow':True,'rootWidth':[.08,.5,1],
    'nearOffset':[target[0],-target[2]+1.9],
    'scope':'仅局部根颈/主肩枝形变，未含叶冠与木牌，不是完整树苗或A2样件'}
if WHOLE:
    foliage_count=sum(p['material']==1 for p in parts)
    meta.update({'extraTextures':['canopy.png','frame-left.png','frame-right-atlas.png'],
        'triangleTextures':[face_textures[t.polygon_index] for t in mesh.loop_triangles],
        'textureStyles':['wood','leaf','frame','frame'],'foliageParts':foliage_count,'plaques':plaques,
        'nearOffset':[target[0],-target[2]+3.0],'scope':'截面控制笼完整首套，待四图短片整体审查'})
    if ROUND2:
        frame_points=[poses[2][i] for p in parts if p['material'] in [2,3] for i in range(*p['vertexRange'])]
        left=min(p[0] for p in frame_points);right=max(p[0] for p in frame_points)
        bottom=min(p[2] for p in frame_points);top=max(p[2] for p in frame_points)
        meta.update({'juvenileContrast':.28,'nearSpan':[(right-left)*1.08,(top-bottom)*1.15],
            'nearOffset':[target[0]-(left+right)/2,(top+bottom)/2-target[2]],
            'scope':'截面控制笼完整第二套，待整套审查；本方案最后一轮'})
if REFERENCE:
    frame_points=[poses[2][i] for p in parts if p['material']==2 for i in range(*p['vertexRange'])]
    left=min(p[0] for p in frame_points);right=max(p[0] for p in frame_points)
    bottom=min(p[2] for p in frame_points);top=max(p[2] for p in frame_points)
    meta.update({'extraTextures':['canopy.png','frame-left.png'],'textureStyles':['wood','leaf','frame'],
        'juvenileContrast':.06,'nearSpan':[(right-left)*1.08,(top-bottom)*1.15],
        'nearOffset':[target[0]-(left+right)/2,(top+bottom)/2-target[2]],
        'scope':'批准参考主导统一源稿完整首套，待实际四图短片整体审查'})
(OUT/'mesh.bin').write_bytes(payload.tobytes())
(OUT/'mesh.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copyfile(source,OUT/'baked-bark.png')
for path,name in zip(extras,['canopy.png','frame-left.png','frame-right-atlas.png']):shutil.copyfile(path,OUT/name)
report={'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'mesh_export':{'vertices':len(points),'triangles':len(mesh.loop_triangles),'bytes':len(payload)*4,
        'referenceSamples':len(points)*3},
    'control':{'sourceLevels':levels,'heights':heights,'innerRadii':radii,'innerScales':inner_scales,'outerScales':outer_scales},
    'production_integrated':False,'visualAcceptance':'局部形变待实际浏览器核对，不计完整样件轮次'}
if WHOLE:
    report.update({'parts':parts,'foliageParts':foliage_count,'plaques':2,'sourceImages':[{'path':str(p.relative_to(ROOT)),
        'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [source]+extras],
        'visualAcceptance':'参考主导完整首套，待四图短片审查' if REFERENCE else '第二套完整候选，待实际四图短片审查' if ROUND2 else '新完整方案第一套，待实际四图短片审查'})
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable-cage.blend'))
print(json.dumps(report['mesh_export']))
