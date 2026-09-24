# Building with your own Apple Developer team

The tracked config is the **shipping identity** (`Configs/Release.xcconfig`):

```
DEVELOPMENT_TEAM = 9ZYQ3XT8L9
MESHY_BASE_BUNDLE_ID = com.meshed.app
PRODUCT_BUNDLE_IDENTIFIER = $(MESHY_BASE_BUNDLE_ID)
APP_GROUP_ID = group.$(MESHY_BASE_BUNDLE_ID)
```

The Xcode project itself only references `$(DEVELOPMENT_TEAM)` and `$(PRODUCT_BUNDLE_IDENTIFIER)`, and the entitlements use `$(APP_GROUP_ID)`, so these three lines are the only place the identity lives.

**Anyone building on a different team (e.g. Nick on `QH3CULU8Z7`):**

1. `cp Configs/Local.xcconfig.example Configs/Local.xcconfig` (the copy is gitignored).
2. Set your `DEVELOPMENT_TEAM`. The bundle ID and app group follow from it.
3. Build. `Local.xcconfig` is included last by both Debug and Release, so it overrides the shipping values on your machine only.

**Don't** change the team or bundle ID in Xcode's Signing & Capabilities UI. That writes them into `project.pbxproj`, which is tracked, and breaks everyone else's build. (That is what flipped the team between `9ZYQ3XT8L9` and `QH3CULU8Z7` before.) If Xcode does it anyway, discard the `project.pbxproj` change before committing.

The share extension and the app must share `group.<bundle id>`. Both derive it from the bundle ID, so a local bundle ID gets a matching local app group automatically. Register the group on your team the first time Xcode asks.

**Old `Local.xcconfig` files:** if yours sets `APP_GROUP_ID = group.$(PRODUCT_BUNDLE_IDENTIFIER)`, change it to `MESHY_BASE_BUNDLE_ID = …` plus `APP_GROUP_ID = group.$(MESHY_BASE_BUNDLE_ID)`, as in the example. Otherwise the share extension gets `group.<id>.ShareExtension`, and signing fails with "doesn't match the entitlements file's value for … application-groups".

## First-time signing on a team (App Groups)

1. The Account Holder must accept the latest **Program License Agreement** at https://developer.apple.com/account. Until then, Xcode's automatic signing can't create or update profiles ("PLA Update available").
2. Build once with automatic signing. Xcode should register `group.<base bundle id>` and add App Groups to both App IDs (`<base>` and `<base>.ShareExtension`).
3. If Xcode still says a profile "doesn't support the group…" App Group, go to developer.apple.com → Certificates, IDs & Profiles:
   - **Identifiers → App Groups → +** and register `group.<base bundle id>`.
   - Then open each of the two App IDs, enable **App Groups**, and select that group.
   - Back in Xcode, Signing & Capabilities → **Try Again**.
