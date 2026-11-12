"""GLB -> FBX avec Blender (module bpy). Script autonome, lancé à part.

    python convertir_fbx_blender.py modele.glb modele.fbx nom

Blender vit dans son propre environnement Python : il n'est jamais importé dans
le processus qui fait tourner PyTorch, pour éviter tout conflit de bibliothèques.
La texture est intégrée au FBX (« embed media »), ce que Mixamo attend.
"""
import sys


def main(glb: str, fbx: str, nom: str) -> None:
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    for image in bpy.data.images:
        image.name = f"{nom}_texture.png"
    bpy.ops.export_scene.fbx(
        filepath=fbx,
        use_selection=False,
        object_types={"MESH"},
        path_mode="COPY",
        embed_textures=True,
        add_leaf_bones=False,
        bake_anim=False,
        mesh_smooth_type="FACE",
    )


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
