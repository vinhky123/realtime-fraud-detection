import math

from app.config import settings


def _to_float(value) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlmb = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlmb / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _z_score(amount: float, avg: float, std: float) -> float:
    if std <= 0:
        return 0.0
    return (amount - avg) / std


def _normalize(value: float, cap: float) -> float:
    return max(0.0, min(value / cap, 1.0))


def evaluate(amount: float, geo_lat: float, geo_lon: float, features: dict | None) -> tuple[float, str]:
    """Compute a risk score in [0,1] and a human reason. Uber-pattern weights."""
    features = features or {}

    avg = _to_float(features.get("rolling_avg_50"))
    std = _to_float(features.get("rolling_std_50"))
    velocity = _to_float(features.get("velocity_15m"))

    z = abs(_z_score(amount, avg, std))
    amount_norm = _normalize(z, 3.0)
    velocity_norm = _normalize(velocity, settings.velocity_threshold)

    geo_norm = 0.0
    reason_parts = []
    if "last_geo_lat" in features and "last_geo_lon" in features and "last_txn_ts" in features:
        last_lat = _to_float(features.get("last_geo_lat"))
        last_lon = _to_float(features.get("last_geo_lon"))
        last_ts = _to_float(features.get("last_txn_ts"))
        cur_ts = _to_float(features.get("updated_at_epoch")) or None
        distance = _haversine_km(last_lat, last_lon, geo_lat, geo_lon)
        if last_ts > 0 and cur_ts and cur_ts > last_ts:
            hours = (cur_ts - last_ts) / 3_600_000.0
            if hours > 0:
                speed = distance / hours
                geo_norm = _normalize(speed, settings.impossible_speed_kmh)
                if geo_norm > 0:
                    reason_parts.append(f"geo speed {speed:.0f}km/h")

    risk = 0.4 * amount_norm + 0.3 * velocity_norm + 0.3 * geo_norm

    if z > 3.0:
        reason_parts.append(f"amount z={z:.2f}")
    if velocity > settings.velocity_threshold:
        reason_parts.append(f"velocity {int(velocity)}")

    reason = "; ".join(reason_parts) if reason_parts else "within normal bounds"
    return risk, reason
