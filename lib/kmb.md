<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# again but API spec. previous is dictionary for the API spec.

Below is a concise Markdown API specification for KMB Real‑time Arrival (ETA) covering endpoints, parameters, responses, and operational notes, formatted for direct reading without tables.[^1]

### Base URL

All endpoints share the base URL: https://data.etabus.gov.hk/ with case‑sensitive paths and parameters.[^1]

Details:
Raw Data (Every 5 am):

API Base URL
https://data.etabus.gov.hk/ 

Route List API /v1/transport/kmb/route/
Route API /v1/transport/kmb/route/{route}/{direction}/{service_type}

Stop List API /v1/transport/kmb/stop 

Stop API      /v1/transport/kmb/stop/{stop_id}

Route-stop List API   /v1/transport/kmb/route-stop 

Route-Stop API   /v1/transport/kmb/route-stop/{route}/{direction}/{service_type}




### Update cadence

Static datasets for routes, stops, and route‑stops update daily at 05:00 local time and should be cached accordingly.[^1]

### Common response schema

Responses include type, version, generated_timestamp, and data, with generated_timestamp indicating when the payload was prepared before any caching layer.[^1]
On errors, the API returns a JSON body with code and message alongside the HTTP status code.[^1]

### HTTP status codes

Successful requests return 200, validation issues return 422 with a descriptive message, and unexpected failures return 500.[^1]

### Route List API

Description returns all KMB routes including directions and service types for origin and destination pairs.[^1]
Request method is GET at /v1/transport/kmb/route/ without parameters.[^1]
Response data is an array of objects with fields including co, route, bound, service_type, orig_en, orig_tc, orig_sc, dest_en, dest_tc, dest_sc, and data_timestamp.[^1]

### Route API

Description returns a specific route’s metadata given route number, direction, and service type.[^1]
Request method is GET at /v1/transport/kmb/route/{route}/{direction}/{service_type} with path parameters.[^1]
Parameters include route as case‑sensitive route number, direction as outbound or inbound, and service_type as the numeric service type.[^1]
Response data is an object mirroring the route list item, including co, route, bound, service_type, origin names, destination names, and data_timestamp.[^1]

### Stop List API

Description returns all bus stops with multilingual names and WGS84 coordinates.[^1]
Request method is GET at /v1/transport/kmb/stop without parameters.[^1]
Response data is an array of stop objects including stop, name_tc, name_en, name_sc, lat, long, and data_timestamp.[^1]

### Stop API

Description returns metadata for a specific stop ID.[^1]
Request method is GET at /v1/transport/kmb/stop/{stop_id} with stop_id as a 16‑character ID.[^1]
Response data is a stop object with multilingual names, coordinates, and data_timestamp.[^1]

### Route‑Stop List API

Description returns stop sequences for all routes and directions.[^1]
Request method is GET at /v1/transport/kmb/route-stop without parameters.[^1]
Response data is an array including co, route, bound, service_type, seq, stop, and data_timestamp for each stop in order.[^1]

### Route‑Stop API

Description returns the ordered stops for a specific route direction and service type.[^1]
Request method is GET at /v1/transport/kmb/route-stop/{route}/{direction}/{service_type} with path parameters.[^1]
Parameters include route as case‑sensitive route number, direction as inbound (towards origin) or outbound (towards destination), and service_type numeric.[^1]
Response data is an array of stop sequence objects with co, route, bound, service_type, seq, stop, and data_timestamp.[^1]

### ETA API

Description returns up to three upcoming ETAs for a specific route and service type at a given stop, noting that ETAs may also appear under other service types of the same route at that shared stop.[^1]
Request method is GET at /v1/transport/kmb/eta/{stop_id}/{route}/{service_type} with path parameters.[^1]
Parameters include stop_id as a 16‑character stop identifier, route as case‑sensitive route number, and service_type numeric.[^1]
Response data is an array where each ETA entry includes co, route, dir, service_type, seq, stop, dest_tc, dest_sc, dest_en, eta_seq, eta, rmk_tc, rmk_sc, rmk_en, and data_timestamp.[^1]

### Stop ETA API

