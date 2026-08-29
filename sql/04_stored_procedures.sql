-- Remove the existing procedure before recreating it.
DROP PROCEDURE IF EXISTS sp_book_trip(UUID, UUID, DECIMAL, UUID, TEXT);

-- Procedure for atomically booking a trip and deducting the fare.
CREATE OR REPLACE PROCEDURE sp_book_trip(
    IN  p_rider_id     UUID,
    IN  p_vehicle_id   UUID,
    IN  p_fare_amount  DECIMAL(10,2),
    OUT p_trip_id      UUID,
    OUT p_status       TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Stores the new trip ID and error information.
    v_new_trip_id UUID;
    v_failed      BOOLEAN := false;
    v_error_msg   TEXT;
BEGIN

    -- Mark the wallet update as an escrow hold for the audit trigger.
    PERFORM set_config('ridesync.wallet_action', 'ESCROW_HOLD', true);

    -- Inner block handles errors while keeping transaction control outside.
    BEGIN
        -- Reject zero or negative fares.
		IF p_fare_amount <= 0 THEN
	    	RAISE EXCEPTION 'Fare amount must be greater than zero';
		END IF;
		
        -- Deduct the fare from the rider's wallet.
        -- The wallet CHECK constraint prevents insufficient funds.
        UPDATE riders
           SET wallet_balance = wallet_balance - p_fare_amount
         WHERE id = p_rider_id;

        -- Fail if the specified rider does not exist.
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Rider % not found', p_rider_id
                USING ERRCODE = 'no_data_found';
        END IF;

        -- Create the trip with REQUESTED status.
        INSERT INTO trips (rider_id, vehicle_id, fare_amount, status)
        VALUES (p_rider_id, p_vehicle_id, p_fare_amount, 'REQUESTED')
        RETURNING id INTO v_new_trip_id;

    EXCEPTION
        -- Handle wallet/check constraint violations.
        WHEN check_violation THEN
            v_failed    := true;
            v_error_msg := 'insufficient wallet balance or invalid data (' || SQLERRM || ')';

        -- Handle missing rider/trip data.
        WHEN no_data_found THEN
            v_failed    := true;
            v_error_msg := SQLERRM;

        -- Handle any other unexpected error.
        WHEN OTHERS THEN
            v_failed    := true;
            v_error_msg := SQLERRM;
    END;

    -- Commit successful bookings or roll back failed ones.
    IF v_failed THEN
        ROLLBACK;
        p_trip_id := NULL;
        p_status  := 'FAILED: ' || v_error_msg;
    ELSE
        COMMIT;
        p_trip_id := v_new_trip_id;
        p_status  := 'BOOKED';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- sp_release_escrow (bonus)
-- ---------------------------------------------------------------------

-- Remove the existing escrow-release procedure before recreating it.
DROP PROCEDURE IF EXISTS sp_release_escrow(UUID);

-- Procedure for completing a trip and recording escrow release.
CREATE OR REPLACE PROCEDURE sp_release_escrow(
    IN p_trip_id UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Stores the rider associated with the trip and error information.
    v_rider_id  UUID;
    v_failed    BOOLEAN := false;
    v_error_msg TEXT;
BEGIN
    -- Mark the audit action as an escrow release.
    PERFORM set_config('ridesync.wallet_action', 'ESCROW_RELEASE', true);

    -- Inner block handles errors during trip completion.
    BEGIN
        -- Complete the trip only if it is currently IN_TRANSIT.
        UPDATE trips
           SET status = 'COMPLETED'
         WHERE id = p_trip_id
           AND status = 'IN_TRANSIT'
        RETURNING rider_id INTO v_rider_id;

        -- Fail if the trip does not exist or is not in transit.
        IF v_rider_id IS NULL THEN
            RAISE EXCEPTION 'Trip % not found or not IN_TRANSIT', p_trip_id
                USING ERRCODE = 'no_data_found';
        END IF;

        -- Record the escrow release in the wallet audit log.
        INSERT INTO wallet_audit_logs (rider_id, amount_changed, action_type, balance_after, "timestamp")
        SELECT v_rider_id, 0.00, 'ESCROW_RELEASE', r.wallet_balance, now()
        FROM riders r
        WHERE r.id = v_rider_id;

    EXCEPTION
        -- Handle any error during escrow release.
        WHEN OTHERS THEN
            v_failed    := true;
            v_error_msg := SQLERRM;
    END;

    -- Roll back on failure; otherwise commit the completion.
    IF v_failed THEN
        ROLLBACK;
        RAISE NOTICE 'sp_release_escrow failed: %', v_error_msg;
    ELSE
        COMMIT;
    END IF;
END;
$$;