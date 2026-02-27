from datetime import datetime
from zoneinfo import ZoneInfo

def now_wib():
    """Returns the current time in WIB (Western Indonesian Time) timezone."""
    wib_tz = ZoneInfo("Asia/Jakarta")
    return datetime.now(wib_tz) # format: 2026-02-27 17:32:37.322898+07:00

if __name__ == "__main__":
    print("Current time in WIB:", now_wib())