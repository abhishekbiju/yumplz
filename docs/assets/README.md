# yumplz brand assets

Exported from the master 1024×1024 app icon in `Yumplz/Resources/Assets.xcassets/AppIcon.appiconset/`.

| File | Size | Use |
|------|------|-----|
| `icon/yumplz-app-icon-1024.png` | 1024×1024 | App Store Connect |
| `icon/yumplz-app-icon-512.png` | 512×512 | Marketing, social |
| `icon/yumplz-app-icon-256.png` | 256×256 | README, docs |
| `icon/yumplz-app-icon-128.png` | 128×128 | Favicon-scale |
| `icon/yumplz-app-icon-64.png` | 64×64 | Small UI embeds |

In-app logo scales live in `Yumplz/Resources/Assets.xcassets/Logo.imageset/`.

Regenerate marketing exports:

```bash
MASTER=Yumplz/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
for size in 512 256 128 64; do
  sips -z $size $size "$MASTER" --out "docs/assets/icon/yumplz-app-icon-${size}.png"
done
```
