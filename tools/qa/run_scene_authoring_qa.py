"""Prepare a disposable real-editor save/reload fixture. Never edit source scenes."""
import argparse
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def prepare(destination: Path, negative_control: bool = False) -> None:
    destination = destination.resolve()
    sandbox = (ROOT / 'build' / 'mobile-web' / 'scene-authoring').resolve()
    if not destination.is_relative_to(sandbox) or destination == sandbox:
        raise ValueError('Fixture must be a child of build/mobile-web/scene-authoring')
    destination.mkdir(parents=True, exist_ok=False)
    sandbox.joinpath('.gdignore').write_text('')
    for folder in ('actors', 'assets', 'scripts', 'data'):
        shutil.copytree(ROOT / folder, destination / folder)
    for filename in ('project.godot', 'icon.svg'):
        shutil.copy2(ROOT / filename, destination / filename)
    project = destination.joinpath('project.godot').read_text(encoding='utf-8')
    if '[editor_plugins]' in project:
        raise ValueError('Update fixture setup explicitly if production editor plugins are added')
    project += '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/authoring_qa/plugin.cfg")\n'
    project = project.replace('config/name="FishingGame"', 'config/name="Disposable Scene Authoring QA"')
    destination.joinpath('project.godot').write_text(project, encoding='utf-8')
    addon = destination / 'addons' / 'authoring_qa'
    addon.mkdir(parents=True)
    addon.joinpath('plugin.cfg').write_text('[plugin]\nname="Authoring QA"\ndescription="Disposable editor regression"\nauthor="Project QA"\nversion="1"\nscript="plugin.gd"\n', encoding='utf-8')
    shutil.copy2(ROOT / 'scripts/qa/scene_instance_authoring_editor_qa.gd', addon / 'plugin.gd')
    destination.joinpath('AUTHORING_QA_DISPOSABLE').write_text('Only this project may be edited by the QA plugin.\n')
    if negative_control:
        for name in ('ExplorationPlayer_V2', 'FishingMasterStillWaterNPC', 'FishingCardMakerNPC'):
            scene = destination / 'actors' / (name + '.tscn')
            scene.write_text(scene.read_text().replace('[editable path="GroundPresentation"]', ''), encoding='utf-8')
    print(destination)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--negative-control', action='store_true', help='Reproduce missing declarations only in the disposable copy; editor QA must fail.')
    args = parser.parse_args()
    prepare(args.directory, args.negative_control)
