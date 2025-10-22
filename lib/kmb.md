<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# again but API spec. previous is dictionary for the API spec.

Below is a concise Markdown API specification for KMB Real‑time Arrival (ETA) covering endpoints, parameters, responses, and operational notes, formatted for direct reading without tables.[^1]

### Base URL

All endpoints share the base URL: https://data.etabus.gov.hk/ with case‑sensitive paths and parameters.[^1]

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

<div align="center">⁂</div>

[^1]: kmb_eta_api_specification.pdf

