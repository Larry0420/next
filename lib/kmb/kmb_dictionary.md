<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# draft a spec for kmb_eta_data_dictionary in .md, any strings for reading, no any table

Below is a clean Markdown specification for the KMB ETA Data Dictionary, structured for direct reading and implementation, without tables.[^1][^2]

### Document info

This specification describes a RESTful JSON API providing static route/stop data and real-time estimated arrival times for KMB and LWB services.[^2][^1]
Current version of the data dictionary is 1.02 dated 10 May 2021, with revisions on 8 Mar 2021 and 11 Mar 2021.[^1][^2]

### Common response envelope

All endpoints return a top-level object containing fields: type, version, generatedtimestamp, and data.[^2][^1]
Timestamps use ISO 8601 with timezone offset, and generatedtimestamp reflects the pre-cache generation time.[^1][^2]

### Notes and conventions

Empty data objects denote “not available” or “not found,” and list endpoints return an array in data.[^2][^1]
Text fields are available in English, Traditional Chinese, and Simplified Chinese with suffixes en, tc, and sc respectively.[^1][^2]

### Route list

type indicates Route or RouteList, version is the JSON major.minor string, and generatedtimestamp is ISO 8601.[^2][^1]
data objects include co, route, bound, servicetype, origen, origtc, origsc, desten, desttc, destsc, and datatimestamp.[^1][^2]

### Route fields

co is always KMB and includes both KMB and LWB route services, and route is the route number string.[^2][^1]
bound is I for inbound or O for outbound, and servicetype is a string representing the service type of the route.[^1][^2]
origen, origtc, origsc give origin names by language, and desten, desttc, destsc provide destination names by language.[^2][^1]
datatimestamp is when the payload was prepared at source, in ISO 8601 with timezone.[^1][^2]

### Stop list

type indicates Stop or StopList and version is the JSON version string, with generatedtimestamp as ISO 8601.[^2][^1]
data contains stop, nametc, nameen, namesc, lat, long, and datatimestamp, with arrays for list responses.[^1][^2]

### Stop fields

stop is the bus stop ID, and nametc, nameen, namesc are stop names in Traditional Chinese, English, and Simplified Chinese.[^2][^1]
lat and long are WGS84 decimal degrees as strings, and datatimestamp reflects source preparation time.[^1][^2]

### Route-stop list

type indicates RouteStop or RouteStopList, version identifies the JSON version, and generatedtimestamp is ISO 8601.[^2][^1]
data contains co, route, bound, servicetype, seq, stop, and datatimestamp, returned as an array for list endpoints.[^1][^2]

### Route-stop fields

co is KMB, route is the route number string, and bound is I or O for direction.[^2][^1]
servicetype is a string, seq is a numeric stop sequence within the route, and stop is the stop ID string.[^1][^2]
datatimestamp is the ISO 8601 source preparation timestamp with timezone.[^2][^1]

### ETA responses

type is ETA, StopETA, or RouteETA, version is the JSON version, and generatedtimestamp captures pre-cache time.[^1][^2]
data includes co, route, dir, servicetype, seq, stop, desttc, destsc, desten, etaseq, eta, rmktc, rmksc, rmken, and datatimestamp.[^2][^1]

### ETA fields

co is KMB and route is the route number string tied to the requested company in the ETA call.[^1][^2]
dir is I or O indicating inbound or outbound, and servicetype is a string representing service type.[^2][^1]
seq is the numeric stop sequence number, and stop is the stop ID where ETA is requested.[^1][^2]
desten, desttc, destsc are destination names in English, Traditional Chinese, and Simplified Chinese respectively.[^2][^1]
etaseq is the ETA sequence number for multiple upcoming buses, and eta is the ISO 8601 timestamp for the arrival.[^1][^2]
rmken, rmktc, rmksc are free-text remarks per language, and datatimestamp is the source preparation time in ISO 8601.[^2][^1]

### Example values

Example route entries show route 74B outbound service type 1 with origin and destination names and ISO timestamps.[^1][^2]
Example stop entries include a stop ID like A3ADFCDF8487ADB9 with English name SAU MAU PING CENTRAL and WGS84 coordinates.[^2][^1]
Example ETA entries show STAR FERRY as destination with etaseq 1 and eta like 2022-11-29T15:48:00+0800 plus language-specific remarks.[^1][^2]

### Error and empties

Empty data objects indicate no available data for the query, and consumers should guard against empty arrays or objects.[^2][^1]
Cache behavior is implied by generatedtimestamp, and clients should not assume real-time regeneration for every request.[^1][^2]

### Implementation guidance

Always parse timestamps with timezone offsets, and treat numeric-like fields that are strings as per schema to avoid type coercion issues.[^2][^1]
When building lists, respect sequence numbers for ordering of stops and multiple ETAs, and present multilingual names per user locale.[^1][^2]

<div align="center">⁂</div>

[^1]: kmb_eta_data_dictionary.pdf

[^2]: kmb_eta_data_dictionary.pdf

