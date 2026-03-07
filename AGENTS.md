# AGENTS.md - Project Context for AI Assistants

## Project Overview

**LRT Next Train** is a comprehensive Hong Kong public transport query Flutter application that provides real-time next train information for the Light Rail (LRT) and Mass Transit Railway (MTR), as well as bus route information for KMB, Citybus (CTB), and New Lantao Bus (NLB).

### Key Features
- **Light Rail (LRT)**: Real-time next train schedules with station selection
- **MTR**: Next train arrival times with line/station selection and intelligent caching
- **Bus Routes**: KMB, CTB, and NLB route queries with ETA information
- **Map Integration**: OpenStreetMap-based stop visualization with location services
- **Multi-language**: Full Traditional Chinese and English support
- **Cross-platform**: Supports Android, iOS, Web, Linux, macOS, and Windows

## Technology Stack

### Core Framework
- **Flutter**: >=3.19.0 (UI framework)
- **Dart**: >=3.3.0 <4.0.0 (programming language)
- **Material Design 3**: Modern UI components and theming

### State Management
- **Provider**: Primary state management solution
- **ChangeNotifier**: Reactive UI updates
- **SharedPreferences**: Local data persistence

### Key Dependencies
```yaml
# Networking
http: ^1.5.0              # HTTP requests for API calls

# UI/Animation
animations: ^2.0.11       # Material motion animations
flutter_animate: ^4.5.2   # Animation utilities
flutter_staggered_animations: ^1.1.1
implicitly_animated_reorderable_list_2: ^0.6.0

# Maps & Location
flutter_map: ^8.2.2       # OpenStreetMap integration
latlong2: ^0.9.1          # Geographic coordinates
flutter_map_location_marker: ^10.2.0
geolocator: ^14.0.2       # GPS location services

# UI Components
liquid_glass_renderer: ^0.2.0-dev.4  # Glass morphism effects
auto_size_text: ^3.0.0    # Auto-scaling text
flutter_svg: ^2.0.10      # SVG icon support
marquee: ^2.3.0           # Scrolling text

# Utilities
shared_preferences: ^2.5.3  # Local storage
path_provider: ^2.0.14      # File system access
permission_handler: ^12.0.1 # Runtime permissions
connectivity_plus: ^7.0.0   # Network state monitoring
intl: ^0.20.2               # Internationalization
package_info_plus: ^9.0.0   # App version info
url_launcher: ^6.1.10       # External links
```

## Project Structure

```
/app
├── lib/                          # Main source code
│   ├── main.dart                 # App entry point, LRT main logic
│   ├── mtr/                      # MTR (subway) module
│   │   ├── mtr_schedule_page.dart   # MTR schedule UI & providers
│   │   ├── MTR.md                   # MTR API documentation
│   │   └── MTR API.md               # API specification
│   ├── kmb/                      # Bus module (KMB/CTB/NLB)
│   │   ├── api/
│   │   │   ├── kmb.dart             # KMB API client
│   │   │   ├── citybus.dart         # CTB API client
│   │   │   └── nlb.dart             # NLB API client
│   │   ├── kmb_dialer.dart          # Route selection dialer
│   │   ├── kmb_nearby_page.dart     # Nearby stops
│   │   ├── kmb_pinned_page.dart     # Pinned routes/stops
│   │   └── company_name.dart        # Company branding
│   ├── widgets/                  # Shared UI components
│   │   └── saved_files_list.dart
│   ├── index.dart                # Library exports (barrel file)
│   ├── ui_constants.dart         # UI constants (sizes, colors)
│   ├── direction_color.dart      # Direction styling utilities
│   ├── optionalMarquee.dart      # Marquee text widget
│   ├── toTitleCase.dart          # String formatting extension
│   ├── settings_page.dart        # App settings
│   └── hkbus_db_provider.dart    # Unified bus database
├── android/                      # Android platform code
├── ios/                          # iOS platform code
├── web/                          # Web-specific files
├── linux/                        # Linux platform code
├── macos/                        # macOS platform code
├── windows/                      # Windows platform code
├── assets/                       # Static assets
│   ├── icon/                     # App icons
│   ├── prebuilt/                 # Pre-built data files
│   └── routes/                   # Route assets
├── tools/                        # Development tools
│   └── prebuild_kmb.dart         # Data pre-building script
├── pubspec.yaml                  # Dependency configuration
├── netlify.toml                  # Netlify deployment config
├── Dockerfile                    # Container build config
└── analysis_options.yaml         # Dart static analysis rules
```

## Building and Running

### Prerequisites
- Flutter SDK >=3.19.0
- Dart SDK >=3.3.0
- Android SDK (for Android builds)
- Xcode (for iOS builds, macOS only)

### Development Commands

```bash
# Get dependencies
flutter pub get

# Run in debug mode
flutter run

# Run on specific device
flutter run -d <device_id>

# Build for production
flutter build apk --release          # Android APK
flutter build appbundle --release    # Android App Bundle
flutter build ios --release          # iOS
flutter build web --release          # Web
flutter build linux --release        # Linux
flutter build macos --release        # macOS
flutter build windows --release      # Windows

# Run tests
flutter test

# Analyze code
flutter analyze

# Format code
flutter format lib/
```

### Web Deployment (Netlify)
The project includes Netlify configuration for automatic Flutter web builds:

