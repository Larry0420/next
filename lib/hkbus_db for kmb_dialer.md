<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# for a set for complete info (the route with the service type with companyId, and dest), the structure is like as follows, propose your best approcah for various purposes (), e.g. search, indexing, prasing/mapping, fetching, for various helper/classes/methods, etc. say dialer to search, status_page for route-stops list, pinning, history:

"276B+1+SHEUNG SHUI (CHOI YUEN)+TIN FU": {"bound": {"kmb": "I"}, "co": ["kmb"], "dest": {"en": "TIN FU", "zh": "\u5929\u5bcc"}, "fares": ["10.5", "10.5", "10.5", "10.5", "10.5", "5.1", "5.1", "5.1", "5.1", "5.1", "5.1", "5.1", "5.1"], "faresHoliday": null, "freq": {"287": {"0610": ["0635", "1500"], "0635": ["0655", "1200"], "0655": ["0725", "900"], "0725": ["0905", "1200"], "0905": ["0935", "900"], "0935": ["1715", "1200"], "1715": ["1830", "900"], "1830": ["2450", "1200"]}, "288": {"0610": ["0625", "900"], "0625": ["1245", "1200"], "1245": ["1845", "900"], "1845": ["2105", "1200"], "2105": ["2150", "900"], "2150": ["2450", "1200"]}, "448": {"0610": ["1210", "1200"], "1210": ["1810", "900"], "1810": ["2450", "1200"]}}, "gtfsId": "1139", "jt": "46", "nlbId": null, "orig": {"en": "SHEUNG SHUI (CHOI YUEN)", "zh": "\u4e0a\u6c34(\u5f69\u5712)"}, "route": "276B", "seq": 14, "serviceType": "1", "stops": {"kmb": ["26A1D2969A15C3AF", "4E655B25ABAE103A", "AD4E0E8DC8ACEFB6", "DF8F6AA868615D47", "FFFB0F940CA7BEA7", "1D202282C0A82F12", "D813C93D9AD1C45B", "7BB395B6FE66E102", "6D4E7B9D5F9584E7", "47AB1894215AECEE", "42AEF6365E78DA56", "8753A8442C2FFF53", "8D56DB404D264D5A", "430C6E88A93B42DE"]}},

你呢個 JSON 其實已經係一個「*完整 route 變體*」record：唯一 key = `routeId = route+serviceType+orig+dest`，value 入面再有 `companyId(s)、bound、stops、fares、freq...`，好適合做核心 domain model。基於你現有 `UnifiedBusRoute` / Dialer / RouteStatusPage 結構，我會建議圍繞「*一個 route 變體 = 一條 normalized record*」去拆幾層：資料層（DB）、domain 層（Route / Stop / Variant）、功能層（search、status、pinning/history）。

***

## 建議核心 Domain 結構

用你現有 `UnifiedBusRoute` 做 base，稍微補幾個 field，把上面 JSON 嵌入：[^1]

```dart
class UnifiedBusRoute {
  final String routeId;         // "276B+1+SHEUNG SHUI (CHOI YUEN)+TIN FU"
  final String routeNumber;     // "276B"
  final String serviceType;     // "1"
  final List<String> companies; // ["kmb"]
  final Map<String, String> boundsByCompany; // { "kmb": "I" }

  final String origTc;
  final String origEn;
  final String destTc;
  final String destEn;

  final Map<String, List<String>> stopsByCompany; // { "kmb": [stopIds...] }
  final Map<String, dynamic>? fares;              // 或直接保留原 array
  final Map<String, dynamic>? freq;               // 保留原 JSON 結構
  final String? gtfsId;
  final String? nlbId;
  final String? journeyTime; // jt

  // helper:
  String get primaryCompany => companies.isNotEmpty ? companies.first : 'kmb';
  bool get isJointOperation => companies.length > 1;

  // 可加一個 computed:
  String get displayKey => '$routeNumber ($serviceType) $origEn → $destEn';
}
```

Provider 端（`HkbusDbProvider`）就負責：[^1]

- 把 JSON routeEntry → `UnifiedBusRoute`（normalize stops/bound 型別、確保 `serviceType` 一致）。
- 提供按 **routeId** / **routeNumber+bound+svcType** / **模糊關鍵字** 查詢。

***

## 各用途的「最佳 entry / 索引」建議

