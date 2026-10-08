"""Reviewable guide slicing; never infers direction or animation from pixels.

Closed magenta rectangles prove a frame. Open/connected guide regions are
reported for review rather than interpolated into an imaginary frame grid.
"""
import json
import copy
import argparse
from collections import defaultdict
from pathlib import Path
from PIL import Image
from build_npc_catalog import ROOT
NAMES = {
 '14bf342a':'Rod Angler', '21f7b2b2':'Seated Angler', '3cb9da3b':'Turban Trader',
 '43fb177f':'Horned Traveler', '4b58ab5e':'Blue Scarf Traveler', '68024840':'Lanky Worker',
 '6d89ee8e':'Small Bird', '78f1768c':'Brown Hat Traveler', '7d53dc6e':'Violet Armored Traveler',
 '7f1b19bc':'Blue Cap Stout Traveler', '837b6a03':'Short Robed Traveler', '8483df78':'Angler Action Sheet',
 '85f413fb':'Red Vest Seated Traveler', '8c3ae570':'Tall Hat Green Traveler', '9d2e2d78':'Feathered Traveler',
 'c3997e38':'Gold Armored Stout Traveler', 'cac2bbc2':'Red Hair Traveler', 'd1282736':'Dark Hat Traveler',
 'd7c2eeb9':'Purple Robed Traveler', 'e1466c4f':'Green Bearded Traveler', 'e5085f21':'Seated Fishing Pose',
 'e8e1ac56':'Green Cap Trader', 'ea87e795':'Red Cap Stout Traveler', 'f3876069':'Pale Hood Traveler',
 'f8644d09':'Purple Cape Stout Traveler', 'faacbedb':'Seated Light Angler', 'ff1c0303':'Green Turban Traveler',
 'ff6dba97':'Stout Bearded Traveler Variants'
}
REVIEWED_FIVE_VIEW = {'3cb9da3b','43fb177f','6d89ee8e','78f1768c','7d53dc6e','8c3ae570','9d2e2d78','cac2bbc2','d1282736','ff1c0303'}

