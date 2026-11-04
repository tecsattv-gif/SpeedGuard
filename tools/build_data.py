"""Gera a base própria de parks e radares do SpeedGuard.

Roda no GitHub Actions (workflow data.yml), uma vez por semana:
para cada país da Europa baixa o mapa oficial do Geofabrik, separa os
parks (áreas de descanso/serviço e estacionamentos de caminhão) e os
radares, e grava em pedaços de 2° x 2° (tiles):

  out/parks/<lat>_<lon>.json    out/radars/<lat>_<lon>.json   out/meta.json

O app baixa só os pedaços perto de onde está (raw.githubusercontent.com,
ramo "data"). Assim parks e radares não dependem dos servidores Overpass.

Uso: python3 build_data.py <arquivo.osm.pbf> [...]   (já filtrados pelo osmium)
"""
import json
import os
import sys
import time

import osmium

TILE = 2  # graus

PARK_TAGS = ("toilets", "toilets:wheelchair", "shower", "fuel", "restaurant",
             "food", "capacity:hgv", "fee", "hgv", "parking", "amenity",
             "highway", "name")
ENF_TYPES = {"maxspeed", "traffic_signals", "average_speed"}


def key(lat, lon):
    return f"{int((lat // TILE) * TILE)}_{int((lon // TILE) * TILE)}"


def is_park(t):
    if t.get("highway") in ("rest_area", "services"):
        return True
    if t.get("amenity") == "parking":
        return (t.get("hgv") in ("yes", "designated", "only")
                or t.get("parking") == "truck_stop")
    return False


class Pass1(osmium.SimpleHandler):
    """Parks (nós e vias, com o centro), radares soltos e relações."""

    def __init__(self, parks, radars):
        super().__init__()
        self.parks, self.radars = parks, radars
        self.rel_node = {}  # nó da câmera -> tags da relação

    def node(self, n):
        t = dict(n.tags)
        if not t:
            return
        loc = n.location
        if not loc.valid():
            return
        if is_park(t):
            self._park(f"n{n.id}", loc.lat, loc.lon, t)
        if t.get("highway") == "speed_camera" or "enforcement" in t:
            self.radars[n.id] = {"id": n.id, "lat": round(loc.lat, 6),
                                 "lon": round(loc.lon, 6), "tags": t}

    def way(self, w):
        t = dict(w.tags)
        if not is_park(t):
            return
        la = lo = 0.0
        c = 0
        for nd in w.nodes:
            if nd.location.valid():
                la += nd.location.lat
                lo += nd.location.lon
                c += 1
        if c:
            self._park(f"w{w.id}", la / c, lo / c, t)

    def relation(self, r):
        t = dict(r.tags)
        if t.get("type") != "enforcement" or t.get("enforcement") not in ENF_TYPES:
            return
        dev = frm = to = None
        for m in r.members:
            if m.type == "n":
                if m.role == "device" and dev is None:
                    dev = m.ref
                elif m.role == "from" and frm is None:
                    frm = m.ref
                elif m.role == "to" and to is None:
                    to = m.ref
        if t.get("enforcement") == "average_speed":
            # Velocidade média: início (from, ou a câmera) e fim (to) do trecho.
            start = frm if frm is not None else dev
            if start is not None:
                self.rel_node[start] = {**t, "section": "start"}
            if to is not None:
                self.rel_node[to] = {**t, "section": "end"}
            return
        node = dev if dev is not None else frm
        if node is not None:
            self.rel_node[node] = t

    def _park(self, pid, lat, lon, t):
        self.parks[pid] = {"i": pid, "a": round(lat, 6), "o": round(lon, 6),
                           "t": {k: v for k, v in t.items() if k in PARK_TAGS}}


class Pass2(osmium.SimpleHandler):
    """Posição e tags dos nós das câmeras das relações de fiscalização."""

    def __init__(self, want, radars):
        super().__init__()
        self.want, self.radars = want, radars

    def node(self, n):
        rel = self.want.get(n.id)
        if rel is None or not n.location.valid():
            return
        own = dict(n.tags)
        tags = {**rel, **own}
        tags["enforcement"] = rel["enforcement"]
        if "maxspeed" not in own and "maxspeed" in rel:
            tags["maxspeed"] = rel["maxspeed"]
        tags.pop("type", None)
        self.radars[n.id] = {"id": n.id, "lat": round(n.location.lat, 6),
                             "lon": round(n.location.lon, 6), "tags": tags}


def main(args):
    files = [a for a in args if not a.endswith(".json")]
    road_files = [a for a in args if a.endswith(".roads.json")]
    parks, radars = {}, {}
    for f in files:
        t0 = time.time()
        p1 = Pass1(parks, radars)
        p1.apply_file(f, locations=True)
        if p1.rel_node:
            Pass2(p1.rel_node, radars).apply_file(f, locations=True)
        print(f"{os.path.basename(f)}: {len(parks)} parks, {len(radars)} radares "
              f"no total ({time.time() - t0:.0f}s)", flush=True)

    # Vias de cada radar/park (road_match.py, 1.29.0): "rd" = lista das vias
    # mais perto (tipo, número, nome, mão única e rumo do trecho).
    nr = npk = 0
    for rf in road_files:
        try:
            with open(rf) as fh:
                rd = json.load(fh)
        except Exception as e:  # arquivo de um país que falhou
            print(f"{rf}: ignorado ({e})")
            continue
        for rid, lst in rd.get("r", {}).items():
            r = radars.get(int(rid))
            if r is not None and lst:
                r["rd"] = lst
                nr += 1
        for pid, lst in rd.get("p", {}).items():
            p = parks.get(pid)
            if p is not None and lst:
                p["rd"] = lst
                npk += 1
    print(f"Vias: {nr} radares e {npk} parks com a via marcada")

    out = {"parks": {}, "radars": {}}
    for p in parks.values():
        out["parks"].setdefault(key(p["a"], p["o"]), []).append(p)
    for r in radars.values():
        out["radars"].setdefault(key(r["lat"], r["lon"]), []).append(r)
    # Todo pedaço coberto ganha os dois arquivos (lista vazia se não tiver
    # nada): no app, "não existe" (404) quer dizer "fora da base" e ele usa
    # o Overpass; lista vazia quer dizer "coberto, sem nada aqui".
    covered = set(out["parks"]) | set(out["radars"])
    for kind in out:
        for k in covered:
            out[kind].setdefault(k, [])
    for kind, tiles in out.items():
        os.makedirs(f"out/{kind}", exist_ok=True)
        for k, items in tiles.items():
            with open(f"out/{kind}/{k}.json", "w") as fh:
                json.dump(items, fh, ensure_ascii=False, separators=(",", ":"))
    with open("out/meta.json", "w") as fh:
        json.dump({"date": time.strftime("%Y-%m-%d"), "tile": TILE,
                   "parks": len(parks), "radars": len(radars),
                   "parkTiles": sorted(out["parks"]),
                   "radarTiles": sorted(out["radars"])}, fh)
    print(f"Pronto: {len(parks)} parks, {len(radars)} radares, "
          f"{len(out['parks'])} + {len(out['radars'])} pedaços")


if __name__ == "__main__":
    main(sys.argv[1:])
