# MaterialMotion

Pixel / Material 3 (Expressive) spring motion for SpringBoard app launches.
Targets **iOS 16+**. Builds for rootless, **roothide**, and rootful.

## Build with GitHub Actions
1. Push this folder to a GitHub repo (the `.github/workflows/build.yml` must be at the repo root).
2. Open the **Actions** tab -> *Build* runs automatically (or use *Run workflow*).
3. Download the `.deb` from the run's **Artifacts**:

| Artifact | Package arch | Use on |
|---|---|---|
| MaterialMotion-rootless | `iphoneos-arm64`  | Dopamine (rootless), palera1n rootless |
| MaterialMotion-roothide | `iphoneos-arm64e` | Dopamine **roothide** |
| MaterialMotion-rootful  | `iphoneos-arm`    | palera1n rootful, other rootful |

Tag a release (`git tag v0.1.0 && git push --tags`) and the debs are attached to a GitHub Release automatically.

## Local build
```
make package THEOS_PACKAGE_SCHEME=roothide   # needs roothide/theos as $THEOS
make package THEOS_PACKAGE_SCHEME=rootless
```

## Settings
Domain `com.example.materialmotion`, keys: `enabled`, `overlay`, `scheme` (0 Standard / 1 Expressive), `speed` (0.5-2.0).
See `com.example.materialmotion.plist.example`.
