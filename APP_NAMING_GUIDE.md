# App Naming Guide (zh-HK)

## Optimized Names for Hong Kong Traditional Chinese

### **Full Name (name)**
**輕鐵到站時間**
- **Pinyin:** Qīng tiě dào zhàn shí jiān
- **English:** Light Rail Arrival Time
- **Character Count:** 6 characters
- **Usage:** App drawer, install prompt, splash screen, app store

**Why this name:**
- ✅ Clear and descriptive
- ✅ Uses familiar terminology ("輕鐵" is widely recognized in HK)
- ✅ Explains the core function (arrival time)
- ✅ Natural Chinese phrasing
- ✅ SEO-friendly for Hong Kong users

---

### **Short Name (short_name)**
**輕鐵到站**
- **Pinyin:** Qīng tiě dào zhàn
- **English:** LRT Arrival
- **Character Count:** 4 characters
- **Usage:** Home screen icon label, launcher, limited space UI

**Why this name:**
- ✅ Concise (4 characters fits perfectly on home screen)
- ✅ Still descriptive enough to identify the app
- ✅ Natural truncation of the full name
- ✅ Easy to read at small sizes

---

### **Apple Mobile Web App Title**
**輕鐵到站**
- **Same as short_name for consistency**
- **iOS home screen label**

---

### **Description**
**香港輕鐵實時到站資訊查詢**
- **Pinyin:** Xiānggǎng qīng tiě shí shí dào zhàn zī xùn chá xún
- **English:** Hong Kong Light Rail Real-time Arrival Information Query
- **Character Count:** 14 characters

**Keywords included:**
- 香港 (Hong Kong) - Location targeting
- 輕鐵 (Light Rail) - Service type
- 實時 (Real-time) - Key feature
- 到站 (Arrival) - Core function
- 資訊 (Information) - Content type
- 查詢 (Query) - User action

---

## Alternative Name Options

### Option 1: Modern/Tech Style
- **Name:** 輕鐵班次通
- **Short:** 輕鐵通
- **Translation:** Light Rail Schedule Connect
- **Pros:** Modern, catchy
- **Cons:** Less descriptive

### Option 2: Service-Focused
- **Name:** 輕鐵即時到站
- **Short:** 輕鐵到站
- **Translation:** Light Rail Instant Arrival
- **Pros:** Emphasizes real-time aspect
- **Cons:** 5 characters (slightly long)

### Option 3: User-Centric
- **Name:** 搭輕鐵助手
- **Short:** 搭輕鐵
- **Translation:** Ride Light Rail Assistant
- **Pros:** Friendly, helpful tone
- **Cons:** Doesn't highlight arrival times

### Option 4: Action-Oriented (Current Choice ✅)
- **Name:** 輕鐵到站時間
- **Short:** 輕鐵到站
- **Translation:** Light Rail Arrival Time
- **Pros:** Clear, functional, descriptive
- **Cons:** None

---

## Naming Best Practices (zh-HK)

### Character Count Guidelines
| Element | Recommended | Maximum | Current |
|---------|-------------|---------|---------|
| Full Name | 4-8 chars | 12 chars | 6 chars ✅ |
| Short Name | 2-4 chars | 6 chars | 4 chars ✅ |
| Description | 10-20 chars | 30 chars | 14 chars ✅ |

### ✅ Do's
- Use familiar local terminology (輕鐵 not 輕軌)
- Keep short name ≤ 4 characters for home screen
- Use Traditional Chinese (繁體中文) for Hong Kong
- Test name on actual devices (small screens)
- Consider SEO keywords in description

### ❌ Don'ts
- Don't use Simplified Chinese (簡體中文)
- Don't use English unless it's a brand name
- Don't use uncommon/literary terms
- Don't exceed recommended character counts
- Don't use special symbols (emojis, etc.)

---

## SEO Keywords (zh-HK)

### Primary Keywords
1. 輕鐵 (Light Rail)
2. 到站時間 (Arrival Time)
3. 香港 (Hong Kong)
4. 實時 (Real-time)
5. 班次 (Schedule)

### Secondary Keywords
6. 路線 (Route)
7. 車站 (Station)
8. 查詢 (Query)
9. 時刻表 (Timetable)
10. 港鐵 (MTR - related term)

### Long-tail Keywords
- 香港輕鐵到站時間
- 輕鐵實時到站
- 輕鐵班次查詢
- 輕鐵路線圖
- 輕鐵時刻表

---

## Localization Comparison

| Element | English | 繁體中文 (zh-HK) |
|---------|---------|-----------------|
| **Full Name** | LRT Next Train | 輕鐵到站時間 |
| **Short Name** | LRT Next | 輕鐵到站 |
| **Description** | Hong Kong Light Rail real-time arrival information | 香港輕鐵實時到站資訊查詢 |
| **Title** | LRT Next Train | 輕鐵到站時間 |

---

## Testing Checklist

### Visual Testing
- [ ] Test on iOS home screen (short name visibility)
- [ ] Test on Android home screen (icon label)
- [ ] Test in app drawer (full name display)
- [ ] Test in browser tab (title display)
- [ ] Test in PWA install prompt

### Functional Testing
- [ ] Verify correct Traditional Chinese characters
- [ ] Check font rendering on different devices
- [ ] Test search functionality (can users find the app?)
- [ ] Verify no character encoding issues

### SEO Testing
- [ ] Google search in Chinese
- [ ] App store search (if applicable)
- [ ] Voice search compatibility (Cantonese/Mandarin)

---

## Platform-Specific Considerations

### iOS (Safari)
- **apple-mobile-web-app-title:** Uses short name (4 chars max recommended)
- **Language:** Automatically detects zh-HK
- **Font:** Uses system San Francisco font for Chinese

### Android (Chrome)
- **PWA name:** Uses full name from manifest
- **Home screen:** Uses short_name
- **Font:** Uses system Noto Sans CJK

### Desktop (Chrome/Edge)
- **Tab title:** Uses `<title>` tag
- **PWA window:** Uses full name from manifest
- **Taskbar:** May truncate to ~15 characters

---

## Future Enhancements

### Multi-language Support
Consider adding language variants:
```json
{
  "name": "輕鐵到站時間",
  "short_name": "輕鐵到站",
  "lang": "zh-HK",
  "translations": {
    "en": {
      "name": "LRT Next Train",
      "short_name": "LRT Next",
      "description": "Hong Kong Light Rail real-time arrival information"
    },
    "zh-CN": {
      "name": "轻铁到站时间",
      "short_name": "轻铁到站",
      "description": "香港轻铁实时到站信息查询"
    }
  }
}
```

**Note:** PWA manifest doesn't natively support translations yet. This would require JavaScript detection and dynamic manifest generation.

---

## References
- [香港輕鐵官方網站](https://www.mtr.com.hk/ch/customer/services/light_rail.html)
- [Traditional Chinese Web Design Best Practices](https://www.w3.org/International/questions/qa-scripts)
- [PWA Naming Guidelines](https://web.dev/learn/pwa/web-app-manifest/)
- [Hong Kong Chinese Character Standards](https://www.ogcio.gov.hk/tc/our_work/business/tech_promotion/ccli/)
