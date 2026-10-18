#!/usr/bin/env python3
"""Generate all app-branding images from the latest uploaded IfallMusic logo.

The committed upload is the single source of truth. Its central Spotify + YouTube
Music mark is cropped with generous padding, then exported to the Android, Apple,
web, desktop and in-app slots. Run after replacing the uploaded source image:

    python3 scripts/generate_logo_assets.py

Requires Pillow (python3 -m pip install Pillow).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "file_000000006f348208a9e754d805017c9c.png"
ANDROID_RES = ROOT / "android/app/src/main/res"

ANDROID_MIPMAP = {"mdpi": 48, "hdpi": 72, "xhdpi": 96,
                  "xxhdpi": 144, "xxxhdpi": 192}
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60, "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120, "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180, "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152, "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024@1x.png": 1024, "Icon-App-1024x1024@1x.png": 1024,
}
MACOS_ICONS = {"app_icon_16.png": 16, "app_icon_32.png": 32,
               "app_icon_64.png": 64, "app_icon_128.png": 128,
               "app_icon_256.png": 256, "app_icon_512.png": 512,
               "app_icon_1024.png": 1024}
WEB_ICONS = {"Icon-192.png": 192, "Icon-512.png": 512,
             "Icon-maskable-192.png": 192, "Icon-maskable-512.png": 512}


def save(image: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.Resampling.LANCZOS).save(
        path, "PNG", optimize=True)
    print(path.relative_to(ROOT))


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Uploaded logo not found: {SOURCE}")

    uploaded = Image.open(SOURCE).convert("RGB")
    width, height = uploaded.size
    if width < 500 or height < 500:
        raise SystemExit(f"Uploaded logo must be at least 500x500: {uploaded.size}")

    # The uploaded graphic is a black square. Keep only the combined Spotify +
    # YouTube Music symbol and a small part of its black surround, so the mark
    # reads clearly at launcher size and does not shrink behind empty margins.
    side = int(min(width, height) * 0.585)
    center_x, center_y = width // 2, height // 2
    left, top = center_x - side // 2, center_y - side // 2
    mark = uploaded.crop((left, top, left + side, top + side)).convert("RGBA")
    mark = mark.resize((1024, 1024), Image.Resampling.LANCZOS)

    # Both legacy asset names are still referenced throughout the Flutter UI;
    # make them identical to the submitted mark to keep every existing screen
    # and splash path in sync without risky code-path renames.
    for name in ("sidify_logo.png", "sidify_mark.png"):
        save(mark, ROOT / "assets/images" / name, 1024)

    for density, size in ANDROID_MIPMAP.items():
        save(mark, ANDROID_RES / f"mipmap-{density}/ic_launcher.png", size)
    save(mark, ANDROID_RES / "drawable/sidify_splash_logo.png", 512)

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in IOS_ICONS.items():
        target = ios / name
        if target.exists() or name.startswith("Icon-App-1024"):
            save(mark, target, size)
    launch_images = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for name in ("LaunchImage.png", "LaunchImage@2x.png", "LaunchImage@3x.png"):
        if (launch_images / name).exists():
            save(mark, launch_images / name, 512)

    macos = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for name, size in MACOS_ICONS.items():
        save(mark, macos / name, size)

    for name, size in WEB_ICONS.items():
        # A maskable icon needs a safe-zone margin inside the black canvas.
        icon = mark
        if "maskable" in name:
            canvas = Image.new("RGBA", mark.size, (8, 7, 13, 255))
            inner = mark.resize((int(mark.width * 0.72), int(mark.height * 0.72)),
                                Image.Resampling.LANCZOS)
            canvas.alpha_composite(inner, ((mark.width - inner.width) // 2,
                                           (mark.height - inner.height) // 2))
            icon = canvas
        save(icon, ROOT / "web/icons" / name, size)
    save(mark, ROOT / "web/favicon.png", 64)
    save(mark, ROOT / "fastlane/metadata/android/en-US/images/icon.png", 512)

    # Keep the Play listing's feature artwork aligned with the in-app mark.
    feature_graphic = ROOT / "fastlane/metadata/android/en-US/images/featureGraphic.png"
    if feature_graphic.exists():
        graphic = Image.open(feature_graphic).convert("RGBA")
        if graphic.size == (1024, 500):
            tile = mark.resize((280, 280), Image.Resampling.LANCZOS)
            graphic.alpha_composite(tile, (80, 110))
            graphic.save(feature_graphic, "PNG", optimize=True)
            print(feature_graphic.relative_to(ROOT))

    # Regenerate desktop icons from the same mark.
    windows_ico = ROOT / "windows/runner/resources/app_icon.ico"
    windows_ico.parent.mkdir(parents=True, exist_ok=True)
    ico_source = ROOT / ".cache/ifallmusic_app_icon.png"
    ico_source.parent.mkdir(parents=True, exist_ok=True)
    mark.resize((256, 256), Image.Resampling.LANCZOS).save(ico_source, "PNG")
    Image.open(ico_source).save(windows_ico, "ICO",
                                sizes=[(16, 16), (32, 32), (48, 48), (64, 64),
                                       (128, 128), (256, 256)])
    ico_source.unlink(missing_ok=True)
    print(windows_ico.relative_to(ROOT))
    save(mark, ROOT / "linux/runner/resources/app_icon.png", 256)


if __name__ == "__main__":
    main()
