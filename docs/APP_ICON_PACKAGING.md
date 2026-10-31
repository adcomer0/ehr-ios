# Own icon packaging

The native candidate builder accepts `--app-icon PATH` for an owner's original
opaque 1024 by 1024 PNG. Combine it with `--display-name "EHR Among Us"`; the
existing explicit bundle identifier, profile and signing checks still apply.
The visible label and icon do not change the runtime game version or app's
credential namespace.

The input must be a regular, non-symlink static 8-bit RGB/RGBA PNG of at most
32 MiB. Framing and checksums are checked before Apple's ImageIO decoder.
Transparent pixels are rejected, including a single transparent pixel in an
otherwise opaque image. Preparation occurs before the builder reads or copies
the game bundle. It uses an immutable input snapshot and preserves that source.

An original Swift helper normalizes the artwork into opaque sRGB PNGs without
carrying its embedded metadata. It emits iPhone and iPad icon sizes, including
120/180-pixel iPhone and 152/167-pixel iPad variants. `EHRBrandIcon.png` contains
the same normalized art at 1024 pixels for the UIKit interface.

The builder selects namespaced icon files using `CFBundleIcons` and its iPad
variant, clearing inherited primary and alternate icon references. It preserves
the existing `Assets.car`, which can contain unrelated native interface assets.
Apple documents that [primary icon files may live in the bundle](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleicons/cfbundleprimaryicon/cfbundleiconfiles).

The private build manifest records the input image hash and every generated
file's dimensions and hash. No original game icon is used to generate these
variants or added to the repository. A signed runtime check verifies code and
startup; the Home Screen icon and cached icon refresh still require a physical
device observation.
