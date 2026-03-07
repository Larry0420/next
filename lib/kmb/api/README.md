# 香港公共交通 API 文档

本文档描述了用于获取香港各种公共交通服务（巴士、小巴）实时到站信息的 API 客户端实现。

## 目录

- [KMB (九巴)](#kmb-九巴)
- [CTB (城巴/新巴)](#ctb-城巴新巴)
- [NLB (嶼巴)](#nlb-嶼巴)
- [GMB (專線小巴)](#gmb-專線小巴)

---

## KMB (九巴)

**文件**: `kmb.dart`

**API 基础 URL**: `https://data.etabus.gov.hk/v1/transport/kmb`

### 支持的端点

| 端点 | 描述 |
|------|------|
| `GET /route` | 获取所有路线列表 |
| `GET /route-stop/{route}` | 获取路线站点信息 |
| `GET /stop` | 获取所有站点列表 |
| `GET /stop-eta/{stop_id}` | 获取站点的 ETA |
| `GET /eta/{stop_id}/{route}/{service_type}` | 获取特定站点路线的 ETA |
| `GET /route-eta/{route}/{service_type}` | 获取路线的所有 ETA |

### 主要方法

```dart
// 获取路线列表
static Future<List<String>> fetchRoutes()

// 获取路线详情
static Future<Map<String, dynamic>> fetchRouteStatus(String route)

// 获取路线站点
static Future<List<Map<String, dynamic>>> fetchRouteStops(
  String route,
  String direction,  // 'inbound' 或 'outbound'
  String serviceType, // e.g., '1', '2'
)

// 获取站点 ETA
static Future<List<Map<String, dynamic>>> fetchStopEta(String stopId)

// 获取特定路线站点的 ETA
static Future<List<Map<String, dynamic>>> fetchStopRouteEta(
  String stopId,
  String route,
  String serviceType,
)
```

### 缓存策略

- **内存缓存**: 存储最近获取的数据
- **SharedPreferences 缓存**: 持久化存储，24 小时 TTL
- **预构建资源**: `assets/prebuilt/kmb_route_stops.json`, `kmb_stops.json`

---

## CTB (城巴/新巴)

**文件**: `citybus.dart`

**API 基础 URL**: `https://rt.data.gov.hk/v2/transport/citybus`

### 支持的端点

| 端点 | 描述 |
|------|------|
| `GET /route/{company}` | 获取公司路线列表 |
| `GET /stop` | 获取所有站点列表 |
| `GET /route-stop/{company}/{route}/{direction}` | 获取路线站点 |
| `GET /eta/{company}/{stop_id}/{route}` | 获取站点 ETA |

### 主要方法

```dart
// 获取路线列表
static Future<List<Map>> fetchRoutes({String companyId = 'ctb'})

// 获取站点列表
static Future<List<Map>> fetchStopsAll()

// 获取路线站点
static Future<List<Map<dynamic, dynamic>>> fetchRouteStops(
  String route,
  String direction,  // 'inbound' 或 'outbound'
  {String companyId = 'ctb'}
)

// 获取 ETA
static Future<List<Map>> fetchEta(
  String stopId,
  String route, {
  String companyId = 'ctb',
})

// 构建路线索引（用于搜索）
static Future<Map<String, Map<String, dynamic>>> buildRouteIndex()

// 搜索路线
static Future<List<Map<String, dynamic>>> searchRoutes(
  String query, {
  String companyId = 'ctb',
  int? maxResults,
})
```

### 支持的运营商

- `ctb` - 城巴 (Citybus)
- `nwfb` - 新巴 (NWFB)

---

## NLB (嶼巴)

**文件**: `nlb.dart`

**API 基础 URL**: `https://rt.data.gov.hk/v2/transport/nlb`

### 支持的端点

| 端点 | 描述 |
|------|------|
| `GET /route.php?action=list` | 获取所有路线列表 |
| `GET /stop.php?action=list&routeId={routeId}` | 获取路线站点 |
| `GET /stop.php?action=estimatedArrivals&routeId={routeId}&stopId={stopId}` | 获取 ETA |

### 主要方法

```dart
// 获取路线列表
static Future<List<Map<String, dynamic>>> fetchRoutes()

// 构建路线到站点映射
static Future<Map<String, dynamic>> buildRouteToStopsMap()

// 获取 ETA
static Future<List<Map<String, dynamic>>> fetchEstimatedArrivals({
  required String routeId,
  required String stopId,
  String language = 'en',  // 'en', 'zh', 'cn'
})

// 获取路线变体
static Future<List<Map<String, dynamic>>> getVariantsForRoute(String routeNo)
```

### NLB 特点

- NLB 使用 `routeId` 而非 `route` 号码来识别路线变体
- 同一 `routeNo` 可能有多个变体（如不同服务类型）
- 建议依赖预构建数据而非实时 API 获取路线信息

---

## GMB (專線小巴)

**文件**: `gmb.dart`

**API 基础 URL**: `https://data.etagmb.gov.hk`

**API 版本**: 1.1

**官方文档**: https://data.etagmb.gov.hk/static/GMB_ETA_API_Specification.pdf

### 支持的端点

| 端点 | 描述 |
|------|------|
| `GET /route` | 获取所有地区路线列表 |
| `GET /route/{region}` | 获取特定地区路线 |
| `GET /route/{region}/{route_code}` | 获取路线详情 |
| `GET /route/{route_id}` | 通过 ID 获取路线详情 |
| `GET /stop/{stop_id}` | 获取站点信息 |
| `GET /route-stop/{route_id}/{route_seq}` | 获取路线站点列表 |
| `GET /stop-route/{stop_id}` | 获取站点服务的路线 |
| `GET /eta/route-stop/{route_id}/{route_seq}/{stop_seq}` | 获取路线站点 ETA |
| `GET /eta/route-stop/{route_id}/{stop_id}` | 通过 stop_id 获取 ETA |
| `GET /eta/stop/{stop_id}` | 获取站点的所有 ETA |
| `GET /last-update/*` | 获取最后更新时间 |

### 主要方法

```dart
// 获取所有路线（按地区分组）
static Future<Map<String, List<String>>> fetchAllRoutes()
// 返回: { 'HKI': ['1', '10', ...], 'KLN': ['12', ...], 'NT': ['1', '101M', ...] }

// 获取特定地区路线
static Future<List<String>> fetchRoutesByRegion(String region)
// 地区: 'HKI', 'KLN', 'NT'

// 获取路线详情
static Future<List<Map<String, dynamic>>> fetchRouteInfo(
  String region,
  String routeCode,
)

// 通过 ID 获取路线详情
static Future<List<Map<String, dynamic>>> fetchRouteInfoById(int routeId)

// 获取路线站点
static Future<List<Map<String, dynamic>>> fetchRouteStops(
  int routeId,
  int routeSeq,  // 1 或 2
)

// 获取站点 ETA
static Future<List<Map<String, dynamic>>> fetchStopEta(int stopId)

// 获取路线站点 ETA（多种方式）
static Future<Map<String, dynamic>> fetchRouteStopEta(
  int routeId,
  int routeSeq,
  int stopSeq,
)

static Future<List<Map<String, dynamic>>> fetchRouteStopEtaByStopId(
  int routeId,
  int stopId,
)

// 便利方法：获取路线的 ETA
static Future<List<Map<String, dynamic>>> fetchEtaForRouteStop(
  int routeId,
  int stopId, {
  int? routeSeq,
  int? stopSeq,
})
```

### GMB API 数据结构

#### 路线信息 (Route)

```json
{
  "region": "HKI",
  "route_code": "69",
  "route_id": 2000410,
  "description_tc": "正常班次",
  "description_en": "Normal Schedule",
  "directions": [
    {
      "route_seq": 1,
      "orig_tc": "數碼港",
      "orig_en": "Cyberport",
      "dest_tc": "鰂魚涌 (船塢里)(循環線)",
      "dest_en": "Quarry Bay (Shipyard Lane) (Circular)",
      "headways": [...]
    }
  ]
}
```

#### ETA 响应 (ETA-Route-Stop)

```json
{
  "enabled": true,
  "stop_id": 20003337,
  "eta": [
    {
      "eta_seq": 1,
      "diff": 6,                    // 相对分钟数
      "timestamp": "2020-12-28T15:20:00.000+08:00",
      "remarks_tc": null,
      "remarks_en": null
    }
  ]
}
```

### GMB 特点

1. **整数 ID**: GMB 使用整数 `route_id` 和 `stop_id`（非字符串）
2. **地区分组**: 路线按地区分组（HKI, KLN, NT）
3. **多方向**: 一条路线可能有多个 `directions`（不同服务类型）
4. **diff 字段**: ETA 直接提供相对分钟数（`diff`），无需计算
5. **班次信息**: 路线详情包含 `headways`（班次频率）

### 缓存策略

- **内存缓存**: 路线列表、站点信息、路线站点
- **SharedPreferences**: 24 小时 TTL
- **预构建资源**: `assets/prebuilt/gmb_route_stops.json`, `gmb_stops.json`

---

## 统一数据映射

在使用 `hkbus_db_provider.dart` 时，所有 API 数据会被映射为统一格式：

### UnifiedBusRoute

```dart
class UnifiedBusRoute {
  final String routeId;           // JSON 中的 Key
  final String routeNumber;       // "101"
  final List<String> companies;   // ["kmb", "ctb"]
  final String origTc;
  final String origEn;
  final String destTc;
  final String destEn;
  final String? serviceType;
  final Map<String, dynamic> stopsByCompany;
  final Map<String, dynamic> boundsByCompany;
}
```

### ETA 统一格式

```dart
{
  'eta': '2024-01-01T12:00:00.000+08:00',  // 绝对时间
  'diff': 5,                                  // 相对分钟数（可选）
  'eta_seq': 1,
  'remarks_en': 'Scheduled',
  'remarks_tc': '未開出',
}
```

---

## 使用示例

### 在 UnifiedRouteStatusPage 中使用

```dart
// 页面自动处理所有 API
UnifiedRouteStatusPage(
  route: '101',
  companies: ['kmb', 'ctb'],
  useUnifiedDb: true,  // 使用 hkbus_db_provider
)

// 页面会根据选定的公司自动调用相应的 API：
// - KMB -> Kmb.fetchStopRouteEta()
// - CTB -> Citybus.fetchEta()
// - NLB -> Nlb.fetchEstimatedArrivals()
// - GMB -> GMB.fetchRouteStopEta()
```

### 直接使用 API

```dart
// KMB ETA
final etas = await Kmb.fetchStopRouteEta('AA100', '101', '1');

// CTB ETA
final etas = await Citybus.fetchEta('1234', '969');

// NLB ETA
final etas = await Nlb.fetchEstimatedArrivals(
  routeId: '1',
  stopId: '100',
);

// GMB ETA
final etas = await GMB.fetchRouteStopEta(2000410, 1, 1);
```

---

## 缓存和离线支持

所有 API 客户端支持以下缓存层级：

1. **内存缓存**: 快速访问最近数据
2. **SharedPreferences**: 持久化缓存（默认 24 小时 TTL）
3. **预构建资源**: `assets/prebuilt/*.json`
4. **应用文档**: 可更新的预构建数据

缓存优先级：
```
内存缓存 > SharedPreferences > 应用文档 > 打包资源 > API
```

---

## 错误处理

所有 API 方法会抛出以下异常：

- `Exception('HTTP {code}: ...')` - HTTP 错误
- `Exception('Invalid response: ...')` - 响应格式错误
- `Exception('Failed to fetch ...')` - 网络或解析错误

建议使用 try-catch 处理：

```dart
try {
  final etas = await Kmb.fetchStopRouteEta(stopId, route, serviceType);
} catch (e) {
  // 处理错误，回退到缓存或显示错误信息
}
```
