"""Процедурная модель вертолёта Ми-26 для Blender.

Запуск без интерфейса:
    blender -b -P mi26.py            # или: python3 mi26.py (с модулем bpy)
Результат: Mi-26.glb, Mi-26.fbx, Mi-26.blend и рендеры в папке renders/.

Оси: X — вперёд (нос), Y — влево, Z — вверх. Единицы — метры.
"""
import math
import os

import bpy  # bpy нужно импортировать до bmesh
import bmesh
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))


# ---------- материалы ----------

def make_mat(name, color, rough=0.5, metal=0.0):
    m = bpy.data.materials.new(name)
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    m.diffuse_color = (*color, 1.0)
    return m


# ---------- геометрия ----------

def link(name, bm, mats, location=(0, 0, 0), rotation=(0, 0, 0), smooth=False, subsurf=0, parent=None):
    if smooth:
        for f in bm.faces:
            f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    ob.location = location
    ob.rotation_euler = rotation
    bpy.context.scene.collection.objects.link(ob)
    if subsurf:
        mod = ob.modifiers.new("Subsurf", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf
    if parent:
        ob.parent = parent
    return ob


def catmull(p0, p1, p2, p3, t):
    return 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                  + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3)


def loft(name, keys, mats, matfn=None, seg=48, steps=6, **kw):
    """Тело вращения по сечениям-суперэллипсам.
    keys: (x, полуширина, полувысота, z центра, показатель суперэллипса, y центра)."""
    rows = []
    for i in range(len(keys) - 1):
        k0, k1, k2, k3 = keys[max(i - 1, 0)], keys[i], keys[i + 1], keys[min(i + 2, len(keys) - 1)]
        for s in range(steps):
            t = s / steps
            rows.append([catmull(a, b, c, d, t) for a, b, c, d in zip(k0, k1, k2, k3)])
    rows.append(list(keys[-1]))

    bm = bmesh.new()
    rings = []
    for x, w, h, zc, n, yc in rows:
        ring = []
        for j in range(seg):
            a = 2 * math.pi * j / seg
            c, s = math.cos(a), math.sin(a)
            y = yc + w * math.copysign(abs(c) ** (2 / n), c)
            z = zc + h * math.copysign(abs(s) ** (2 / n), s)
            ring.append(bm.verts.new((x, y, z)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for j in range(seg):
            f = bm.faces.new((r0[j], r0[(j + 1) % seg], r1[(j + 1) % seg], r1[j]))
            if matfn:
                # материал по углу сечения, чтобы границы шли по рёбрам сетки
                x = (r0[j].co.x + r1[j].co.x) / 2
                f.material_index = matfn(x, math.degrees(2 * math.pi * (j + 0.5) / seg))
    for ring, row in ((rings[0], rows[0]), (rings[-1], rows[-1])):
        c = bm.verts.new((row[0], row[5], row[3]))
        for j in range(seg):
            bm.faces.new((ring[j], ring[(j + 1) % seg], c))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return link(name, bm, mats, smooth=True, **kw)


def box(name, size, mat, location=(0, 0, 0), rotation=(0, 0, 0), offset=(0, 0, 0), parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0] + offset[0], v.co.y * size[1] + offset[1], v.co.z * size[2] + offset[2]))
    return link(name, bm, [mat], location, rotation, parent=parent)


