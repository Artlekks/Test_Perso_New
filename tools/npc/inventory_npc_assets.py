"""Read-only source inventory; emits the audit as JSON, never edits PNGs."""
from pathlib import Path
import json, re
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]

def inventory():
    sheets = sorted(set(list((ROOT/'assets/sprites/npcs').rglob('*.png')) + list((ROOT/'assets/sprites/player').rglob('*.png')) + list((ROOT/'assets/sprites/npc/source').rglob('*.png'))))
    result = []
    frame_resources = list((ROOT/'assets/animations').glob('*.tres')) + list((ROOT/'data/npc/frames').glob('*.tres'))
    for sheet in sheets:
        relative = sheet.relative_to(ROOT).as_posix()
        image = Image.open(sheet).convert('RGBA')
        row = {'path':relative, 'width':image.width,'height':image.height,'magenta_pixels':sum(1 for r,g,b,a in image.get_flattened_data() if a and r>240 and b>240 and g<20),'kind':'player' if '/player/' in relative else 'npc','conversions':[]}
        for resource in frame_resources:
            text = resource.read_text()
            if relative not in text: continue
            source_ids = re.findall(r'path="res://'+re.escape(relative)+r'" id="([^\"]+)"',text)
            regions = {}
            for match in re.finditer(r'\[sub_resource type="AtlasTexture" id="([^\"]+)"\](.*?)(?=\[|$)',text,re.S):
                if any('ExtResource("'+id+'")' in match[2] for id in source_ids):
                    rect = re.search(r'region = Rect2\(([^)]+)\)',match[2])
                    if rect: regions[match[1]] = [float(value.strip()) for value in rect[1].split(',')]
            groups = []
            for match in re.finditer(r'"frames":\s*\[(.*?)\],\s*"loop":.*?"name":\s*&"([^\"]+)".*?"speed":\s*([\d.]+)',text,re.S):
                frame_ids = re.findall(r'SubResource\("([^\"]+)"\)',match[1])
                selected = [regions[id] for id in frame_ids if id in regions]
                if selected: groups.append({'name':match[2],'fps':float(match[3]),'rects':selected})
            resource_path = resource.relative_to(ROOT).as_posix()
            scenes = [p.relative_to(ROOT).as_posix() for p in (ROOT/'actors').rglob('*.tscn') if resource_path in p.read_text()]
            row['conversions'].append({'sprite_frames':resource_path,'animations':groups,'scenes':scenes})
        result.append(row)
    output = ROOT/'docs/npc/asset_inventory.json'
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(len(result),'character sheets;',sum(row['kind']=='npc' for row in result),'NPC sheets; all source pixels untouched')

if __name__ == '__main__': inventory()