Description returns ETAs for all serving routes at a given stop, with up to three upcoming times per route and direction.[^1]
Request method is GET at /v1/transport/kmb/stop-eta/{stop_id} with stop_id as a 16‑character ID.[^1]
Response data is an array of ETA entries with the same fields used in ETA API, across all matching routes and service types serving that stop.[^1]

### Route ETA API

Description returns ETAs for all stops along a specified route and service type, using the same entry structure as the ETA API.[^1]
Request method is GET at /v1/transport/kmb/route-eta/{route}/{service_type} with route and service_type as path parameters.[^1]
Response data is an array of ETA entries covering each stop sequence for the route and direction combinations.[^1]

### Field semantics

co is the bus operator code, KMB, consistent across endpoints in this specification.[^1]
route is the route number string and is case sensitive in all path usages.[^1]
bound and dir use I for inbound and O for outbound within data payloads, while direction parameter uses textual inbound or outbound.[^1]
service_type is a numeric selector for route variants and is required when specified in the endpoint; ETAs may duplicate across service types at shared stops.[^1]
eta_seq enumerates the order of upcoming arrivals, typically 1 to 3 where available.[^1]

### Timestamps

generated_timestamp is the server’s generation time for the response envelope and may reflect caching; consumers must not infer vehicle position freshness solely from this field.[^1]
data_timestamp is the last known update time for the underlying record or ETA calculation and should be used for recency checks.[^1]

### Remarks and nullability

rmk_en, rmk_tc, and rmk_sc may contain operational notes such as Scheduled Bus or service restrictions, and fields can be empty strings.[^1]
eta can be null for routes not currently operating or outside service hours, and clients should handle null gracefully.[^1]

### Input validation

All path elements are case sensitive, and invalid or missing parameters result in HTTP 422 with a JSON message indicating Invalid/Missing parameter(s).[^1]
Numeric fields may appear as numbers or strings in samples; clients should accept both and avoid strict type assumptions when parsing.[^1]

### Usage guidance

Cache static lists (route, stop, route‑stop) after the 05:00 daily refresh to reduce load and improve latency, while querying ETAs on demand.[^1]
Order stop lists by seq for presentation and use eta_seq to sort multiple arrivals for a given stop and route direction.[^1]

### Error response format

On error, the JSON body includes code and message, for example code 422 and message Invalid/Missing parameter(s), with the HTTP status reflecting the same code class.[^1]

### Route Data Fetching for KMB Dialer

**Purpose**: Fetch all available KMB routes for display in the route selection dialer (kmb_dialer.dart).

**Endpoint**: `GET https://data.etabus.gov.hk/v1/transport/kmb/route/`

**Request Details**:
- Method: GET
- Parameters: None
- Headers: None required

**Response Structure**:
```json
{
  "type": "RouteList",
  "version": "1.0",
  "generated_timestamp": "2025-10-31T12:00:00+08:00",
  "data": [
    {
      "co": "KMB",
      "route": "1",
      "bound": "O",
      "service_type": "1",
      "orig_en": "Chuk Yuen Estate",
      "orig_tc": "竹園邨",
      "orig_sc": "竹园邨",
      "dest_en": "Star Ferry",
      "dest_tc": "尖沙咀碼頭",
      "dest_sc": "尖沙咀码头",
      "data_timestamp": "2025-10-31T05:00:00+08:00"
    }
  ]
}
```

**Implementation in kmb_dialer.dart**:
- Call `Kmb.fetchRoutes()` which extracts route numbers from the data array
- Routes are displayed as selectable options in the dialer interface
- Background loading of route-to-stops mapping for direction metadata

**Error Handling**:
- Network failures: Display error message and retry option
- Invalid response: Throw exception with descriptive message
- Empty data: Handle gracefully (no routes available)

**Caching Strategy**:
- No client-side caching (routes fetched on demand)
- Server-side caching: Data updates daily at 05:00 local time
- Consider implementing local cache for offline route selection

### Stop Data Fetching for Location-Based Features

**Purpose**: Fetch all KMB bus stops for location-based appearance and mapping functionality.

**Endpoint**: `GET https://data.etabus.gov.hk/v1/transport/kmb/stop`

**Request Details**:
- Method: GET
- Parameters: None
- Headers: None required