def cyl(name, r, depth, mat, location, rotation=(0, 0, 0), r2=None, seg=32, parent=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    return link(name, bm, [mat], location, rotation, smooth=True, parent=parent)


def plate(name, outline, thickness, mat, axis="y", location=(0, 0, 0), rotation=(0, 0, 0)):
    """Плоская деталь по контуру, выдавленная по толщине."""
    bm = bmesh.new()
    h = thickness / 2
    if axis == "y":   # контур в плоскости XZ
        front = [bm.verts.new((u, -h, v)) for u, v in outline]
        back = [bm.verts.new((u, h, v)) for u, v in outline]
    else:             # контур в плоскости XY
        front = [bm.verts.new((u, v, -h)) for u, v in outline]
        back = [bm.verts.new((u, v, h)) for u, v in outline]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    n = len(outline)
    for i in range(n):
        bm.faces.new((front[i], front[(i + 1) % n], back[(i + 1) % n], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = link(name, bm, [mat], location, rotation)
    bev = ob.modifiers.new("Bevel", "BEVEL")
    bev.width = min(0.04, thickness / 3)
    bev.segments = 2
    return ob


def star(name, radius, mat, location, rotation):
    pts = []
    for i in range(10):
        r = radius if i % 2 == 0 else radius * 0.4
        a = math.pi / 2 + i * math.pi / 5
        pts.append((r * math.cos(a), r * math.sin(a)))
    bm = bmesh.new()
    c = bm.verts.new((0, 0, 0))
    vs = [bm.verts.new((u, v, 0)) for u, v in pts]
    for i in range(10):
        bm.faces.new((c, vs[i], vs[(i + 1) % 10]))
    return link(name, bm, [mat], location, rotation)


# ---------- сборка ----------

def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    body = make_mat("Body_Green", (0.17, 0.22, 0.13), 0.6)
    belly = make_mat("Belly_Blue", (0.42, 0.52, 0.58), 0.6)
    glass = make_mat("Glass", (0.02, 0.04, 0.06), 0.05, 0.3)
    dark = make_mat("Dark_Metal", (0.05, 0.05, 0.05), 0.4, 0.8)
    metal = make_mat("Metal", (0.45, 0.45, 0.45), 0.35, 0.9)
    rubber = make_mat("Rubber", (0.015, 0.015, 0.015), 0.9)
    blade_m = make_mat("Blade", (0.08, 0.08, 0.08), 0.5)
    red = make_mat("Red", (0.6, 0.02, 0.02), 0.5)
    white = make_mat("White", (0.85, 0.85, 0.85), 0.5)
    door_m = make_mat("Door", (0.11, 0.14, 0.08), 0.6)
    yellow = make_mat("Yellow", (0.85, 0.65, 0.05), 0.5)

    # Фюзеляж: нос -> грузовая кабина -> рампа -> хвостовая балка
    #        x     w     h    zc    n    y
    fus = [
        (14.2, 0.15, 0.20, 2.75, 2.0, 0),
        (13.8, 0.90, 1.00, 2.85, 2.2, 0),
        (13.0, 1.45, 1.55, 3.00, 2.4, 0),
        (11.8, 1.75, 1.95, 3.10, 2.8, 0),
        (10.0, 1.90, 2.15, 3.15, 3.2, 0),
        (6.0, 1.95, 2.20, 3.20, 3.4, 0),
        (-2.0, 1.95, 2.20, 3.20, 3.4, 0),
        (-4.0, 1.85, 2.00, 3.40, 3.0, 0),
        (-6.0, 1.45, 1.35, 4.10, 2.6, 0),
        (-8.0, 0.85, 0.85, 4.50, 2.2, 0),
        (-11.0, 0.68, 0.68, 4.70, 2.0, 0),
        (-16.0, 0.55, 0.55, 4.95, 2.0, 0),
        (-19.8, 0.45, 0.48, 5.15, 2.0, 0),
        (-20.6, 0.20, 0.25, 5.25, 2.0, 0),
    ]

    def fus_mat(x, deg):
        if 11.3 < x < 13.9 and (12 < deg < 74 or 106 < deg < 168):
            return 2  # остекление кабины, по центру крыши — переплёт
        if math.sin(math.radians(deg)) < -0.5:
            return 1  # светлое брюхо
        return 0

    loft("Fuselage", fus, [body, belly, glass], fus_mat, seg=56, steps=6, subsurf=1)

    # Капот двигателей и редуктора на крыше
    loft("Cowling", [
        (10.6, 0.30, 0.20, 5.15, 2.4, 0),
        (9.8, 1.55, 0.85, 5.25, 2.6, 0),
        (4.0, 1.70, 1.00, 5.40, 2.8, 0),
        (-1.0, 1.50, 1.05, 5.45, 2.8, 0),
        (-5.0, 0.90, 0.75, 5.20, 2.4, 0),
        (-8.0, 0.40, 0.35, 4.95, 2.2, 0),
    ], [body], seg=40, subsurf=1)

    # Двигатели Д-136 (две гондолы) с воздухозаборниками и выхлопом
    for side in (1, -1):
        y = 1.15 * side
        loft(f"Engine_{'L' if side > 0 else 'R'}", [
            (10.3, 0.62, 0.62, 5.95, 2.0, y),
            (10.0, 0.78, 0.78, 5.95, 2.0, y),
            (7.0, 0.82, 0.82, 5.95, 2.0, y),
            (3.0, 0.80, 0.80, 5.90, 2.0, y),
            (1.6, 0.66, 0.66, 5.85, 2.0, y),
        ], [body], seg=36, steps=4)
        cyl(f"Intake_{side}", 0.56, 0.06, dark, (10.33, y, 5.95), (0, math.radians(90), 0))
        cyl(f"Spinner_{side}", 0.22, 0.5, metal, (10.45, y, 5.95), (0, math.radians(90), 0), r2=0.02)
        cyl(f"Exhaust_{side}", 0.5, 1.4, dark, (1.2, y + 0.35 * side, 5.85),
            (0, math.radians(90), math.radians(-25 * side)), r2=0.6)

    # Иллюминаторы грузовой кабины и двери
    for side in (1, -1):
        for i, x in enumerate((7.5, 5.5, 3.5, 0.5, -1.5)):
            cyl(f"Window_{side}_{i}", 0.2, 0.08, glass, (x, 1.95 * side, 3.7), (math.radians(90), 0, 0))
        box(f"Door_{side}", (0.9, 0.06, 1.6), door_m, (9.2, 1.93 * side, 2.7))
    box("Ramp_Seam", (0.06, 3.0, 0.06), dark, (-4.6, 0, 1.75))

    # Боковые обтекатели шасси
    for side in (1, -1):
        loft(f"Sponson_{side}", [
            (3.8, 0.10, 0.15, 1.75, 2.0, 1.90 * side),
            (3.0, 0.50, 0.55, 1.80, 2.4, 1.95 * side),
            (-2.5, 0.50, 0.55, 1.80, 2.4, 1.95 * side),
            (-3.5, 0.10, 0.15, 1.85, 2.0, 1.90 * side),
        ], [belly], seg=24, steps=4)

    # Шасси: носовая стойка и две основные со спаренными колёсами
    def wheel(name, x, y, z, r, w):
        cyl(name, r, w, rubber, (x, y, z), (math.radians(90), 0, 0))
        cyl(name + "_Hub", r * 0.45, w + 0.02, metal, (x, y, z), (math.radians(90), 0, 0))

    cyl("NoseStrut", 0.1, 0.9, metal, (10.6, 0, 1.0))
    for y in (0.3, -0.3):
        wheel(f"NoseWheel_{y}", 10.6, y, 0.45, 0.45, 0.28)
    for side in (1, -1):
        cyl(f"MainStrut_{side}", 0.14, 1.6, metal, (-0.5, 2.3 * side, 1.15), (math.radians(-12 * side), 0, 0))
        for k, y in enumerate((2.25, 2.75)):
            wheel(f"MainWheel_{side}_{k}", -0.5, y * side, 0.55, 0.55, 0.38)
    cyl("TailSkid", 0.07, 0.8, metal, (-13.0, 0, 3.9))

    # Хвостовое оперение
    plate("Fin", [(-17.0, 4.9), (-20.6, 4.9), (-21.8, 9.0), (-20.4, 9.0)], 0.38, body)
    plate("Stabilizer", [(-13.6, -2.6), (-13.4, 2.6), (-14.8, 2.6), (-15.0, -2.6)], 0.14, body,
          axis="z", location=(0, 0, 5.0))

    # Несущий винт: 8 лопастей, диаметр 32 м
    hub_pos = (1.6, 0, 7.4)
    cyl("Mast", 0.35, 1.4, metal, (1.6, 0, 6.7))
    cyl("RotorHub", 0.95, 0.55, dark, hub_pos)
    cyl("HubCap", 0.5, 0.4, metal, (1.6, 0, 7.85), r2=0.15)
    for k in range(8):
        rot = (0, math.radians(2.0), math.radians(k * 45 + 10))
        box(f"Blade_{k}", (15.0, 0.85, 0.12), blade_m, hub_pos, rot, offset=(0.9 + 7.5, 0, 0))
        box(f"BladeTip_{k}", (0.6, 0.86, 0.13), yellow, hub_pos, rot, offset=(15.6, 0, 0))
        box(f"BladeArm_{k}", (1.0, 0.3, 0.25), metal, hub_pos, rot, offset=(1.0, 0, 0))

    # Рулевой винт: 5 лопастей, диаметр 7,6 м, справа по борту
    tr = (-20.9, -0.62, 7.6)
    cyl("TailHub", 0.35, 0.4, dark, tr, (math.radians(90), 0, 0))
    for k in range(5):
        box(f"TailBlade_{k}", (3.45, 0.06, 0.42), blade_m, tr, (0, math.radians(k * 72 + 15), 0),
            offset=(0.35 + 1.725, -0.12, 0))
    cyl("TailGearbox", 0.35, 1.3, body, (-20.9, -0.15, 7.6), (math.radians(90), 0, 0))

    # Опознавательные знаки ВВС России на хвостовой балке и киле
    for side in (1, -1):
        star(f"StarW_{side}", 0.58, white, (-11.0, 0.705 * side, 4.72), (math.radians(90 * side), 0, 0))
        star(f"StarR_{side}", 0.48, red, (-11.0, 0.715 * side, 4.72), (math.radians(90 * side), 0, 0))


# ---------- сцена и рендер ----------

def setup_scene():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.9

    ground_m = make_mat("Ground", (0.32, 0.33, 0.28), 0.9)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=200)
    link("Ground", bm, [ground_m])

    sun = bpy.data.lights.new("Sun", "SUN")
    sun.energy = 4.0
    sun.angle = math.radians(3)
    sun_ob = bpy.data.objects.new("Sun", sun)
    sun_ob.rotation_euler = (math.radians(40), math.radians(15), math.radians(-35))
    scene.collection.objects.link(sun_ob)

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.view_settings.view_transform = "AgX"
    return scene


def render_view(scene, name, loc, target, lens=35, ortho=None):
    cam = bpy.data.cameras.new(name)
    if ortho:
        cam.type = "ORTHO"
        cam.ortho_scale = ortho
    else:
        cam.lens = lens
    ob = bpy.data.objects.new(name, cam)
    scene.collection.objects.link(ob)
    ob.location = loc
    direction = Vector(target) - Vector(loc)
    ob.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = ob
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    scene.render.filepath = os.path.join(OUT, "renders", f"{name}.png")
    bpy.ops.render.render(write_still=True)


def main():
    build()
    # Экспорт только самой модели (без земли, света и камер)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "Mi-26.glb"), export_format="GLB",
                              export_apply=True)
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, "Mi-26.fbx"), use_mesh_modifiers=True)
    scene = setup_scene()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "Mi-26.blend"))
    render_view(scene, "front_3q", (30, 26, 12), (-2, 0, 4), lens=30)
    render_view(scene, "rear_3q", (-34, -26, 14), (-2, 0, 4), lens=30)
    render_view(scene, "side", (-3.5, 60, 5), (-3.5, 0, 5), ortho=48)
    render_view(scene, "top", (-3, 0, 60), (-3, 0, 0), ortho=50)


if __name__ == "__main__":
    main()
