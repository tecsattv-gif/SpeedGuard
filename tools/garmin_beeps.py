"""Gera os bipes do Garmin (assets/sounds/garmin). Tom agudo (1,5-3 kHz, onde
o alto-falante pequeno do Garmin rende mais), com harmônicos e entrada/saída
suaves (sem estalo), no volume máximo. Uso: python3 tools/garmin_beeps.py"""
import math, struct, os

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds', 'garmin')


def tone(freq, secs, attack=0.006, release=0.035):
    n = int(RATE * secs)
    out = []
    for i in range(n):
        t = i / RATE
        v = (math.sin(2 * math.pi * freq * t)
             + 0.30 * math.sin(2 * math.pi * 2 * freq * t)
             + 0.12 * math.sin(2 * math.pi * 3 * freq * t))
        env = min(1.0, t / attack, (secs - t) / release)
        out.append(v * env)
    return out


def gap(secs):
    return [0.0] * int(RATE * secs)


def save(name, samples):
    peak = max(abs(x) for x in samples)
    pcm = b''.join(struct.pack('<h', int(x / peak * 32000)) for x in samples)
    hdr = (b'RIFF' + struct.pack('<I', 36 + len(pcm)) + b'WAVEfmt '
           + struct.pack('<IHHIIHH', 16, 1, 1, RATE, RATE * 2, 2, 16)
           + b'data' + struct.pack('<I', len(pcm)))
    with open(os.path.join(OUT, name + '.wav'), 'wb') as f:
        f.write(hdr + pcm)


# Avisos de radar (1 = mais longe ... 5 = mais perto): cada vez mais agudo.
for i, f in enumerate([1568, 1760, 1976, 2217, 2637], start=1):
    save('step%d' % i, tone(f, 0.28))
# Último aviso: dois bipes.
save('step6', tone(2794, 0.16) + gap(0.07) + tone(2794, 0.16))
# Acima do limite do radar: seis bipes rápidos.
fast = []
for _ in range(6):
    fast += tone(2960, 0.09) + gap(0.05)
save('beep_fast', fast)
# Fim da contagem dos 30 s ("velocidade excedida"): bipe longo.
save('long', tone(2093, 1.3, release=0.06))