def rectangles(image):
    w, h = image.size
    p = image.load()
    def guide(x, y):
        r,g,b,a=p[x,y]
        return a>0 and r>240 and g<20 and b>240
    horizontal={}
    for y in range(h):
        xs=[x for x in range(w) if guide(x,y)]
        if len(xs)>=7: horizontal[y]=xs
    result=[]
    for top,top_xs in horizontal.items():
        for bottom,bottom_xs in horizontal.items():
            if not 12<=bottom-top<=100: continue
            # Authored sprites occasionally overwrite one pixel of a vertical
            # guide. Top and bottom plus >90% of both sides prove the bounds.
            xs=[x for x in set(top_xs).intersection(bottom_xs) if sum(guide(x,y) for y in range(top,bottom+1))/(bottom-top+1)>=0.9]
            xs.sort()
            for left,right in zip(xs,xs[1:]):
                if right-left<6: continue
                if min(sum(guide(x,y) for x in range(left,right+1))/(right-left+1) for y in [top,bottom])<0.9: continue
                rect=[left+1,top+1,right-left-1,bottom-top-1]
                if any(guide(x,y) for x in range(left+1,right) for y in range(top+1,bottom)): continue
                if not image.crop((left+1,top+1,right,bottom)).getbbox(): continue
                if rect not in result: result.append(rect)
    return sorted(result,key=lambda r:(r[1],r[0]))

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--refresh-generated',action='store_true',help='Regenerate only manifests explicitly marked batch_generated; reviewed manifests remain untouched.')
    options=parser.parse_args()
    report=[]
    for path in sorted((ROOT/'assets/sprites/npc/source').glob('*.png')):
        image=Image.open(path).convert('RGBA')
        rects=rectangles(image)
        # All semantics remain explicitly unreviewed. The catalogue can expose
        # proven static poses without inventing a walk cycle or rear direction.
        id='placeholder_'+path.stem.split('-')[0]
        frames=[]; feet_x={}; feet_y={}
        for i,r in enumerate(rects):
            name=f'pose_{i:03d}'
            crop=image.crop((r[0],r[1],r[0]+r[2],r[1]+r[3]))
            box=crop.getbbox()
            foot_y=box[3]-1
            stance=[x for x in range(crop.width) for y in range(max(box[1],foot_y-2),foot_y+1) if crop.getpixel((x,y))[3]>0]
            feet_x[name]=(min(stance)+max(stance))/2
            feet_y[name]=crop.height-foot_y-1
            frames.append({'name':name,'fps':1,'rects':[r]})
        status='POSES_EXTRACTED_NEEDS_REVIEW' if frames else 'NEEDS_REVIEW'
        if frames:
            entry={'id':id,'name':NAMES.get(path.stem.split('-')[0], 'Placeholder '+path.stem.split('-')[0]), 'source':path.relative_to(ROOT).as_posix(),
                'animations':frames,'default_animation':frames[0]['name'],'mode':5,'directions':['UNCONFIRMED'],
                'collider':'humanoid_standard','tags':['placeholder','role_unconfirmed'],'note':'Closed guide cells preserved as individually inspectable static poses. Direction, row animation/timing and special role UNCONFIRMED; open guides NEEDS_REVIEW. No walk cycle invented.',
                'profile_overrides':{'animation_feet_from_bottom_px':json.dumps(feet_y), 'animation_feet_from_left_px':json.dumps(feet_x)}}
            # Visually reviewed common BOF layout: N/NE/E/SE/S standing
            # poses, followed by six NE and six SE walking cells. Only this
            # exact reviewed layout is grouped; mixed actions stay static.
            rows=defaultdict(list)
            for r in rects: rows[r[1]].append(r)
            first_row=min(rows)
            standing=sorted([r for r in rects if r[1]<first_row+12],key=lambda r:r[0])
            walking=[r for r in rects if r not in standing]
            if path.stem.split('-')[0] in REVIEWED_FIVE_VIEW and len(rects)==17 and len(standing)==5 and len(walking)==12:
                groups=[('idle_'+d,[r],1) for d,r in zip(['n','ne','e','se','s'],standing)]
                walking.sort(key=lambda r:r[0])
                groups += [('walk_ne',walking[:6],8),('walk_se',walking[6:],8)]
                entry['animations']=[{'name':n,'fps':fps,'rects':rs} for n,rs,fps in groups]
                entry['default_animation']='idle_s'
                entry['directions']=['N','NE','E','SE','S']
                entry['movement']=True
                entry['profile_overrides']['directional_animation_prefixes']='{"idle": "idle_", "walk": "walk_"}'
                entry['profile_overrides']['default_directional_pose']='"idle"'
                # The grouped frames retain the common authored cell anchor.
                for field,values in [('animation_feet_from_bottom_px',feet_y),('animation_feet_from_left_px',feet_x)]:
                    mapping={}
                    for n,rs,fps in groups:
                        points=[values[f'pose_{rects.index(r):03d}'] for r in rs]
                        mapping[n]=sorted(points)[len(points)//2]
                    entry['profile_overrides'][field]=json.dumps(mapping)
                entry['note']='Reviewed five standing views N/NE/E/SE/S and NE/SE walk strips (8 FPS). Missing west views use nearest authored direction, no fabricated frames. Special role UNCONFIRMED.'
                if path.stem.startswith('6d89ee8e'):
                    for animation in entry['animations']: animation['name']=animation['name'].replace('walk_', 'fly_')
                    entry['collider']='ambient_creature'
                    entry['shadow']='small_creature'
                    entry['movement']=False
                    entry['profile_overrides']['directional_animation_prefixes']='{"idle": "idle_", "fly": "fly_"}'
                    for field in ['animation_feet_from_bottom_px','animation_feet_from_left_px']:
                        entry['profile_overrides'][field]=entry['profile_overrides'][field].replace('walk_', 'fly_')
                    entry['profile_overrides']['shadow_width']='0.10'
                    entry['profile_overrides']['shadow_depth']='0.10'
                    entry['note']='Reviewed five standing bird views and two flapping strips fly NE/SE (8 FPS). No walking animation invented. Master role UNCONFIRMED.'
                status='CONVERTED_REVIEWED_GROUPS'
            target=path.with_suffix('.npc.json')
            # Reviewed manifests are user-authored data and must never be replaced.
            if not target.exists() or (options.refresh_generated and json.loads(target.read_text()).get('batch_generated',False)):
                entry['batch_generated']=True
                if path.stem.startswith('ff6dba97'):
                    variants=[]
                    for color,subset in [('blue',frames[:8]),('orange',frames[8:])]:
                        variant=copy.deepcopy(entry)
                        variant['id'] += '_'+color
                        variant['name']='Stout Bearded Traveler ('+color+')'
                        variant['animations']=subset
                        variant['default_animation']=subset[0]['name']
                        variants.append(variant)
                    entry={'batch_generated':True,'entries':variants}
                target.write_text(json.dumps(entry,indent=2)+'\n',encoding='utf-8')
        report.append({'source':path.relative_to(ROOT).as_posix(),'dimensions':image.size,'status':status,'closed_frames':len(frames), 'role':'UNCONFIRMED','direction':'N/NE/E/SE/S; west absent' if status=='CONVERTED_REVIEWED_GROUPS' else 'NEEDS_REVIEW','animation':('idle + fly NE/SE' if path.stem.startswith('6d89ee8e') else 'idle + walk NE/SE') if status=='CONVERTED_REVIEWED_GROUPS' else 'NEEDS_REVIEW'})
    target=ROOT/'docs/npc/batch_coverage.json'
    target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('Source sheets:',len(report),'with proven poses:',sum(r['closed_frames']>0 for r in report),'need review:',sum(r['closed_frames']==0 for r in report))

if __name__=='__main__': main()
