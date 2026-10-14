#!/usr/bin/env python3
"""Paint the IfallMusic mascot across every icon slot the app ships with.

One master artwork (the chubby round "motu golu molu" character) is resized into
every platform's launcher icon, splash logo, web icon and in-app asset, so the
same face greets the listener everywhere: home screen, splash, notifications,
web and desktop.

    python3 scripts/generate_logo_assets.py

Requires Pillow (`pip install --break-system-packages Pillow`).
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets" / "images" / "ifall_motu_master.png"
HEART = ROOT / "assets" / "images" / "ifall_motu_heart.png"

ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Android launcher icon, per density bucket.
ANDROID_MIPMAP = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# iOS / macOS app icon sets (filename -> pixel size).
IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024@1x.png": 1024,
    "Icon-App-1024x1024@1x.png": 1024,
}

MACOS_ICONS = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

WEB_ICONS = {
    "Icon-192.png": 192,
    "Icon-512.png": 512,
    "Icon-maskable-192.png": 192,
    "Icon-maskable-512.png": 512,
}


def square_logo(src: Image.Image, size: int, *, maskable: bool = False) -> Image.Image:
    """Resize `src` to `size`, letterboxing so the whole character survives."""
    src = src.convert("RGBA")
    if maskable:
        # A maskable icon is cropped to a circle by some launchers: keep the
        # character inside the safe zone by scaling it down inside the frame.
        inner = int(size * 0.72)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 255))
        canvas.alpha_composite(src.resize((inner, inner), Image.LANCZOS),
                               ((size - inner) // 2, (size - inner) // 2))
        return canvas
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(src.resize((size, size), Image.LANCZOS), (0, 0))
    return canvas


def write(path: Path, image: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, "PNG", optimize=True)
    print(f"  {path.relative_to(ROOT)}")


def main() -> int:
    if not MASTER.exists():
        print(f"missing master artwork: {MASTER}", file=sys.stderr)
        return 1
    if not HEART.exists():
        print(f"missing heart artwork: {HEART}", file=sys.stderr)
        return 1

    master = Image.open(MASTER).convert("RGBA")
    heart = Image.open(HEART).convert("RGBA")

    print("in-app assets")
    write(ROOT / "assets" / "images" / "ifall_logo.png",
          master.resize((512, 512), Image.LANCZOS))
    write(ROOT / "assets" / "images" / "ifall_splash.png",
          master.resize((512, 512), Image.LANCZOS))
    write(ROOT / "assets" / "images" / "liked_songs_motu.png",
          heart.resize((512, 512), Image.LANCZOS))
    # The legacy file names stay put so older code paths keep resolving.
    for legacy in ("saxify_logo.png", "saxify_splash.png"):
        write(ROOT / "assets" / "images" / legacy,
              master.resize((512, 512), Image.LANCZOS))

    print("android")
    for density, size in ANDROID_MIPMAP.items():
        write(ANDROID_RES / f"mipmap-{density}" / "ic_launcher.png",
              square_logo(master, size))
    # Notification + splash drawables.
    write(ANDROID_RES / "drawable" / "ifall_logo_bg.png",
          square_logo(master, 192))
    write(ANDROID_RES / "drawable" / "ifall_splash_logo.png",
          square_logo(master, 200))
    for legacy in ("saxify_logo_bg.png", "saxify_splash_logo.png"):
        target = ANDROID_RES / "drawable" / legacy
        if target.exists():
            write(target, square_logo(master, 200))

    print("ios")
    ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in IOS_ICONS.items():
        target = ios_dir / name
        if not target.exists() and name not in ("Icon-App-1024@1x.png",
                                                "Icon-App-1024x1024@1x.png"):
            continue
        write(target, square_logo(master, size))

    print("macos")
    macos_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for name, size in MACOS_ICONS.items():
        write(macos_dir / name, square_logo(master, size))

    print("web")
    for name, size in WEB_ICONS.items():
        write(ROOT / "web" / "icons" / name,
              square_logo(master, size, maskable="maskable" in name))
    write(ROOT / "web" / "favicon.png", square_logo(master, 64))

    # Windows: a multi-resolution .ico built from the same master.
    print("windows")
    ico = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    tmp = ROOT / ".cache" / "ifall_icon_tmp.png"
    tmp.parent.mkdir(parents=True, exist_ok=True)
    master.resize((256, 256), Image.LANCZOS).save(tmp, "PNG")
    ico.parent.mkdir(parents=True, exist_ok=True)
    Image.open(tmp).save(ico, "ICO",
                         sizes=[(16, 16), (32, 32), (48, 48), (64, 64),
                                (128, 128), (256, 256)])
    print(f"  {ico.relative_to(ROOT)}")
    os.remove(tmp)

    # Linux desktop icon.
    linux_icon = ROOT / "linux" / "runner" / "resources" / "app_icon.png"
    linux_icon.parent.mkdir(parents=True, exist_ok=True)
    master.resize((256, 256), Image.LANCZOS).save(linux_icon, "PNG")
    print(f"  {linux_icon.relative_to(ROOT)}")

    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
