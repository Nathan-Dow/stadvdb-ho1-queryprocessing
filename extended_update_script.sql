-- Update Script but involving more tables

-- ALTER TABLES

USE sakila;
SET foreign_key_checks = 0;
SET SQL_SAFE_UPDATES = 0;

-- 1. Drop foreign keys that restrict altering the ID columns
ALTER TABLE rental DROP FOREIGN KEY fk_rental_customer;
ALTER TABLE payment DROP FOREIGN KEY fk_payment_customer;
ALTER TABLE payment DROP FOREIGN KEY fk_payment_rental;

-- 2. Expand columns to INT UNSIGNED
ALTER TABLE customer 
    MODIFY customer_id INT UNSIGNED NOT NULL AUTO_INCREMENT;

ALTER TABLE rental 
    MODIFY rental_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    MODIFY customer_id INT UNSIGNED NOT NULL;

ALTER TABLE payment 
    MODIFY payment_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    MODIFY customer_id INT UNSIGNED NOT NULL,
    MODIFY rental_id INT UNSIGNED DEFAULT NULL;

-- 3. Re-attach the foreign keys
ALTER TABLE rental 
    ADD CONSTRAINT fk_rental_customer 
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id) 
    ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE payment 
    ADD CONSTRAINT fk_payment_customer 
    FOREIGN KEY (customer_id) REFERENCES customer (customer_id) 
    ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE payment 
    ADD CONSTRAINT fk_payment_rental 
    FOREIGN KEY (rental_id) REFERENCES rental (rental_id) 
    ON DELETE SET NULL ON UPDATE CASCADE;

SET foreign_key_checks = 1;

-- PROCEDURE
CREATE DEFINER=`root`@`localhost` PROCEDURE `ScaleSakilaData`()
BEGIN
    DECLARE target_actors INT DEFAULT 1200;
    DECLARE target_customers INT DEFAULT 1500;
    DECLARE target_rentals INT DEFAULT 110000;
    
    DECLARE v_min_inv INT;
    DECLARE v_max_inv INT;
    DECLARE v_min_addr INT;
    DECLARE v_max_addr INT;
    DECLARE v_total_cust INT;

    SET autocommit = 0;
    SET unique_checks = 0;
    SET foreign_key_checks = 0;

    -- Retrieve reference bounds
    SELECT MIN(inventory_id), MAX(inventory_id) INTO v_min_inv, v_max_inv FROM inventory;
    SELECT MIN(address_id), MAX(address_id) INTO v_min_addr, v_max_addr FROM address;

    -- STEP A: Scale Reference Tables (actor >= 1,000)
    WHILE (SELECT COUNT(*) FROM actor) < target_actors DO
        INSERT INTO actor (first_name, last_name, last_update)
        SELECT 
            CONCAT('ACTOR', FLOOR(RAND() * 100000)),
            CONCAT('PERFORMER', FLOOR(RAND() * 100000)),
            NOW()
        FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) a
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) b
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) c
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) d;

        COMMIT;
    END WHILE;

    -- STEP B: Scale Descriptive Tables (customer >= 1,000)
    WHILE (SELECT COUNT(*) FROM customer) < target_customers DO
        INSERT INTO customer (store_id, first_name, last_name, email, address_id, active, create_date)
        SELECT 
            ELT(FLOOR(1 + (RAND() * 2)), 1, 2) AS store_id,
            CONCAT('CUST', FLOOR(RAND() * 100000)) AS first_name,
            CONCAT('USER', FLOOR(RAND() * 100000)) AS last_name,
            CONCAT('synth_', UUID_SHORT(), '@example.com') AS email,
            FLOOR(v_min_addr + (RAND() * (v_max_addr - v_min_addr + 1))) AS address_id,
            1 AS active,
            NOW() - INTERVAL FLOOR(RAND() * 730) DAY AS create_date
        FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) a
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) b
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) c
        CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6) d;

        COMMIT;
    END WHILE;

    -- STEP C: Temporary Dense Customer Index for Pareto Selection
    DROP TEMPORARY TABLE IF EXISTS tmp_cust_index;
    CREATE TEMPORARY TABLE tmp_cust_index (
        row_id INT AUTO_INCREMENT PRIMARY KEY,
        customer_id INT UNSIGNED NOT NULL
    );
    INSERT INTO tmp_cust_index (customer_id) 
    SELECT customer_id FROM customer ORDER BY customer_id;

    SELECT COUNT(*) INTO v_total_cust FROM tmp_cust_index;

    -- STEP D: Scale Rentals (Pareto Distribution & Strict Chronology)
    WHILE (SELECT COUNT(*) FROM rental) < target_rentals DO
        INSERT IGNORE INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)
        SELECT 
            raw.rent_date,
            raw.inv_id,
            tc.customer_id,
            NULL AS return_date,
            ELT(FLOOR(1 + (RAND() * 2)), 1, 2) AS staff_id,
            NOW()
        FROM (
            SELECT 
                NOW() - INTERVAL FLOOR(RAND() * 365) DAY 
                      - INTERVAL FLOOR(RAND() * 86400) SECOND AS rent_date,
                FLOOR(v_min_inv + (RAND() * (v_max_inv - v_min_inv + 1))) AS inv_id,
                1 + FLOOR(POW(RAND(), 2.5) * v_total_cust) AS skewed_idx
            FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) d1
            CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) d2
            CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) d3
            CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9 UNION SELECT 10) d4
        ) raw
        JOIN tmp_cust_index tc ON raw.skewed_idx = tc.row_id;

        UPDATE rental 
        SET return_date = CASE 
            WHEN RAND() < 0.04 THEN NULL
            WHEN RAND() < 0.20 THEN rental_date + INTERVAL (8 + FLOOR(RAND() * 14)) DAY
            ELSE rental_date + INTERVAL (1 + FLOOR(RAND() * 7)) DAY
        END
        WHERE return_date IS NULL AND rental_id > 16049;

        COMMIT;
    END WHILE;

    DROP TEMPORARY TABLE IF EXISTS tmp_cust_index;

    -- STEP E: Scale Payments (1:1 with rentals)
    INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date, last_update)
    SELECT 
        r.customer_id,
        r.staff_id,
        r.rental_id,
        ROUND(
            2.99 + 
            CASE 
                WHEN r.return_date IS NULL THEN 19.99
                WHEN TIMESTAMPDIFF(DAY, r.rental_date, r.return_date) > 7 
                     THEN (TIMESTAMPDIFF(DAY, r.rental_date, r.return_date) - 7) * 1.50
                ELSE 0.00
            END + (RAND() * 1.00),
            2
        ) AS amount,
        COALESCE(r.return_date, r.rental_date + INTERVAL 7 DAY) AS payment_date,
        NOW()
    FROM rental r
    LEFT JOIN payment p ON r.rental_id = p.rental_id
    WHERE p.payment_id IS NULL;

    COMMIT;

    SET unique_checks = 1;
    SET foreign_key_checks = 1;
    SET autocommit = 1;
END
