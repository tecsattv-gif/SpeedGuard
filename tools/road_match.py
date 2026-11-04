"""Descobre em que via fica cada radar e cada park (1.29.0).

Para cada radar (até 50 m) e cada park (até 300 m, só vias principais),
grava as vias mais perto: tipo (highway), número (ref), nome, se é de
mão única (e em que sentido) e o rumo do trecho. O app usa isso para
avisar só os radares/parks da via e do sentido onde o veículo anda,
sem depender do Overpass.

Uso (no workflow data.yml, por país):
  python3 road_match.py <pontos.osm.pbf> <vias-com-locais.osm.pbf> <saida.json>

<pontos> é o arquivo já filtrado (parks e radares) e <vias-com-locais> é o
mapa só com as vias, passado antes pelo "osmium add-locations-to-ways"
(a posição de cada nó vai dentro da via; não precisa de índice aqui).
"""
import json
import math
import os
import sys

import osmium

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_data import Pass1, Pass2  # noqa: E402

RADAR_R = 50.0  # m
PARK_R = 300.0  # m
PARK_ROADS = {"motorway", "trunk", "primary", "motorway_link", "trunk_link",
              "primary_link"}
CELL = 0.005  # grau (~550 m de latitude)


def cell(lat, lon):
    return (int(math.floor(lat / CELL)), int(math.floor(lon / CELL)))


def oneway(t, hw):
    o = t.get("oneway")
    if o == "-1":
        return -1
    if o in ("yes", "true", "1"):
        return 1
    if o == "no":
        return 0
    if hw in ("motorway", "motorway_link") or t.get("junction") == "roundabout":
        return 1
    return 0


class Points:
    def __init__(self):
        self.grid = {}  # célula -> [(chave, lat, lon, raio, só_principais)]
        self.best = {}  # chave -> {way_id: registro}

    def add(self, k, lat, lon, r, major):
        dlat = r / 110540 + CELL
        dlon = r / (111320 * max(0.2, math.cos(math.radians(lat)))) + CELL
        a0, o0 = cell(lat - dlat, lon - dlon)
        a1, o1 = cell(lat + dlat, lon + dlon)
        for a in range(a0, a1 + 1):
            for o in range(o0, o1 + 1):
                self.grid.setdefault((a, o), []).append((k, lat, lon, r, major))


class Roads(osmium.SimpleHandler):
    def __init__(self, pts):
        super().__init__()
        self.pts = pts

    def way(self, w):
        t = w.tags
        hw = t.get("highway")
        if not hw:
            return
        coords = []
        cand = {}
        grid = self.pts.grid
        for nd in w.nodes:
            loc = nd.location
            if not loc.valid():
                continue
            la, lo = loc.lat, loc.lon
            coords.append((la, lo))
            hit = grid.get(cell(la, lo))
            if hit:
                for p in hit:
                    cand[p[0]] = p
        if not cand or len(coords) < 2:
            return
        tags = None
        for k, plat, plon, r, major in cand.values():
            if major and hw not in PARK_ROADS:
                continue
            kx = 111320 * math.cos(math.radians(plat))
            ky = 110540.0
            best, bear = 1e18, 0.0
            for i in range(len(coords) - 1):
                ax = (coords[i][1] - plon) * kx
                ay = (coords[i][0] - plat) * ky
                bx = (coords[i + 1][1] - plon) * kx
                by = (coords[i + 1][0] - plat) * ky
                dx, dy = bx - ax, by - ay
                l2 = dx * dx + dy * dy
                tt = 0.0 if l2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / l2))
                px, py = ax + tt * dx, ay + tt * dy
                d = math.hypot(px, py)
                if d < best:
                    best = d
                    bear = (math.degrees(math.atan2(dx, dy)) + 360) % 360
            if best > r:
                continue
            if tags is None:
                tags = {"h": hw, "r": t.get("ref", "") or t.get("int_ref", ""),
                        "n": t.get("name", ""), "o": oneway(t, hw)}
            rec = dict(tags, d=round(best, 1), b=round(bear))
            self.pts.best.setdefault(k, {})[w.id] = rec


def main(points_file, roads_file, out_file):
    parks, radars = {}, {}
    p1 = Pass1(parks, radars)
    p1.apply_file(points_file, locations=True)
    if p1.rel_node:
        Pass2(p1.rel_node, radars).apply_file(points_file, locations=True)
    pts = Points()
    for r in radars.values():
        pts.add(f"r{r['id']}", r["lat"], r["lon"], RADAR_R, False)
    for p in parks.values():
        pts.add(f"p{p['i']}", p["a"], p["o"], PARK_R, True)
    Roads(pts).apply_file(roads_file)
    out = {"r": {}, "p": {}}
    for k, ways in pts.best.items():
        lst = sorted(ways.values(), key=lambda x: x["d"])[:3]
        out[k[0]][k[1:]] = lst
    with open(out_file, "w") as fh:
        json.dump(out, fh, ensure_ascii=False, separators=(",", ":"))
    print(f"{os.path.basename(points_file)}: vias de {len(out['r'])} radares "
          f"e {len(out['p'])} parks", flush=True)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
