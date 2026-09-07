import os
import re
import json
import sqlite3
import hashlib
import urllib.request
from datetime import datetime, timedelta, date
import icalendar
import recurring_ical_events

# Script lives in 'dashboard-dependencies'
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "calendar-config.json")

# ==============================================================================
# DEFAULT CONFIGURATION MATRIX
# ==============================================================================
DEFAULT_FEEDS = [
    {
        "name": "ProtonCalendar",
        "url": "YOUR_PROTON_FEED_URL_HERE",
        "default_color": "#e06666",
    },
    {
        "name": "CanadianHolidays",
        "url": "https://calendar.google.com/calendar/ical/en.canadian%23holiday%40group.v.calendar.google.com/public/basic.ics",
        "default_color": "#8fce00",
    },
    {
        "name": "CanadianObservances",
        "url": "https://calendar.google.com/calendar/ical/en.canadian.official%23holiday%40group.v.calendar.google.com/public/basic.ics",
        "default_color": "#8fce00",
    },
]

def load_feeds():
    """Load feeds from calendar-config.json located in dashboard-dependencies."""
    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                feeds = data.get("FEEDS", [])
                if feeds:
                    return feeds
        except Exception as e:
            print(f"Warning: Failed to load {CONFIG_FILE}, using defaults. Error: {e}")
    else:
        print(f"Warning: {CONFIG_FILE} not found. Using default feed matrix.")
    return DEFAULT_FEEDS

CONFIG = {
    "PATHS": {
        "BASE_DIR": PROJECT_ROOT,
        "STATUS_FILE": os.path.join(PROJECT_ROOT, "proton_sync.status"),
        "DB_FILENAME": "app.db",
        "SEARCH_SUBDIRS": ["data", "", "instance"],
    },
    "SYNC_WINDOW_DAYS": 1095,  # 3 years past/future
    "CLEANUP": {
        "EXACT_ORIGINS": ["ProtonCalendar", "CanadianHolidays", "CanadianObservances", "OfficialCanada", "GoogleHolidays"],
        "LIKE_PATTERNS": ["%Holiday%", "%Canada%", "%Proton%"],
    },
    "RULES": {
        "NATIONWIDE_KEYWORDS": [
            "labour day", "labor day", "canada day", "new year's day", 
            "good friday", "christmas day"
        ],
        "RELIGIOUS_OBSERVANCES": [
            "orthodox christmas", "epiphany", "orthodox new year", 
            "ash wednesday", "palm sunday", "maundy thursday", "orthodox easter"
        ],
        "SPLIT_RULES": {
            "truth and reconciliation": {
                "CanadianHolidays": ("National Day for Truth and Reconciliation (regional)", "Public holiday in British Columbia, Manitoba, Northwest Territories, Nunavut, Prince Edward Island, Yukon"),
                "CanadianObservances": ("National Day for Truth and Reconciliation (regional)", "Observance in Alberta, New Brunswick, Newfoundland and Labrador, Nova Scotia, Ontario, Quebec, Saskatchewan")
            },
            "thanksgiving": {
                "CanadianHolidays": ("Thanksgiving (regional)", "Public holiday in Alberta, British Columbia, Manitoba, New Brunswick, Northwest Territories, Nunavut, Ontario, Quebec, Saskatchewan, Yukon"),
                "CanadianObservances": ("Thanksgiving (regional)", "Observance in Newfoundland and Labrador, Nova Scotia, Prince Edward Island")
            },
            "remembrance": {
                "CanadianHolidays": ("Remembrance Day (regional)", "Public holiday in Alberta, British Columbia, New Brunswick, Newfoundland and Labrador, Northwest Territories, Nunavut, Prince Edward Island, Saskatchewan, Yukon"),
                "CanadianObservances": ("Remembrance Day (regional)", "Observance in Manitoba, Nova Scotia, Ontario, Quebec")
            },
            "victoria day": {
                "CanadianHolidays": ("Victoria Day (regional)", "Public holiday in Alberta, British Columbia, Manitoba, New Brunswick, Northwest Territories, Nunavut, Ontario, Quebec, Saskatchewan, Yukon"),
                "CanadianObservances": ("Victoria Day (regional)", "Observance in Newfoundland and Labrador, Nova Scotia, Prince Edward Island")
            },
            "boxing day": {
                "CanadianHolidays": ("Boxing Day (regional)", "Public holiday in Northwest Territories, Ontario"),
                "CanadianObservances": ("Boxing Day (regional)", "Observance in Alberta, British Columbia, Manitoba, New Brunswick, Newfoundland and Labrador, Nova Scotia, Nunavut, Prince Edward Island, Quebec, Saskatchewan, Yukon")
            }
        }
    }
}

# ==============================================================================
# HELPER UTILITIES
# ==============================================================================

