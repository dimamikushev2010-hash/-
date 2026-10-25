"""Собирает AllScripts.lua (все скрипты одним файлом) и PoseSystem.rbxlx (готовое место).

Запуск из папки PoseSystem:  python3 tools/build.py
Новый скрипт — добавь его имя в SCRIPTS ниже (порядок = порядок в AllScripts.lua).
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (папка, тип объекта, имена)
SCRIPTS = [
    ("ReplicatedStorage", "ModuleScript", ["PoseConfig", "InvisibilityConfig", "LaserConfig", "FlightConfig", "CubeConfig",
                                           "NPCConfig", "VehicleConfig", "SoundConfig", "WeatherConfig", "CityConfig",
                                           "DebugConfig", "WeaponConfig", "AbilityButton", "RigAnimator", "AbilityFx"]),
    ("ServerScriptService", "ModuleScript", ["AbilityRegistry", "NPCRegistry", "VehicleDefaults"]),
    ("ServerScriptService", "Script", ["PoseServer", "InvisibilityServer", "LaserServer", "FlightServer", "CubeServer",
                                       "NPCDemo", "NPCServer", "NPCDoors", "DayNightServer", "TrafficServer", "WeatherServer",
                                       "PhoneServer", "CityLifeServer", "DebugServer", "WeaponServer", "WantedServer"]),
    ("StarterPlayerScripts", "LocalScript", ["PoseClient", "InvisibilityClient", "LaserClient", "FlightClient", "CubeClient",
                                             "NPCClient", "VehicleClient", "PoliceDeskClient", "WeatherClient", "PhoneClient",
                                             "CityLifeClient", "DebugClient", "WeaponClient", "WantedClient"]),
]
EXT = {"ModuleScript": ".lua", "Script": ".server.lua", "LocalScript": ".client.lua"}
WHERE = {"ReplicatedStorage": "ReplicatedStorage", "ServerScriptService": "ServerScriptService",
         "StarterPlayerScripts": "StarterPlayer → StarterPlayerScripts"}


def source(folder, kind, name):
    with open(os.path.join(ROOT, folder, name + EXT[kind]), encoding="utf-8") as f:
        return f.read()


def build_all():
    total = sum(len(names) for _, _, names in SCRIPTS)
    out = [
        "-- ВСЕ СКРИПТЫ ИГРЫ. Каждый блок ниже — отдельный скрипт. Создай объект нужного типа в нужном месте,",
        "-- назови его точно как написано и вставь код блока целиком.",
        "-- Проще всего: открыть PoseSystem.rbxlx — там всё уже расставлено. Инструкция — STUDIO_CLAUDE.md.",
        "",
        f"-- СПИСОК ({total} скриптов):",
    ]
    n = 0
    for folder, kind, names in SCRIPTS:
        for name in names:
            n += 1
            out.append(f'--   {n:2}. {WHERE[folder]} > {kind} "{name}"')
    out.append("")
    n = 0
    for folder, kind, names in SCRIPTS:
        for name in names:
            n += 1
            out += ["", "-" * 70, f'-- {n}. {WHERE[folder]} > {kind} "{name}"', "-" * 70, "",
                    source(folder, kind, name).rstrip()]
    with open(os.path.join(ROOT, "AllScripts.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    return total


def build_place():
    ref = [0]

    def r():
        ref[0] += 1
        return f"RBX{ref[0]}"

    def cf(x, y, z):
        return (f'<CoordinateFrame name="CFrame"><X>{x}</X><Y>{y}</Y><Z>{z}</Z>'
                "<R00>1</R00><R01>0</R01><R02>0</R02><R10>0</R10><R11>1</R11><R12>0</R12>"
                "<R20>0</R20><R21>0</R21><R22>1</R22></CoordinateFrame>")

    def part(cls, name, pos, size, color, extra=""):
        return (f'<Item class="{cls}" referent="{r()}"><Properties>'
                f'<string name="Name">{name}</string><bool name="Anchored">true</bool>'
                f'{cf(*pos)}<Vector3 name="size"><X>{size[0]}</X><Y>{size[1]}</Y><Z>{size[2]}</Z></Vector3>'
                f'<Color3uint8 name="Color3uint8">{color}</Color3uint8>{extra}</Properties></Item>')

    def script(kind, folder, name):
        src = source(folder, kind, name)
        assert "]]>" not in src, name
        return (f'<Item class="{kind}" referent="{r()}"><Properties>'
                f'<string name="Name">{name}</string>'
                f'<ProtectedString name="Source"><![CDATA[{src}]]></ProtectedString>'
                "</Properties></Item>")

    def svc(cls, inner=""):
        return f'<Item class="{cls}" referent="{r()}"><Properties><string name="Name">{cls}</string></Properties>{inner}</Item>'

    def group(folder):
        return "".join(script(kind, f, name) for f, kind, names in SCRIPTS if f == folder for name in names)

    grey = (0xFF << 24) | (99 << 16) | (95 << 8) | 98
    white = (0xFF << 24) | (230 << 16) | (230 << 8) | 230
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" '
           'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           + svc("Workspace",
                 part("Part", "Baseplate", (0, -4, 0), (512, 8, 512), grey, '<bool name="Locked">true</bool>')
                 + part("SpawnLocation", "SpawnLocation", (0, 0.5, 0), (12, 1, 12), white))
           + svc("ReplicatedStorage", group("ReplicatedStorage"))
           + svc("ServerScriptService", group("ServerScriptService"))
           + svc("StarterPlayer", svc("StarterPlayerScripts", group("StarterPlayerScripts")))
           + "</roblox>")
    with open(os.path.join(ROOT, "PoseSystem.rbxlx"), "w", encoding="utf-8") as f:
        f.write(xml)


if __name__ == "__main__":
    count = build_all()
    build_place()
    print(f"AllScripts.lua и PoseSystem.rbxlx собраны: {count} скриптов")
    sys.exit(0)