**Response Structure**:
```json
{
  "type": "StopList",
  "version": "1.0",
  "generated_timestamp": "2025-10-31T12:00:00+08:00",
  "data": [
    {
      "stop": "7B9F2F1B4A2E6D8C",
      "name_en": "Tsim Sha Tsui Star Ferry",
      "name_tc": "尖沙咀碼頭",
      "name_sc": "尖沙咀码头",
      "lat": "22.2935",
      "long": "114.1681",
      "data_timestamp": "2025-10-31T05:00:00+08:00"
    }
  ]
}
```

**Individual Stop Details Mapping**:
- Use the "stop" field (16-character ID) to fetch detailed stop information
- Endpoint: `GET https://data.etabus.gov.hk/v1/transport/kmb/stop/{stop_id}`
- Returns single stop object with same structure as above

**Implementation for Location-Based Appearance**:
- Call `Kmb.fetchStopsAll()` to get complete stop list
- Build stop ID to stop info mapping using `Kmb.buildStopMap()`
- Use coordinates (lat/long) for location-based filtering and display
- Multilingual names (en/tc/sc) for localized user interface

**Error Handling**:
- Network failures: Fallback to cached data if available
- Invalid response format: Log error and use cached data
- Missing coordinates: Skip stops without valid lat/long values

**Caching Strategy**:
- In-memory cache with 24-hour TTL
- Persistent storage using SharedPreferences
- Prebuilt asset files for faster initial load
- Force refresh capability for updated stop data

**Usage Guidance**:
- Cache stop data locally to reduce API calls and improve performance
- Use stop coordinates for proximity calculations and map display
- Handle multilingual stop names based on user locale preferences
- Validate stop IDs before making individual stop detail requests

### Route Details API for Route Verification

**Purpose**: Fetch detailed metadata for a specific KMB route, direction, and service type to verify route validity and display route information.

**Endpoint**: `GET https://data.etabus.gov.hk/v1/transport/kmb/route/{route}/{direction}/{service_type}`

**Request Details**:
- Method: GET
- Path Parameters:
  - `route`: Case-sensitive route number (e.g., "276B") - obtained from Route List API
  - `direction`: Direction of travel ("outbound" or "inbound")
  - `service_type`: Numeric service type identifier ("1", "2", "3", etc.) - obtained from Route List API
- Headers: None required

**Example URLs**:
- `https://data.etabus.gov.hk/v1/transport/kmb/route/276B/outbound/1`
- `https://data.etabus.gov.hk/v1/transport/kmb/route/1/inbound/2`

**Response Structure**:
```json
{
  "type": "Route",
  "version": "1.0",
  "generated_timestamp": "2025-11-01T12:00:00+08:00",
  "data": {
    "co": "KMB",
    "route": "276B",
    "bound": "O",
    "service_type": "1",
    "orig_en": "Hung Hom Station",
    "orig_tc": "紅磡站",
    "orig_sc": "红磡站",
    "dest_en": "Chuk Yuen Estate",
    "dest_tc": "竹園邨",
    "dest_sc": "竹园邨",
    "data_timestamp": "2025-11-01T05:00:00+08:00"
  }
}
```

**Implementation in Route Verification**:
- Call `Kmb.fetchRouteWithParams(route, direction, serviceType)` to get route metadata
- Validate route exists and is active by checking response data
- Display route origin/destination information in route details page
- Use for route confirmation before displaying stop sequences or ETA data

**Implementation in Independent Stop Page**:
- Use route details to show which routes serve a particular stop
- Display route direction and service type information
- Enable navigation to full route view from stop details

**Error Handling**:
- Invalid route/direction/service_type: HTTP 422 with validation error message
- Route not found: HTTP 422 or empty response
- Network failures: Fallback to cached route list data
- Invalid response format: Log error and show generic route unavailable message

**Caching Strategy**:
- No client-side caching (route details fetched on-demand)
- Server-side caching: Data updates daily at 05:00 local time
- Consider caching frequently accessed route details locally

**Usage Guidance**:
- Always validate route parameters before making API calls
- Use route details to enhance user interface with origin/destination information
- Combine with Route-Stop API to show complete route information
- Handle both "outbound" and "inbound" directions appropriately
- Service types may vary by route - validate against Route List API data

<div align="center">⁂</div>

[^1]: kmb_eta_api_specification.pdf

