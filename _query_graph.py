import json
from pathlib import Path

graph = json.loads(Path(r'c:\Projects\all in one\graphify-out\graph.json').read_text())
nodes = graph.get('nodes', [])
links = graph.get('links', [])

print(f'=== GRAPH STATS ===')
print(f'Total nodes: {len(nodes)}')
print(f'Total edges: {len(links)}')

# Find nodes related to ride dispatch
ride_keywords = ['ride', 'dispatch', 'hero', 'captain', 'fcm', 'push', 'booking', 'bike_taxi', 'tracking']
for kw in ride_keywords:
    matches = [n for n in nodes if kw.lower() in n.get('label','').lower()]
    print(f'\nNodes matching "{kw}": {len(matches)}')
    for m in matches[:8]:
        print(f'  - {m.get("label","?")}  [src={m.get("source_file","")}]')

# Find edges between key files
print('\n=== EDGES BETWEEN RIDE PACKAGE FILES ===')
for link in links:
    s = link.get('source','')
    t = link.get('target','')
    rel = link.get('relation','')
    if 'ride' in s.lower() or 'ride' in t.lower() or 'hero' in s.lower() or 'hero' in t.lower():
        if rel and rel != 'imports':
            print(f'  {s} --{rel}--> {t}')
