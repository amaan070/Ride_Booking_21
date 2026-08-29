-- Remove existing trigger and function so they can be recreated cleanly.
DROP TRIGGER IF EXISTS trg_wallet_audit ON riders;
DROP FUNCTION IF EXISTS fn_wallet_audit_log();

-- Trigger function that records every wallet balance change.
CREATE OR REPLACE FUNCTION fn_wallet_audit_log()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    -- Stores the type of wallet action and amount changed.
    v_action_type    VARCHAR(30);
    v_amount_changed DECIMAL(10,2);
BEGIN
    -- Calculate the difference between new and old balance.
    v_amount_changed := NEW.wallet_balance - OLD.wallet_balance;

    -- Get the action tag set by the calling procedure, if any.
    v_action_type := NULLIF(current_setting('ridesync.wallet_action', true), '');

    -- If no action was specified, infer it from the balance change.
    IF v_action_type IS NULL THEN
        IF v_amount_changed >= 0 THEN
            v_action_type := 'CREDIT';
        ELSE
            v_action_type := 'DEBIT';
        END IF;
    END IF;

    -- Insert the wallet change into the audit log.
    INSERT INTO wallet_audit_logs (rider_id, amount_changed, action_type, balance_after, "timestamp")
    VALUES (NEW.id, v_amount_changed, v_action_type, NEW.wallet_balance, now());

    -- Return the updated rider row.
    RETURN NEW;
END;
$$;

-- Run the function after a rider's wallet balance is changed.
CREATE TRIGGER trg_wallet_audit
AFTER UPDATE OF wallet_balance ON riders
FOR EACH ROW
-- Fire only when the balance actually changes.
WHEN (OLD.wallet_balance IS DISTINCT FROM NEW.wallet_balance)
EXECUTE FUNCTION fn_wallet_audit_log();