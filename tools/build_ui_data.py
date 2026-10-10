#!/usr/bin/env python3
"""Compile original LabInterface defaults/objects and font metrics; no screenshots used."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
assets = ROOT / 'remake/assets/game'
root = ET.parse(assets / 'FiberTwig.li').getroot()
defaults = {}
for p in root.find('o').findall('p'):
    cls, key, value = (p.text or '').split(';', 2)
    defaults.setdefault(cls, {})[key] = value
nodes = []
for obj in root.findall('o')[1:]:
    cls = obj.get('c')
    node = dict(defaults.get(cls, {}), Class=cls)
    for p in obj.findall('p'):
        key, value = p.get('n'), p.text or ''
        if key.startswith('On'):
            node.setdefault(key, []).append(value)
        else:
            node[key] = value
    nodes.append(node)
font = ET.parse(assets / 'Arial12.xml').getroot()
charsets = []
cur = None
for p in font.iter('p'):
    if p.get('n') == 'AddCharSet':
        cur = {'charset': p.text, 'picture': '', 'metrics': []}
        charsets.append(cur)
    elif p.get('n') == 'AddPicture' and cur is not None:
        cur['picture'] = p.text
    elif p.get('n') == 'AddMetric' and cur is not None:
        cur['metrics'] = list(map(int, p.text.split()))
metrics = charsets[0]['metrics']
output = ROOT / 'remake/assets/data/interface.json'
output.write_text(json.dumps({'nodes': nodes, 'metrics': metrics, 'charsets': charsets}, indent=2))
print(f'{len(nodes)} controls -> {output}')