### 1. Dialer 搜尋（route list / keyword search）

需求：

- 根據 route number、起點/終點中英、公司，快速 filter / ranking。
- 由 dialer 點擊一條 item 時，要有足夠 info 去導航到 status page（即 routeId、companyId、bound、serviceType）。

建議：

1. 在 Provider 內保留一個「*扁平化 dialer view*」緩存：[^1]
```dart
class HkbusDbProvider extends ChangeNotifier {
  late final List<Map<String, dynamic>> _dialerRoutes;

  void _buildDialerRoutes() {
    final all = getAllRoutes(); // List<UnifiedBusRoute>
    _dialerRoutes = all.map(convertToDialerFormat).toList();
  }

  List<Map<String, dynamic>> getAllRoutesForDialer() => _dialerRoutes;
}
```

2. `convertToDialerFormat`（你已經有），只要確保包含以下欄位：[^1]
```dart
Map<String, dynamic> convertToDialerFormat(UnifiedBusRoute route) {
  final bound = route.boundsByCompany.isNotEmpty
      ? route.boundsByCompany.values.first?.toString() ?? 'O'
      : 'O';

  final searchText = [
    route.routeNumber,
    route.origEn,
    route.origTc,
    route.destEn,
    route.destTc,
    ...route.companies,
  ].where((s) => s.isNotEmpty).join(' ').toLowerCase();

  return {
    'route': route.routeNumber,
    'companyid': route.primaryCompany,
    'companies': route.companies,
    'companyname': route.getDisplayCompany(false),
    'orig_en': route.origEn,
    'orig_tc': route.origTc,
    'dest_en': route.destEn,
    'dest_tc': route.destTc,
    'bound': bound,
    'direction': bound == 'I' ? 'inbound' : 'outbound',
    'service_type': route.serviceType,
    'isJointOperation': route.isJointOperation,
    'routeId': route.routeId, // 🔑 之後直接帶去 status page
    'search_text': searchText,
  };
}
```

3. 搜尋：用一個 scoring 函數處理 route number + origin/dest（你已經實作），Dialer 只對 `_dialerRoutes` 做 filtering / sort，完全唔碰原始 JSON。[^1]

Dialer → 點擊 item → 導航到 `UnifiedRouteStatusPage(route: routeNumber, companies: companies, initialRouteId: routeId, initialCompany: companyid, bound: bound, serviceType: service_type)`。[^2]

***

### 2. Route Status Page（站序 + ETA + map）

需求：

- 單一公司 / 聯營，都用 unified DB route 做 primary source。
- GMB / NLB 例外邏輯可保留，但盡量經 `stopsByCompany` / `buildStopGroupsForRoute`。

建議 entry：

- **primary key**：`routeId`（最精準）或 `routeNumber+bound+serviceType`。[^2][^1]
- Provider 提供：

```dart
UnifiedBusRoute? getRouteById(String routeId);
UnifiedBusRoute? getRouteByNumber(
  String routeNumber, {
  String? direction,
  String? serviceType,
});
List<Map<String, dynamic>> buildStopGroupsForRoute(String routeId);
Map<String, double>? getStopCoordinates(String stopId);
String getStopName(String stopId, {bool isEnglish = false});
```

Page 內流程：[^2][^1]

1. `initialRouteId` 有值 → `getRouteById()`。
2. 否則 `getRouteByNumber(route, direction: bound, serviceType: serviceType)`。
3. 有 route →
    - 聯營：`buildStopGroupsForRoute(route.routeId)` → group → 轉成 UI stops。
    - 非聯營或 stopGroups 空：直接用 `route.stopsByCompany[_selectedCompany]` + `_normalizeStops()` 補 name/coords。

呢一層完全只食 `UnifiedBusRoute` / helper，而唔直接觸碰 JSON raw。[^2][^1]

***

### 3. Pinning / History（收藏 / 最近使用）

需求：

- 能夠唯一識別到「某一個具體變體」（276B、走向、serviceType、公司/聯營、orig/dest）。
- UI 上要容易展示。
- 對應 Dialer / Status page 時，不會因為改 serviceType / 新 bound 而錯配。

建議 pinned key = `routeId` + optional 「preferred company」：

