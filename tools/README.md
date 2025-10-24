Prebuild scripts

This folder contains helper scripts to prebuild KMB data assets used at runtime.

Run to fetch data and write to `assets/prebuilt`:

```bash
# from repository root
dart run tools/prebuild_kmb.dart
```

The script writes:
- `assets/prebuilt/kmb_route_stops.json` — route -> list of route-stop entries
- `assets/prebuilt/kmb_stops.json` — stopId -> stop metadata

Include the `assets/prebuilt` directory in your app's assets when deploying.
