import random
import time
import datetime
import psycopg2
import psycopg2.extras as extras
from faker import Faker

PG_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "ridesync_db",
    "user": "postgres",
    "password": "1234",   
}

NUM_RIDERS = 6000
NUM_VEHICLES = 600
NUM_TRIPS = 52000        
DAYS_SPREAD = 60        

fake = Faker("en_IN")   # Indian names

VEHICLE_CLASSES = [
    {"name": "Bike",        "weight": 30, "base_fare": (30, 90)},
    {"name": "Auto",        "weight": 25, "base_fare": (40, 120)},
    {"name": "Mini",        "weight": 20, "base_fare": (80, 220)},
    {"name": "Sedan",       "weight": 12, "base_fare": (120, 320)},
    {"name": "Prime Sedan", "weight": 6,  "base_fare": (180, 450)},
    {"name": "SUV",         "weight": 4,  "base_fare": (250, 600)},
    {"name": "Electric",    "weight": 2,  "base_fare": (100, 280)},
    {"name": "XL",          "weight": 1,  "base_fare": (300, 700)},
]

RTO_CODES = ["TS09", "TS07", "KA01", "KA05", "MH12", "MH01", "DL08", "AP09", "TN07", "UP32"]


def connect():
    return psycopg2.connect(**PG_CONFIG)


def weighted_class():
    classes = [c["name"] for c in VEHICLE_CLASSES]
    weights = [c["weight"] for c in VEHICLE_CLASSES]
    return random.choices(classes, weights=weights, k=1)[0]


def fare_for_class(vehicle_class):
    for c in VEHICLE_CLASSES:
        if c["name"] == vehicle_class:
            low, high = c["base_fare"]
            return round(random.uniform(low, high), 2)
    return round(random.uniform(50, 300), 2)  # fallback


def seed_riders(conn):
    print(f"Creating {NUM_RIDERS} riders...")
    data = []
    for _ in range(NUM_RIDERS):
        name = fake.name()
        if random.random() < 0.85:
            balance = round(random.uniform(50, 800), 2)     
        elif random.random() < 0.97:
            balance = round(random.uniform(800, 2500), 2)    
        else:
            balance = round(random.uniform(2500, 6000), 2)   
        data.append((name, balance))
    with conn.cursor() as cur:
        rows = extras.execute_values(
            cur,
            "INSERT INTO riders (name, wallet_balance) VALUES %s RETURNING id, wallet_balance",
            data,
            fetch=True,
        )
    conn.commit()
    balances = {row[0]: float(row[1]) for row in rows}
    print(f"  done. {len(balances)} riders created.")
    return balances


def seed_vehicles(conn):
    print(f"Creating {NUM_VEHICLES} vehicles...")
    plates = set()
    data = []
    while len(data) < NUM_VEHICLES:
        rto = random.choice(RTO_CODES)
        series = f"{fake.random_uppercase_letter()}{fake.random_uppercase_letter()}"
        number = random.randint(1000, 9999)
        plate = f"{rto}{series}{number}"
        if plate in plates:
            continue
        plates.add(plate)
        vehicle_class = weighted_class()
        # 92% of vehicles active, small % temporarily inactive (maintenance, offline etc.)
        is_active = random.random() < 0.92
        data.append((plate, vehicle_class, is_active))
    with conn.cursor() as cur:
        rows = extras.execute_values(
            cur,
            "INSERT INTO vehicles (license_plate, class, is_active) VALUES %s RETURNING id, class",
            data,
            fetch=True,
        )
    conn.commit()
    vehicles = [{"id": row[0], "class": row[1]} for row in rows]
    print(f"  done. {len(vehicles)} vehicles created.")
    return vehicles


def random_past_timestamp():
    """Spread trips realistically: more trips recently, fewer far in the past,
    and cluster trip times around real commute hours (morning/evening peaks)."""
    days_ago = int(random.triangular(0, DAYS_SPREAD, 0))  
    # Weighted hour: peaks around 8-10am and 6-9pm, quieter overnight
    hour_weights = [1,1,1,1,1,2,4,7,9,8,5,4,4,5,5,4,5,7,9,8,6,4,2,1]
    hour = random.choices(range(24), weights=hour_weights, k=1)[0]
    minute = random.randint(0, 59)
    dt = datetime.datetime.now() - datetime.timedelta(days=days_ago)
    dt = dt.replace(hour=hour, minute=minute, second=random.randint(0, 59), microsecond=0)
    return dt


def seed_trips(conn, balances, vehicles):
    print(f"Creating {NUM_TRIPS} trips (creates ~{NUM_TRIPS*2} audit rows automatically)...")
    rider_ids = list(balances.keys())
    trip_batch = []
    BATCH_SIZE = 2000
    start = time.time()

    with conn.cursor() as cur:
        for i in range(1, NUM_TRIPS + 1):
            rider_id = random.choice(rider_ids)
            vehicle = random.choice(vehicles)
            fare = fare_for_class(vehicle["class"])
            topup = round(fare + random.uniform(20, 600), 2)  

            old_balance = balances[rider_id]
            after_topup = round(old_balance + topup, 2)
            after_fare = round(after_topup - fare, 2)
            balances[rider_id] = after_fare

            # These two UPDATEs are what make the trigger write to wallet_audit_logs
            cur.execute("UPDATE riders SET wallet_balance = %s WHERE id = %s", (after_topup, rider_id))
            cur.execute("UPDATE riders SET wallet_balance = %s WHERE id = %s", (after_fare, rider_id))

            created_at = random_past_timestamp()
            # 95% of seeded trips are COMPLETED (finished rides); a few left REQUESTED/IN TRANSIT
            status_roll = random.random()
            if status_roll < 0.95:
                status = "COMPLETED"
            elif status_roll < 0.98:
                status = "IN TRANSIT"
            else:
                status = "REQUESTED"

            trip_batch.append((rider_id, vehicle["id"], fare, status, created_at))

            if len(trip_batch) >= BATCH_SIZE:
                extras.execute_values(
                    cur,
                    "INSERT INTO trips (rider_id, vehicle_id, fare_amount, status, created_at) VALUES %s",
                    trip_batch,
                )
                conn.commit()
                trip_batch = []
                print(f"  {i}/{NUM_TRIPS} trips done ({time.time()-start:.1f}s elapsed)")

        if trip_batch:
            extras.execute_values(
                cur,
                "INSERT INTO trips (rider_id, vehicle_id, fare_amount, status, created_at) VALUES %s",
                trip_batch,
            )
            conn.commit()

    print("  done.")


def main():
    conn = connect()
    try:
        balances = seed_riders(conn)
        vehicles = seed_vehicles(conn)
        seed_trips(conn, balances, vehicles)
        print("All done!")
    finally:
        conn.close()


if __name__ == "__main__":
    main()