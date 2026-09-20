USE sakila;

-- 1. Ensure payment_id won't overflow SMALLINT (max 65,535)
ALTER TABLE payment MODIFY payment_id INT UNSIGNED NOT NULL AUTO_INCREMENT;

-- 2. Drop triggers that override synthetic timestamps
DROP TRIGGER IF EXISTS rental_date;
DROP TRIGGER IF EXISTS payment_date;

DELIMITER $$

DROP PROCEDURE IF EXISTS GenerateSakilaAnalyticsData$$
CREATE PROCEDURE GenerateSakilaAnalyticsData()
BEGIN
    DECLARE target_customers INT DEFAULT 2500;   -- Descriptive table: >= 1,000 rows
    DECLARE target_rentals   INT DEFAULT 125000; -- Event table: >= 100,000 rows
    
    DECLARE v_store_id TINYINT UNSIGNED;
    DECLARE v_staff_id TINYINT UNSIGNED;
    DECLARE v_address_id SMALLINT UNSIGNED;
    DECLARE min_cust, max_cust INT;
    DECLARE min_inv, max_inv INT;

    -- Speed optimizations for large batch loads
    SET autocommit = 0;
    SET UNIQUE_CHECKS = 0;
    SET FOREIGN_KEY_CHECKS = 0;

    -- Fetch single known valid FK anchors directly from base tables
    SELECT store_id INTO v_store_id FROM store LIMIT 1;
    SELECT staff_id INTO v_staff_id FROM staff LIMIT 1;
    SELECT address_id INTO v_address_id FROM address LIMIT 1;

    -- =========================================================================
    -- STEP 1: EXPAND CUSTOMERS (Fast bulk insert, no join overhead)
    -- =========================================================================
    WHILE (SELECT COUNT(*) FROM customer) < target_customers DO
        INSERT INTO customer (store_id, first_name, last_name, email, address_id, active, create_date, last_update)
        SELECT
            v_store_id,
            ELT(1 + FLOOR(RAND() * 10), 'JAMES','MARY','ROBERT','PATRICIA','JOHN','JENNIFER','MICHAEL','LINDA','WILLIAM','ELIZABETH'),
            CONCAT('Customer_', UUID_SHORT()),
            CONCAT('c', UUID_SHORT(), '@sakila.org'),
            v_address_id,
            1,
            NOW() - INTERVAL FLOOR(RAND() * 900 * 86400) SECOND,
            NOW()
        FROM
            (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
             UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1
        CROSS JOIN
            (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
             UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2
        CROSS JOIN
            (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
             UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3
        LIMIT 1000;

        COMMIT;
    END WHILE;

    -- Dynamic customer and inventory bounds
    SELECT MIN(inventory_id), MAX(inventory_id) INTO min_inv, max_inv FROM inventory;
    SELECT MIN(customer_id),  MAX(customer_id)  INTO min_cust, max_cust FROM customer;

    -- =========================================================================
    -- STEP 2: EXPAND RENTALS (5,000 per batch, pre-computed return_date)
    -- =========================================================================
    WHILE (SELECT COUNT(*) FROM rental) < target_rentals DO
        INSERT INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
        SELECT
            r_date,
            inv_id,
            cust_id,
            -- Pre-compute return_date directly (prevents a secondary slow UPDATE)
            -- 3% items unreturned (NULL), remainder returned between 12 and ~492 hours
            IF(RAND() <= 0.03, NULL, r_date + INTERVAL FLOOR(POW(RAND(), 1.7) * 480 + 12) HOUR) AS return_date,
            v_staff_id,
            NOW()
        FROM (
            SELECT
                NOW() - INTERVAL (FLOOR(RAND() * 700 * 86400) + (d1.n * 500 + d2.n * 50 + d3.n * 5 + d4.n)) SECOND AS r_date,
                min_inv  + FLOOR(RAND() * (max_inv - min_inv + 1)) AS inv_id,
                -- Skewed customer distribution for realistic deciles
                min_cust + FLOOR(POW(RAND(), 2.4) * (max_cust - min_cust + 1)) AS cust_id
            FROM       (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) d1
            CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2
            CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3
            CROSS JOIN (SELECT 0 n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                        UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d4
        ) gen;

        COMMIT;
    END WHILE;

    -- =========================================================================
    -- STEP 3: INSERT PAYMENTS (Fast single set-based insert)
    -- =========================================================================
    INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date, last_update)
    SELECT
        r.customer_id,
        r.staff_id,
        r.rental_id,
        ROUND(
            2.99 + 
            CASE
                WHEN r.return_date IS NULL THEN 19.99
                WHEN TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date) > 168 
                    THEN ((TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date) - 168) / 24) * 1.50
                ELSE 0.00
            END + (RAND() * 1.25), 
            2
        ) AS amount,
        COALESCE(r.return_date, r.rental_date + INTERVAL 7 DAY) AS payment_date,
        NOW()
    FROM rental r
    LEFT JOIN payment p ON p.rental_id = r.rental_id
    WHERE p.payment_id IS NULL;

    COMMIT;

    -- Restore safety variables
    SET FOREIGN_KEY_CHECKS = 1;
    SET UNIQUE_CHECKS = 1;
    SET autocommit = 1;
END$$

DELIMITER ;

-- Execute
CALL GenerateSakilaAnalyticsData();

-- Verify row counts
SELECT 'customer' AS table_name, COUNT(*) AS total_rows FROM customer
UNION ALL 
SELECT 'rental', COUNT(*) FROM rental
UNION ALL 
SELECT 'payment', COUNT(*) FROM payment;