def locate_or_create_database():
    base_dir = CONFIG["PATHS"]["BASE_DIR"]
    db_name = CONFIG["PATHS"]["DB_FILENAME"]
    
    # Check standard subdirectories
    for sub in CONFIG["PATHS"]["SEARCH_SUBDIRS"]:
        path = os.path.join(base_dir, sub, db_name) if sub else os.path.join(base_dir, db_name)
        if os.path.exists(path):
            return path
            
    for root, _, files in os.walk(base_dir):
        if db_name in files:
            return os.path.join(root, db_name)
            
    # Fallback: return root path for creation
    return os.path.join(base_dir, db_name)

def ensure_schema(cursor):
    """Ensure calendars and calendar_events tables exist if app.db is newly initialized."""
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS calendars (
            id TEXT PRIMARY KEY,
            name TEXT,
            color TEXT
        );
    """)
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS calendar_events (
            uid TEXT PRIMARY KEY,
            calendar_id TEXT,
            summary TEXT,
            description TEXT,
            location TEXT,
            dtstart TEXT,
            dtend TEXT,
            all_day INTEGER,
            is_utc INTEGER DEFAULT 0,
            status TEXT DEFAULT 'confirmed',
            color TEXT,
            origin TEXT,
            created_at TEXT,
            updated_at TEXT
        );
    """)

def save_status(state, info):
    try:
        with open(CONFIG["PATHS"]["STATUS_FILE"], "w", encoding="utf-8") as f:
            f.write(f"{state}|{datetime.now().strftime('%m-%d %H:%M')}|{info}")
    except Exception:
        pass

def format_sqlite_date(dt, is_end_of_day=False):
    if dt is None:
        return None
    if isinstance(dt, datetime):
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(dt, date):
        return dt.strftime("%Y-%m-%d 23:59:59" if is_end_of_day else "%Y-%m-%d 00:00:00")
    return str(dt)

def clean_google_description(description):
    desc = re.sub(r'To hide observances, go to Google Calendar Settings.*', '', description, flags=re.IGNORECASE | re.DOTALL).strip()
    return "Observance in Canada" if desc.lower() in ["observance", "public holiday", ""] else desc

def normalize_event(summary, description, source_name):
    clean_desc = clean_google_description(description)
    lower_sum = summary.lower()
    rules = CONFIG["RULES"]

    for rel_kw in rules["RELIGIOUS_OBSERVANCES"]:
        if rel_kw in lower_sum:
            return summary.strip(), "Observance in Canada", "OBSERVANCE"

    for key, data in rules["SPLIT_RULES"].items():
        if key in lower_sum and source_name in data:
            return data[source_name][0], data[source_name][1], "SPLIT"

    for kw in rules["NATIONWIDE_KEYWORDS"]:
        if kw in lower_sum:
            clean_title = re.sub(r'\s*\((regional|regional holiday)\)', '', summary, flags=re.IGNORECASE).strip()
            return clean_title, "Public holiday", "NATIONWIDE"

    clean_title = summary.replace("(regional holiday)", "(regional)").strip()
    if source_name == "CanadianObservances":
        desc = clean_desc if ("observance" in clean_desc.lower()) else "Observance in Canada"
        return clean_title, desc, "OBSERVANCE"

    return clean_title, clean_desc, "GENERAL"

# ==============================================================================
# FETCH & SYNC ENGINE
# ==============================================================================

def clear_existing_entries(cursor):
    exact_origins = CONFIG["CLEANUP"]["EXACT_ORIGINS"]
    like_patterns = CONFIG["CLEANUP"]["LIKE_PATTERNS"]
    
    exact_clause = f"origin IN ({','.join(['?'] * len(exact_origins))})"
    like_clause = " OR ".join(["origin LIKE ?"] * len(like_patterns))
    
    query = f"DELETE FROM calendar_events WHERE {exact_clause} OR {like_clause};"
    cursor.execute(query, exact_origins + like_patterns)

def fetch_feed_events(feed, start_window, end_window):
    if not feed.get("url") or feed["url"].startswith("YOUR_"):
        print(f"Skipping {feed['name']}: Feed URL not configured.")
        return []

    try:
        req = urllib.request.Request(feed["url"], headers={'User-Agent': 'Mozilla/5.0'})
        ics_data = urllib.request.urlopen(req).read()
        calendar = icalendar.Calendar.from_ical(ics_data)
        events = recurring_ical_events.of(calendar).between(start_window, end_window)
        print(f"Fetched {len(events)} events for {feed['name']}.")
        return events
    except Exception as e:
        print(f"Could not fetch {feed['name']}: {e}")
        return []

