USE sakila;

-- Temporarily remove the triggers that force dates to NOW()
DROP TRIGGER IF EXISTS rental_date;
DROP TRIGGER IF EXISTS payment_date;

DELIMITER $$
DROP PROCEDURE IF EXISTS GenerateSakilaRentals$$
CREATE PROCEDURE GenerateSakilaRentals()
BEGIN
    DECLARE target_rentals INT DEFAULT 120000;
    DECLARE min_inv, max_inv, min_cust, max_cust, batch_start INT;

    SET autocommit = 0;

    SELECT MIN(inventory_id), MAX(inventory_id) INTO min_inv, max_inv FROM inventory;
    SELECT MIN(customer_id),  MAX(customer_id)  INTO min_cust, max_cust FROM customer;

    -- Rentals: 10,000 per batch
    WHILE (SELECT COUNT(*) FROM rental) < target_rentals DO
        SELECT COALESCE(MAX(rental_id), 0) INTO batch_start FROM rental;

        INSERT IGNORE INTO rental (rental_date, inventory_id, customer_id, staff_id, last_update)
        SELECT
            NOW() - INTERVAL FLOOR(RAND() * 730 * 86400) SECOND,
            min_inv  + FLOOR(RAND() * (max_inv - min_inv + 1)),
            min_cust + FLOOR(POW(RAND(), 2.5) * (max_cust - min_cust + 1)),
            1 + FLOOR(RAND() * 2),
            NOW()
        FROM       (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1
        CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2
        CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3
        CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d4;

        -- Only touch the rows just inserted (uses the primary key, no full scan)
        UPDATE rental
        SET return_date = rental_date + INTERVAL (1 + FLOOR(RAND() * 14)) DAY
        WHERE rental_id > batch_start AND RAND() > 0.05;

        COMMIT;
    END WHILE;

    -- Payments: one per rental that doesn't have one yet
    INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date, last_update)
    SELECT
        r.customer_id, r.staff_id, r.rental_id,
        ROUND(2.99 +
            CASE
                WHEN r.return_date IS NULL THEN 19.99
                WHEN TIMESTAMPDIFF(DAY, r.rental_date, r.return_date) > 7
                    THEN (TIMESTAMPDIFF(DAY, r.rental_date, r.return_date) - 7) * 1.50
                ELSE 0.00
            END + RAND(), 2),
        COALESCE(r.return_date, r.rental_date + INTERVAL 7 DAY),
        NOW()
    FROM rental r
    LEFT JOIN payment p ON p.rental_id = r.rental_id
    WHERE p.payment_id IS NULL;

    COMMIT;
    SET autocommit = 1;
END$$
DELIMITER ;

CALL GenerateSakilaRentals();

-- Restore Sakila's original triggers
CREATE TRIGGER rental_date  BEFORE INSERT ON rental  FOR EACH ROW SET NEW.rental_date  = NOW();
CREATE TRIGGER payment_date BEFORE INSERT ON payment FOR EACH ROW SET NEW.payment_date = NOW();

SELECT 'customer' AS table_name, COUNT(*) AS total_rows FROM customer
UNION ALL SELECT 'rental',  COUNT(*) FROM rental
UNION ALL SELECT 'payment', COUNT(*) FROM payment;

SELECT * FROM rental;
