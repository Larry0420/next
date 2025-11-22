<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# create comprehensive specs for agent read it for efficient plan and operations with the [https://opendata.mtr.com.hk/doc/Next_Train_DataDictionary_v1.7.pdf](https://opendata.mtr.com.hk/doc/Next_Train_DataDictionary_v1.7.pdf)

[https://opendata.mtr.com.hk/doc/Next_Train_API_Spec_v1.7.pdf](https://opendata.mtr.com.hk/doc/Next_Train_API_Spec_v1.7.pdf)
in .md with tag correctly to using API with its JSON Format

Here is a comprehensive Markdown specification for the agent to plan and operate efficiently with the Next Train API v1.7, referencing both the official data dictionary and specification. This document is tagged for direct implementation and operational efficiency, with all variables and response formats precisely documented for correct API usage.[^1][^2]

***

# Next Train API v1.7 Agent Specification

## API Overview

The Next Train API provides real-time schedules for upcoming trains on all major MTR lines. It uses REST over HTTP GET and returns JSON data detailing arrival/departure times, platform numbers, and service alerts for requested stations.[^2][^1]

## Endpoint

```
GET https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php
```


### Required Query Parameters

- `line` (String): Line code (see table below)
- `sta` (String): 3-letter station code valid for the chosen line


### Optional Query Parameter

- `lang` (String): Language for response; values:
    - `EN`: English (default)
    - `TC`: Traditional Chinese[^1]


## Supported Lines and Station Codes

| Line | Description | Valid Station Codes (sta) |
| :-- | :-- | :-- |
| AEL | Airport Express | HOK, KOW, TSY, AIR, AWE |
| TCL | Tung Chung Line | HOK, KOW, OLY, NAC, LAK, TSY, SUN, TUC |
| TML | Tuen Ma Line | WKS, MOS, HEO, TSH, SHM, CIO, STW, CKT, TAW, HIK, DIH, KAT, SUW, TKW, HOM, HUH, ETS, AUS, NAC, MEF, TWW, KSR, YUL, LOP, TIS, SIH, TUM |
| TKL | Tseung Kwan O | NOP, QUB, YAT, TIK, TKO, LHP, HAH, POA |
| EAL | East Rail Line | ADM, EXC, HUH, MKK, KOT, TAW, SHT, FOT, RAC, UNI, TAP, TWO, FAN, SHS, LOW, LMC |
| SIL | South Island | ADM, OCP, WCH, LET, SOH |
| TWL | Tsuen Wan Line | CEN, ADM, TST, JOR, YMT, MOK, PRE, SSP, CSW, LCK, MEF, LAK, KWF, KWH, TWH, TSW |
| ISL | Island Line | KET, HKU, SYP, SHW, CEN, ADM, WAC, CAB, TIH, FOH, NOP, QUB, TAK, SWH, SKW, HFC, CHW |
| KTL | Kwun Tong Line | WHA, HOM, YMT, MOK, PRE, SKM, KOT, LOF, WTS, DIH, CHH, KOB, NTK, KWT, LAT, YAT, TIK |
| DRL | Disneyland Resort Line | SUN, DIS |

[^2][^1]

## HTTP Response Codes

| Code | Meaning |
| :-- | :-- |
| 200 | Success |
| 429 | Too Many Requests |
| 500 | Internal Server Error |

[^2]

## Example Request

```http
https://rt.data.gov.hk/v1/transport/mtr/getSchedule.php?line=TKL&sta=TKO&lang=EN
```


## JSON Response Structure

### Top-Level Fields

```json
{
  "sys_time": "yyyy-MM-dd HH:mm:ss",      // System timestamp
  "curr_time": "yyyy-MM-dd HH:mm:ss",     // Current system time
  "data": {
    "LINE-STA": {
      "UP": [ ... ],
      "DOWN": [ ... ],
      "curr_time": "...",
      "sys_time": "..."
    }
  },
  "status": 1,               // 1 for success, 0 for error/alert
  "message": "successful",   // Status message
  "isdelay": "N",            // Optional: "N" for on-time, "Y" for delayed
  "url": "https://..."       // Optional: alert info/special arrangements
}
```


### Data Array: UP/DOWN Structure

Each direction array contains up to four upcoming trains:


| Name | Type | Description |
| :-- | :-- | :-- |
| ttnt | Dummy | N/A |
| valid | Dummy | N/A |
| plat | Number | Platform number for arrival/departure |
| time | String | `"yyyy-MM-dd HH:mm:ss"` - estimated arrival/departure time |
| source | Dummy | N/A |
| dest | String | 3-letter MTR station code |
| seq | Number | Sequence index: 1-4 |
| timetype | String | `"A"` (Arrival) or `"D"` (Departure), EAL only |
| route | String | `""` (Normal) / `"RAC"` (Racecourse via), EAL only |

[^1]

### Direction Semantics (UP/DOWN)

Each line’s UP/DOWN directions correspond to specific destination stations:


| Line | UP Destinations | DOWN Destinations |
| :-- | :-- | :-- |
| AEL | AIR, AWE | HOK |
| TCL | TUC | HOK |
| TML | TUM | WKS |
| TKL | POA, LHP | TIK, NOP |
| EAL | LMC, LOW, SHS, TAP, RAC, FOT, SHT | ADM, HUH, MKK |
| SIL | SOH | ADM |
| TWL | TSW | CEN |
| ISL | CHW | KET |
| KTL | TIK | WHA |
| DRL | SUN | DIS |

[^1]

## Error Cases and Alerts

- **Special Train Services Arrangement**
    - `status = 0`
    - Human-readable `message` and optional `url` field with alert info
    - Example:

```json
{
  "status": 0,
  "message": "Special train service arrangements are now in place...",
  "url": "https://mtr.com.hk/alert.html",
  "curr_time": "yyyy-MM-dd HH:mm:ss"
}
```

- **Data Absence**
    - `sys_time` and `curr_time` may be hyphens ("-")
    - UP/DOWN arrays may be empty if no upcoming trains[^2]
- **Station Suspensions**
    - `status = 0`, message may indicate suspension for specific stations (e.g., LOW or LMC on EAL)[^2]


## Version History

| Version | Major Changes | Effective Date |
| :-- | :-- | :-- |
| 1.0 | Initial Release | 18 July 2019 |
| 1.1 | Added Tuen Ma Line (TML) | 27 June 2021 |
| 1.2 | Added East Rail Line (EAL) + new fields | 15 May 2022 |
| 1.3 | Added South Island Line (SIL) | 30 Jan 2023 |
| 1.4 | Added Tsuen Wan Line (TWL) | 17 Apr 2023 |
| 1.5 | Added Island Line (ISL) | 19 Jul 2023 |
| 1.6 | Added Kwun Tong Line (KTL) | 11 Oct 2023 |
| 1.7 | Added Disneyland Resort Line (DRL) | 13 Mar 2025 |

[^1][^2]

## Implementation Guidelines

- Always verify valid line–station combinations before requesting data.[^1]
- Parse all time fields as fixed-format strings: `"yyyy-MM-dd HH:mm:ss"`.[^2][^1]
- Treat train direction semantics according to UP/DOWN rules per line for accurate passenger information.[^1]
- Surface alerts and delays (`status=0`, `isdelay=Y`) promptly as operational exceptions.[^2]
- Respect API rate limits. Handle HTTP 429 by backing off and retrying gracefully.[^2]
- For EAL, include timetype and route fields if present for platform/route management.[^1]

***

This specification ensures robust, compliant, and efficient agent integration for all plan and operational tasks related to the Next Train API v1.7.[^1][^2]

<div align="center">⁂</div>

[^1]: Next_Train_DataDictionary_v1.7.pdf

[^2]: Next_Train_API_Spec_v1.7.pdf