```dart
class PinnedRoute {
  final String routeId;          // "276B+1+SHEUNG SHUI (CHOI YUEN)+TIN FU"
  final String? preferredCompany; // null = primaryCompany

  // cached display fields (for faster list build,可由 UnifiedBusRoute 生成):
  final String routeNumber;
  final String origEn;
  final String destEn;
  final String companyLabel;
  final String bound;       // "I" / "O"
  final String serviceType; // "1"

  Map<String, dynamic> toJson() => {...};
}
```

History 同樣：[^1]

- key 用 `routeId`（optionally 加公司）。
- 當打開 history / pin item → 先用 `getRouteById(routeId)` 取最新 info，如果 route 已刪/改再 fallback 至 cache。

***

### 4. Indexing / Parsing（初始化 DB）

DB provider 初始化時一次完成所有解析，之後所有 UI/功能只用 Domain API：[^1]

1. 讀 JSON → `_routeList`（原始 map）。
2. `getAllRoutes()`：
    - 遍歷 `_routeList`：routeId + routeData → `UnifiedBusRoute`。
    - parse routeId：`[routeNumber, serviceType, origEn, destEn]`。
    - normalize：`stopsByCompany` 與 `boundsByCompany`（你而家準備加嘅 `_normalizeStopsMap` / `_normalizeBoundsMap`）。
3. cache：
    - `List<UnifiedBusRoute> _allRoutes`。
    - `List<Map<String, dynamic>> _dialerRoutes`。
    - 如有需要，建立 map index：`Map<String, UnifiedBusRoute> _routeById`。

之後：

```dart
UnifiedBusRoute? getRouteById(String id) => _routeById[id];

List<UnifiedBusRoute> searchRoutes(String keyword); // for backend search
List<Map<String, dynamic>> searchRoutesForDialer(String keyword); // for UI
```


***

### 5. ETA / RouteIdResolver / UnifiedEtaService

你已經有 `RouteContext` / `ResolvedRouteIds` / `UnifiedEtaService.fetchEta()`：[^2]

- `RouteContext` 入面可以直接掛：`routeNumber、bound、serviceType、nlbRouteId、gmbRouteId...`。
- resolver 用 `UnifiedBusRoute.routeId` + `companies` 去計算 API-specific id。

建議：

- RouteStatusPage 在 `_initializeRouteContext()` 時，只依賴 `UnifiedBusRoute` 以及 `RouteIdResolver`：[^2]

```dart
final routeData = hkbusDb.getRouteById(widget.initialRouteId!) ?? ...;

_routeContext = RouteContext(
  routeNumber: routeData.routeNumber,
  bound: _getBoundFromRouteData(routeData),
  serviceType: routeData.serviceType ?? '1',
  // 其它 API-specific id 由 resolver 提供
);
```

`UnifiedEtaService.fetchEta()` 只食 `company, routeNumber, stopId, routeContext`，無需理原始 JSON。[^2]

***

### 對應你 JSON 例子（276B）

以 `"276B+1+SHEUNG SHUI (CHOI YUEN)+TIN FU"` 呢條 record，整個 flow 會係：

1. DB load 時建一個 `UnifiedBusRoute`：[^1]

- routeId = key。
- routeNumber = "276B"。
- serviceType = "1"。
- companies = ["kmb"]。
- boundsByCompany = {"kmb":"I"}。
- stopsByCompany = {"kmb":[stopIds...] }。
- freq、fares 等照 JSON 存。

2. Dialer：`convertToDialerFormat(route)` → 拿到一條 dialer row，帶 `routeId` 去 status page。[^2][^1]
3. Status page：`getRouteById(routeId)` → 由 `stopsByCompany['kmb']` + `_normalizeStops` 砌出 UI stops，ETA 由 `UnifiedEtaService` 按 `RouteContext` 拉。[^2][^1]
4. Pin / history：儲存 `routeId` + optional preferredCompany；打開時一樣走 `getRouteById()` → `UnifiedRouteStatusPage(initialRouteId: routeId, ...)`。[^1][^2]

***

你會傾向 **所有 UI 都只透過 `UnifiedBusRoute` + helper API**，完全不直接 touching 原始 JSON map？如果係，我可以幫你再拉一個小層 `RouteRepository` 把 provider 封一層，方便之後 unit test / mock。

<div align="center">⁂</div>

[^1]: hkbus_db_provider.dart

[^2]: route_status_page-2.dart