```bash
# Local web build
flutter build web --release

# Deploy to Netlify (automated via netlify.toml)
# Build command configured in netlify.toml
```

## Architecture Patterns

### State Management
- **Provider Pattern**: Top-level providers in `main.dart`
- **ChangeNotifier**: Business logic and state in dedicated provider classes
- **Consumer/Selector**: Granular UI updates to minimize rebuilds

### Key Providers
1. **StationProvider**: Manages LRT station data and selection
2. **ScheduleProvider**: Handles LRT schedule fetching and caching
3. **MtrCatalogProvider**: MTR line/station catalog management
4. **MtrScheduleProvider**: MTR schedule fetching with intelligent caching
5. **RoutesCatalogProvider**: Bus route data management
6. **LanguageProvider**: i18n and localization state
7. **ThemeProvider**: Dark/light mode and theming
8. **DeveloperSettingsProvider**: Feature flags and debug settings

### Data Flow
1. **API Layer**: Service classes (`MtrApiService`, `Kmb`, `Citybus`, `Nlb`)
2. **Caching**: Multi-layer caching (memory + SharedPreferences + prebuilt assets)
3. **Providers**: Transform raw data into UI-ready models
4. **UI**: Reactive widgets that rebuild on state changes

### Caching Strategy
- **In-Memory Cache**: 45-second TTL for API responses
- **Persistent Cache**: 30-minute TTL in SharedPreferences
- **Prebuilt Assets**: Bundled JSON files for offline-first experience
- **Stale-While-Revalidate**: Serve cached data while fetching updates

## API Integrations

### MTR Next Train API
- **Endpoint**: `https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php`
- **Features**: Real-time train arrivals, platform numbers, service status
- **Lines**: AEL, TCL, TML, TKL, EAL, SIL, TWL, ISL, KTL, DRL

### KMB API
- **Endpoint**: `https://data.etabus.gov.hk/v1/transport/kmb/`
- **Features**: Routes, stops, ETA information
- **Caching**: 24-hour cache for static data

### CTB (Citybus) API
- **Endpoint**: `https://rt.data.gov.hk/v2/transport/citybus/`
- **Features**: Route queries, stop information, ETAs

### NLB API
- **Endpoint**: `https://rt.data.gov.hk/v2/transport/nlb/`
- **Features**: New Lantao Bus routes and schedules

## Development Conventions

### Code Style
- **Linting**: Uses `flutter_lints` for standard Dart/Flutter linting
- **Formatting**: 2-space indentation (from codebase observation)
- **Naming**: 
  - `camelCase` for variables and functions
  - `PascalCase` for classes
  - `SCREAMING_SNAKE_CASE` for constants
  - Private members prefixed with `_`

### UI Constants
Centralized in `lib/ui_constants.dart`:
```dart
static const double cardRadius = 12.0;
static const double chipRadius = 8.0;
static const double cardPadding = 12.0;
```

### File Organization
- One main class/widget per file
- Related widgets grouped in subdirectories
- Barrel exports via `index.dart` files
- API clients in dedicated `api/` subdirectories

### Documentation
Extensive documentation files in root (all `.md`):
- `MTR_*.md`: MTR implementation details
- `LRT_*.md`: Light Rail implementation details
- `NETWORK_*.md`: Network optimization guides
- `*_QUICK_REF.md`: Quick reference guides

## Key Files Reference

| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry, LRT logic, shared providers |
| `lib/mtr/mtr_schedule_page.dart` | MTR UI (~4300 lines), providers, API service |
| `lib/kmb/kmb_dialer.dart` | Bus route selection interface |
| `lib/kmb/api/kmb.dart` | KMB API client with caching |
| `lib/ui_constants.dart` | Shared UI sizing and styling constants |
| `lib/Route Station.json` | MTR station and line configuration |
| `pubspec.yaml` | Dependencies and app metadata |
| `netlify.toml` | Web deployment configuration |

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Android | ✅ Full | APK and AppBundle builds |
| iOS | ✅ Full | Requires macOS + Xcode |
| Web | ✅ Full | Deployed via Netlify |
| Linux | ✅ Supported | Desktop build |
| macOS | ✅ Supported | Desktop build |
| Windows | ✅ Supported | Desktop build |

## Important Notes for AI Assistants

1. **Provider Pattern**: Always use `context.read<T>()` or `context.watch<T>()` for state access. Update state through provider methods, not directly.

2. **API Caching**: The app has sophisticated caching. When modifying API-related code, ensure cache invalidation logic is preserved.

3. **Localization**: All user-facing strings should support both English and Traditional Chinese. Use `lang.isEnglish` checks.

4. **Platform Differences**: Web has some limitations (no background fetch, different storage). Use `kIsWeb` checks where needed.

5. **State Persistence**: User preferences and selections are persisted. When adding new settings, add corresponding SharedPreferences keys.

6. **File Size**: Some files are very large (`main.dart` ~12K lines, `mtr_schedule_page.dart` ~4K lines). Use search to navigate efficiently.

7. **Material You**: The app uses Material Design 3 with dynamic theming. Respect `colorScheme` for consistent styling.

8. **Testing**: Limited test coverage. When adding features, consider adding widget tests in `test/`.

---

*Last updated: 2026-03-07*
*Project version: 1.4.3+8*