def process_events(feed, raw_events, seen_keys):
    records = []
    source_name = feed["name"]
    default_color = feed["default_color"]

    for event in raw_events:
        raw_uid = str(event.get("UID", "event"))
        summary = str(event.get("SUMMARY", "Untitled Event"))
        raw_description = str(event.get("DESCRIPTION", ""))
        location = str(event.get("LOCATION", ""))
        
        event_color = str(event.get("COLOR", "")).strip() or str(event.get("X-COLOR", "")).strip() or default_color

        dtstart_raw = event.get("DTSTART")
        dtend_raw = event.get("DTEND")
        dtstart = dtstart_raw.dt if dtstart_raw else None
        dtend = dtend_raw.dt if dtend_raw else dtstart

        is_all_day = 1 if (dtstart and isinstance(dtstart, date) and not isinstance(dtstart, datetime)) else 0

        if is_all_day:
            start_str = format_sqlite_date(dtstart, is_end_of_day=False)
            if isinstance(dtend, date) and not isinstance(dtend, datetime) and dtend > dtstart:
                end_str = format_sqlite_date(dtend - timedelta(days=1), is_end_of_day=True)
            else:
                end_str = format_sqlite_date(dtstart, is_end_of_day=True)
        else:
            start_str = format_sqlite_date(dtstart)
            end_str = format_sqlite_date(dtend)

        date_key = start_str[:10] if start_str else "0000-00-00"

        if source_name in ["CanadianHolidays", "CanadianObservances"]:
            final_title, final_desc, event_type = normalize_event(summary, raw_description, source_name)
            
            if event_type == "NATIONWIDE":
                dedupe_key = (date_key, final_title.lower())
            elif event_type == "OBSERVANCE":
                dedupe_key = (date_key, final_title.lower(), "observance")
            elif event_type == "SPLIT":
                dedupe_key = (date_key, final_title.lower(), source_name)
            else:
                dedupe_key = None

            if dedupe_key:
                if dedupe_key in seen_keys:
                    continue
                seen_keys.add(dedupe_key)
        else:
            final_title = summary
            final_desc = clean_google_description(raw_description)

        content_hash = hashlib.md5(f"{final_title}_{final_desc}".encode('utf-8')).hexdigest()[:8]
        db_uid = f"{source_name}_{raw_uid}_{date_key}_{content_hash}"

        records.append({
            "uid": db_uid,
            "summary": final_title,
            "description": final_desc,
            "location": location,
            "dtstart": start_str,
            "dtend": end_str,
            "all_day": is_all_day,
            "color": event_color,
            "origin": source_name
        })

    return records

def sync_proton_to_odysseus():
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Calendar Sync starting...")
    
    db_path = locate_or_create_database()
    active_feeds = load_feeds()

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        ensure_schema(cursor)
        clear_existing_entries(cursor)

        cursor.execute("SELECT id FROM calendars LIMIT 1;")
        cal_row = cursor.fetchone()
        primary_cal_id = cal_row[0] if cal_row and cal_row[0] else "default"

        cursor.execute("PRAGMA table_info(calendar_events);")
        columns = [c[1] for c in cursor.fetchall()]
        has_color_col = "color" in columns

        days = CONFIG["SYNC_WINDOW_DAYS"]
        start_window = datetime.now() - timedelta(days=days)
        end_window = datetime.now() + timedelta(days=days)
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        all_records = []
        seen_keys = set()

        for feed in active_feeds:
            raw_events = fetch_feed_events(feed, start_window, end_window)
            feed_records = process_events(feed, raw_events, seen_keys)
            all_records.extend(feed_records)

        for r in all_records:
            if has_color_col:
                cursor.execute("""
                    INSERT OR REPLACE INTO calendar_events (
                        uid, calendar_id, summary, description, location,
                        dtstart, dtend, all_day, is_utc, status, color, origin, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'confirmed', ?, ?, ?, ?)
                """, (r["uid"], primary_cal_id, r["summary"], r["description"], r["location"],
                      r["dtstart"], r["dtend"], r["all_day"], r["color"], r["origin"], now_str, now_str))
            else:
                cursor.execute("""
                    INSERT OR REPLACE INTO calendar_events (
                        uid, calendar_id, summary, description, location,
                        dtstart, dtend, all_day, is_utc, status, origin, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'confirmed', ?, ?, ?)
                """, (r["uid"], primary_cal_id, r["summary"], r["description"], r["location"],
                      r["dtstart"], r["dtend"], r["all_day"], r["origin"], now_str, now_str))

        conn.commit()
        conn.close()
        
        total_synced = len(all_records)
        print(f"Sync complete ({total_synced} items).")
        save_status("OK", f"{total_synced} Entries")

    except Exception as e:
        print(f"Database error: {e}")
        save_status("ERROR", "DB Write Failed")

if __name__ == "__main__":
    sync_proton_to_odysseus()