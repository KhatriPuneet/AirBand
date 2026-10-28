import asyncio
import csv
import json
import math
import os
import statistics
import sys
from datetime import datetime, timezone, timedelta

# Ensure RyzeWaveWatch package is accessible
sys.path.insert(0, os.path.abspath("./RyzeWaveWatch"))

from ryzewave import protocol as P
from ryzewave.client import RyzeWave

AIR_BAND_UUID = "6DB2DAAA-21FD-EF31-DDEF-75B6BBC7E2F0"
OUTPUT_JSON = "airband_healthkit.json"
OUTPUT_CSV = "airband_vitals.csv"


def calculate_hrv_and_resting_hr(hr_records: list[tuple[datetime, int]]):
    """
    Computes Apple Health compatible metrics from 10-minute continuous HR records:
    1. Resting HR: 5th-10th percentile of clean HR readings.
    2. SDNN (HRV): Standard deviation of equivalent normal-to-normal RR intervals in ms.
    3. RMSSD: Root mean square of successive differences in ms.
    """
    if not hr_records:
        return None

    # Sort chronologically
    hr_records = sorted(hr_records, key=lambda x: x[0])
    hrs = [hr for _, hr in hr_records if 40 <= hr <= 200]
    if len(hrs) < 3:
        return None

    # Inter-beat intervals in milliseconds: RR = 60,000 / HR
    rrs = [60000.0 / hr for hr in hrs]

    # SDNN is the gold standard for Apple Health HRV
    sdnn = round(statistics.stdev(rrs), 1)

    # RMSSD
    diffs_sq = [(rrs[i + 1] - rrs[i]) ** 2 for i in range(len(rrs) - 1)]
    rmssd = round(math.sqrt(sum(diffs_sq) / len(diffs_sq)), 1)

    # Resting HR: sorted lower percentile during quiet hours
    sorted_hrs = sorted(hrs)
    resting_hr = sorted_hrs[max(0, int(len(sorted_hrs) * 0.05))]

    return {
        "sdnn_ms": sdnn,
        "rmssd_ms": rmssd,
        "resting_hr_bpm": resting_hr,
        "mean_hr_bpm": round(statistics.mean(hrs), 1),
        "min_hr_bpm": min(hrs),
        "max_hr_bpm": max(hrs),
        "sample_count": len(hrs),
    }


async def run_pipeline():
    print(f"Connecting to Air Band ({AIR_BAND_UUID})...")
    w = RyzeWave(address=AIR_BAND_UUID, name_prefix="Air Band")

    try:
        await w.connect(timeout=25.0, authenticate=False)
    except Exception as e:
        print(f"Could not connect: {e}")
        return False

    print("Connected successfully!")
    results = {
        "extracted_at": datetime.now(timezone.utc).isoformat(),
        "device": {
            "name": "Air Band",
            "uuid": AIR_BAND_UUID,
        },
        "vitals_summary": {},
        "heart_rate_samples": [],
        "spo2_samples": [],
        "sleep_stages": [],
        "step_records": [],
    }

    try:
        # Battery & Version
        try:
            ver = await w.version()
            pct, chg = await w.battery()
            results["device"]["firmware"] = ver
            results["device"]["battery_pct"] = pct
            print(f"Firmware: {ver} | Battery: {pct}%")
        except Exception as e:
            print(f"Device info notice: {e}")

        # Sync 24h Heart Rate
        print("\nSyncing Heart Rate records...")
        try:
            hr_records = await w.fetch_heart_rate()
            print(f"  --> Extracted {len(hr_records)} Heart Rate records.")
            for t, val in hr_records:
                results["heart_rate_samples"].append({
                    "timestamp": t.isoformat(),
                    "bpm": val,
                })

            hrv_metrics = calculate_hrv_and_resting_hr(hr_records)
            if hrv_metrics:
                results["vitals_summary"] = hrv_metrics
                print(f"  --> Computed Apple Health HRV (SDNN): {hrv_metrics['sdnn_ms']} ms")
                print(f"  --> Computed RMSSD: {hrv_metrics['rmssd_ms']} ms")
                print(f"  --> Computed Resting HR: {hrv_metrics['resting_hr_bpm']} bpm")
        except Exception as e:
            print(f"  HR sync warning: {e}")

        # Sync SpO2
        print("\nSyncing SpO2 records...")
        try:
            spo2_records = await w.fetch_spo2()
            print(f"  --> Extracted {len(spo2_records)} SpO2 records.")
            for t, val in spo2_records:
                results["spo2_samples"].append({
                    "timestamp": t.isoformat(),
                    "oxygen_percent": val,
                })
        except Exception as e:
            print(f"  SpO2 sync warning: {e}")

        # Sync Sleep Stages
        print("\nSyncing Sleep Stages...")
        try:
            sleep_records = await w.fetch_sleep()
            print(f"  --> Extracted {len(sleep_records)} Sleep Stages.")
            for s in sleep_records:
                stage_name = {1: "Deep", 2: "Light", 3: "REM", 4: "Awake"}.get(s.stage, "Asleep")
                results["sleep_stages"].append({
                    "start_time": s.when.isoformat(),
                    "stage": stage_name,
                    "stage_code": s.stage,
                    "duration_minutes": s.minutes,
                })
        except Exception as e:
            print(f"  Sleep sync warning: {e}")

    finally:
        await w.disconnect()
        print("\nDisconnected cleanly from band.")

    # Save to JSON for HealthKit / Shortcut consumption
    with open(OUTPUT_JSON, "w") as f:
        json.dump(results, f, indent=2)
    print(f"Successfully saved HealthKit export to {OUTPUT_JSON}")

    # Save flat CSV for viewing/analysis
    with open(OUTPUT_CSV, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "metric_type", "value", "unit"])
        for hr in results["heart_rate_samples"]:
            writer.writerow([hr["timestamp"], "heart_rate", hr["bpm"], "bpm"])
        for sp in results["spo2_samples"]:
            writer.writerow([sp["timestamp"], "oxygen_saturation", sp["oxygen_percent"], "%"])
        for sl in results["sleep_stages"]:
            writer.writerow([sl["start_time"], f"sleep_{sl['stage'].lower()}", sl["duration_minutes"], "minutes"])
        if "vitals_summary" in results and "sdnn_ms" in results["vitals_summary"]:
            writer.writerow([results["extracted_at"], "hrv_sdnn", results["vitals_summary"]["sdnn_ms"], "ms"])
            writer.writerow([results["extracted_at"], "resting_hr", results["vitals_summary"]["resting_hr_bpm"], "bpm"])
    print(f"Successfully saved CSV log to {OUTPUT_CSV}")
    return True


if __name__ == "__main__":
    asyncio.run(run_pipeline())
