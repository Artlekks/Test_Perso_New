# Removed Files — Pass 1

These are the files removed from the 2026-09-27 Pass 1 candidate because they
were verified byte-for-byte duplicates of canonical UI assets.

- `assets/sprites/Fishing_Tech1.png`
- `assets/sprites/Fishing_Tech2.png`
- `assets/sprites/Fishing_Tech3.png`
- `assets/sprites/Fishing_Tech4.png`
- `assets/sprites/Menu_Command_Panel.png`
- `assets/sprites/Menu_Data_Bar.png`
- `assets/sprites/Menu_Data_Panel.png`
- `assets/sprites/Menu_Data_Preview_Panel.png`
- `assets/sprites/Menu_Hint_Info_Panel.png`
- `assets/sprites/Menu_Info_Panel.png`
- `assets/sprites/Menu_Status_Panel.png`
- `assets/sprites/Menu_Time_Panel.png`
- `assets/sprites/Menu_Validation_Panel.png`
- `assets/ui/fishing_menu/Icon_Frogger.png`
- `assets/ui/fishing_menu/Icon_Frogger_Dark.png`
- `assets/ui/fishing_menu/Icon_Minnow.png`
- `assets/ui/fishing_menu/Icon_Minnow_Dark.png`
- `assets/ui/fishing_menu/Icon_Spinner.png`
- `assets/ui/fishing_menu/Icon_Spinner_Dark.png`
- `assets/ui/fishing_menu/Icon_Topper.png`
- `assets/ui/fishing_menu/Icon_Topper_Dark.png`
- `assets/ui/fishing_menu/Icon_Winder.png`
- `assets/ui/fishing_menu/Icon_Winder_Dark.png`
- `assets/ui/fishing_menu/Icon_Worm.png`
- `assets/ui/fishing_menu/Icon_Worm_Dark.png`
- `assets/ui/fishing_menu/Icon_BigWaves_Dark.png`
- `assets/ui/fishing_menu/Icon_CalmWave_Dark.png`
- `assets/ui/fishing_menu/Icon_TsunamiWaves_Dark.png`

Their `.png.import` sidecars were removed at the same time when present.

## Packaging exclusions

The distributed source candidate also excludes:

- `.git/` — repository history
- `.godot/` — generated editor/import cache

## Deliberately preserved

- live/current resources;
- editable `.ase` / `.aseprite` files;
- model/source-art duplicate groups;
- gameplay/camera scripts other than removal of the automatic QA startup code.

The original uploaded ZIP remains the recovery source.
