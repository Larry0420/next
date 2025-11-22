<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# create comprehensive specs for agent read it for efficient plan and operations in .md

Below is a comprehensive Markdown specification for agent usage of the Next Train API v1.7, designed for efficient planning and operations. This summary integrates all essential request, response, validation, and operational semantics needed for robust automation and monitoring.[^1][^2]

***

# Next Train API v1.7 Agent Specification

## Overview

The Next Train API provides real-time train arrival and operational status for all major MTR lines, supporting integration with planning and alert systems. It follows REST conventions and delivers standardized JSON payloads for ease of parsing and automation.[^1]

## Endpoint and Method

- **Method:** GET
- **Endpoint:** Provided by MTR system (see official deployment)
- **Authentication:** Not specified; follow MTR environment policies.


## Parameters

| Parameter | Required | Type | Description | Example |
| :-- | :-- | :-- | :-- | :-- |
| line | Yes | String | MTR line code (AEL, TML, etc) | "AEL" |
| sta | Yes | String | 3-letter station code | "KOW" |
| lang | No | String | "EN" (default), "TC" (Chinese) | "EN" |

- Validate line–sta combinations before issuing requests against enumerated lists.[^2]
- Use lang for localization of messages.


## Supported Lines \& Stations

Reference: See official line \& station lists. Highlights:

- **Airport Express (AEL):** HOK, KOW, TSY, AIR, AWE
- **Tuen Ma Line (TML):** WKS–TUM
- **East Rail Line (EAL):** HOK, MKK, etc.
- **Disneyland Resort Line (DRL):** SUN, DIS
- ...and others


## Response Schema

```json
{
  "sys_time": "2025-03-13 09:01:05", // System time (string)
  "curr_time": "2025-03-13 09:01:05", // Current data timestamp (string)
  "data": {
    "{LINE}-{STA}": {
      "UP": [ /* Train object array */ ],
      "DOWN": [ /* Train object array */ ]
    }
  },
  "status": 1, // 1: Success, 0: Alert/Disruption
  "message": "successful",
  "isdelay": "N", // "Y" or "N"
  "url": "", // Only present in service alerts
}
```


### Train Object (Within UP/DOWN arrays)

| Field | Type | Description |
| :-- | :-- | :-- |
| ttnt | String | Dummy field |
| valid | String | "Y" (valid) / "N" (not valid) |
| plat | String | Platform number |
| time | String | ETA/ETD timestamp ("yyyy-MM-dd HH:mm:ss") |
| source | String | Dummy field |
| dest | String | Destination station code (3-letter) |
| seq | Integer | Order in list (1–4) |
| timetype | String | EAL Only: "A"/"D" (Arrival/Departure) |
| route | String | EAL Only: Route info ("" or "RAC") |

## Direction Semantics

- **UP and DOWN** are line-dependent, not cardinal.
- Example: TML UP = toward TUM, DOWN = toward WKS.
- DRL UP = SUN, DOWN = DIS; refer to data dictionary for each line's terminal mappings.[^2]


## Status \& Error Handling

| Status | Meaning | Response |
| :-- | :-- | :-- |
| 1 | Success | Full normal payload |
| 0 | Alert/Error | `message`, optional `url`, no train data |

Common HTTP codes: 200 (OK), 429 (rate limit), 500 (server error).

- On alert or special arrangements, use message and url for display and workflow escalation.[^1]
- Data absence: sys_time \& curr_time may be "-" (empty) with isdelay = "Y".


## Operational Tips

- Retry with delay on 429 error; monitor status/messages for temporary disruptions.
- Always parse time as string ("yyyy-MM-dd HH:mm:ss", length 19).
- UP/DOWN arrays may be empty at end-of-service or during line suspensions.
- For East Rail, display or act on timetype and route as supplemental train info.


## Version History

- v1.7 (2025-03-13): Adds Disneyland Resort Line (DRL).
- v1.6–v1.1: Progressive inclusion of major lines and new features/fields.
- Use version-specific features as documented.

***

This specification ensures agent implementation is resilient, efficient, and compatible with all current and future MTR operational scenarios.[^2][^1]

<div align="center">⁂</div>

[^1]: Next_Train_API_Spec_v1.7.pdf

[^2]: Next_Train_DataDictionary_v1.7.pdf

