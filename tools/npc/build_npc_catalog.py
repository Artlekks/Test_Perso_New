"""Development-only, deterministic NPC ingestion. Never rewrites source PNGs.

Run python tools/npc/build_npc_catalog.py from the project root. Existing
SpriteFrames are reused. New sheets require an explicit reviewed JSON manifest;
directions, timing and frame boundaries are never guessed from artwork.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_FPS = 8.0

def write(path, text):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")

def string(value):
    return json.dumps(value)

def casting_metadata(entry_id):
    # Separate provisional world casting from artwork and gameplay providers.
    path = ROOT / 'data/npc/world_population_v1.json'
    metadata = json.loads(path.read_text(encoding='utf-8')).get('entries', {}).get(entry_id, {}) if path.exists() else {}
    return ''.join(key+' = '+('PackedStringArray('+', '.join(map(string, value))+')' if isinstance(value, list) else string(value))+'\n' for key,value in metadata.items())

def frames_for(entry):
    if entry.get("existing_frames"):
        assert (ROOT / entry["existing_frames"]).is_file()
        return entry["existing_frames"]
    from PIL import Image
    source = ROOT / entry["source"]
    image = Image.open(source).convert("RGBA")
    text = '[gd_resource type="SpriteFrames" format=3]\n[ext_resource type="Texture2D" path="res://' + entry["source"] + '" id="sheet"]\n'
    animations = []
    frame_index = 0
    for animation in entry["animations"]:
        refs = []
        for rect in animation["rects"]:
            x, y, w, h = map(int, rect)
            assert x >= 0 and y >= 0 and w > 0 and h > 0 and x+w <= image.width and y+h <= image.height
            if entry.get("magenta_border"):
                border = [image.getpixel((px,y)) for px in range(x,x+w)] + [image.getpixel((px,y+h-1)) for px in range(x,x+w)] + [image.getpixel((x,py)) for py in range(y,y+h)] + [image.getpixel((x+w-1,py)) for py in range(y,y+h)]
                assert all(r > 240 and g < 20 and b > 240 and a > 0 for r,g,b,a in border), "Unproven guide rectangle"
                x,y,w,h = x+1,y+1,w-2,h-2
            assert w > 0 and h > 0
            assert not any(a and r > 240 and g < 20 and b > 240 for r,g,b,a in image.crop((x,y,x+w,y+h)).getdata()), "Guide pixels inside extracted frame"
            frame_index += 1
            text += f'[sub_resource type="AtlasTexture" id="frame{frame_index}"]\natlas = ExtResource("sheet")\nregion = Rect2({x}, {y}, {w}, {h})\n'
            refs.append('{"duration": 1.0, "texture": SubResource("frame%d")}' % frame_index)
        animations.append('{"name": &%s, "speed": %s, "loop": true, "frames": [%s]}' % (string(animation["name"]), animation.get("fps", DEFAULT_FPS), ', '.join(refs)))
    text += '[resource]\nanimations = [' + ',\n'.join(animations) + ']\n'
    path = 'data/npc/frames/' + entry['id'] + '.tres'
    write(path, text)
    return path

def build():
    manifest = json.loads((ROOT / 'tools/npc/catalog_manifest.json').read_text())
    entries = manifest['entries']
    for path in sorted((ROOT / 'assets/sprites/npc/source').glob('*.npc.json')):
        reviewed = json.loads(path.read_text())
        entries.extend(reviewed['entries'] if 'entries' in reviewed else [reviewed])
    mapped_sources = {entry.get('source') for entry in entries}
    for path in sorted((ROOT / 'assets/sprites/npc/source').glob('*.png')):
        if path.relative_to(ROOT).as_posix() not in mapped_sources:
            print('UNCONFIRMED source awaiting reviewed .npc.json:', path.name)
    ids = [entry['id'] for entry in entries]
    assert all(re.fullmatch(r'[a-z][a-z0-9_]*', id) for id in ids), 'NPC IDs must be lowercase names, not paths'
    assert len(ids) == len(set(ids)), 'Duplicate NPC ID'
    for family, values in manifest['colliders'].items():
        write('data/npc/colliders/' + family + '.tres', '[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="res://scripts/npc/npc_collider_profile.gd" id="script"]\n[resource]\nscript = ExtResource("script")\nfamily = &'+string(family)+'\nradius = '+str(values[0])+'\nheight = '+str(values[1])+'\nhard_blocking = '+str(values[2]).lower()+'\n')
    catalog = '[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="res://scripts/npc/npc_catalog.gd" id="script"]\n'
    for entry in entries:
        frames = frames_for(entry)
        grounding = ''
        if entry.get('grounding_template'):
            raw = (ROOT/entry['grounding_template']).read_text()
            grounding = raw.split('[resource]\n',1)[1]
            grounding = '\n'.join(line for line in grounding.splitlines() if not line.startswith(('script =', 'shadow_family ='))) + '\n'
        profile = '[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="res://scripts/npc/npc_visual_profile.gd" id="script"]\n[ext_resource type="SpriteFrames" path="res://'+frames+'" id="frames"]\n[ext_resource type="Resource" path="res://data/npc/colliders/'+entry['collider']+'.tres" id="collider"]\n[resource]\nscript = ExtResource("script")\n' + grounding
        profile += 'npc_id = &'+string(entry['id'])+'\ndevelopment_name = '+string(entry['name'])+'\nsprite_frames = ExtResource("frames")\ncollider_profile = ExtResource("collider")\ndefault_animation = &'+string(entry['default_animation'])+'\ndirectional_mode = '+str(entry['mode'])+'\navailable_directions = PackedStringArray('+', '.join(map(string,entry['directions']))+')\nrole_tags = PackedStringArray('+', '.join(map(string,entry['tags']))+')\nshadow_family = '+string({'humanoid':'humanoid_standard','small_creature':'critter'}.get(entry.get('shadow','humanoid_standard'),entry.get('shadow','humanoid_standard')))+'\nmovement_capability = '+str(entry.get('movement',False)).lower()+'\n'
        for key,value in entry.get('profile_overrides',{}).items():
            # Replace inherited entries instead of duplicating resource properties.
            profile = '\n'.join(line for line in profile.split('\n') if not line.startswith(key+' ='))+'\n'
            profile += key+' = '+value+'\n'
        profile_path = 'data/npc/profiles/'+entry['id']+'.tres'
        scene_path = 'actors/npc/catalog/NPC_'+entry['id']+'.tscn'
        entry_path = 'data/npc/catalog/'+entry['id']+'.tres'
        write(profile_path, profile)
        write(scene_path, '[gd_scene load_steps=4 format=3]\n[ext_resource type="PackedScene" path="res://actors/npc/NPCActor.tscn" id="base"]\n[ext_resource type="Resource" path="res://'+profile_path+'" id="profile"]\n[ext_resource type="SpriteFrames" path="res://'+frames+'" id="frames"]\n[node name="NPC_'+entry['id']+'" instance=ExtResource("base")]\nvisual_profile = ExtResource("profile")\n[node name="GroundPresentation" parent="." index="1"]\nprofile = ExtResource("profile")\n[node name="AnimatedSprite3D" parent="GroundPresentation/VisualAnchor" index="0"]\nsprite_frames = ExtResource("frames")\nanimation = &'+string(entry['default_animation'])+'\n[editable path="GroundPresentation"]\n')
        write(entry_path, '[gd_resource type="Resource" format=3]\n[ext_resource type="Script" path="res://scripts/npc/npc_catalog_entry.gd" id="script"]\n[ext_resource type="PackedScene" path="res://'+scene_path+'" id="scene"]\n[ext_resource type="Resource" path="res://'+profile_path+'" id="profile"]\n[resource]\nscript = ExtResource("script")\nid = &'+string(entry['id'])+'\nscene = ExtResource("scene")\nprofile = ExtResource("profile")\ndevelopment_note = '+string(entry['note'])+'\n')
        target = ROOT / entry_path
        write(entry_path, target.read_text(encoding='utf-8') + casting_metadata(entry['id']))
        catalog += '[ext_resource type="Resource" path="res://'+entry_path+'" id="'+entry['id']+'"]\n'
    catalog += '[resource]\nscript = ExtResource("script")\nentries = Array[ExtResource("res://scripts/npc/npc_catalog_entry.gd")](['+ ', '.join('ExtResource("'+entry['id']+'")' for entry in entries) + '])\n'
    # Typed resource arrays use a script external resource, not a path token.
    catalog = catalog.replace('[resource]\n','[ext_resource type="Script" path="res://scripts/npc/npc_catalog_entry.gd" id="entry_script"]\n[resource]\n').replace('ExtResource("res://scripts/npc/npc_catalog_entry.gd")','ExtResource("entry_script")')
    write('data/npc/catalog/npc_catalog.tres',catalog)
    print('Generated',len(entries),'profiles/scenes/catalog entries; reused existing SpriteFrames where available.')

if __name__ == '__main__':
    build()
