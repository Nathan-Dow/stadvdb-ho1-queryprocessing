-- ============================================================================
-- SAKILA SYNTHETIC DATA PIPELINE (END-TO-END)
-- Runs automatically on standard Sakila schemas without manual fixes
-- Target: customer >= 1,000 | rental >= 100,000 | payment >= 100,000
-- ============================================================================

USE sakila;

-- ----------------------------------------------------------------------------
-- 1. DYNAMICALLY DROP FOREIGN KEYS & RESIZE ID COLUMNS
-- ----------------------------------------------------------------------------
DELIMITER $$  DROP PROCEDURE IF EXISTS PrepareSakilaSchema$$
CREATE PROCEDURE PrepareSakilaSchema()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE drop_sql VARCHAR(500);

    -- Cursor to find all foreign key constraints targeting customer_id or rental_id
    DECLARE fk_cursor CURSOR FOR
        SELECT CONCAT('ALTER TABLE `', TABLE_NAME, '` DROP FOREIGN KEY `', CONSTRAINT_NAME, '`')
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = 'sakila'
          AND REFERENCED_TABLE_NAME IN ('customer', 'rental')
          AND REFERENCED_COLUMN_NAME IN ('customer_id', 'rental_id');

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    SET foreign_key_checks = 0;

    -- Drop all conflicting foreign keys safely regardless of their internal names
    OPEN fk_cursor;
    drop_loop: LOOP
        FETCH fk_cursor INTO drop_sql;
        IF done THEN
            LEAVE drop_loop;
        END IF;
        SET @s = drop_sql;
        PREPARE stmt FROM @s;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END LOOP;
    CLOSE fk_cursor;

    -- Expand column types to INT UNSIGNED so AUTO_INCREMENT won't overflow 65,535
    ALTER TABLE customer 
        MODIFY customer_id INT UNSIGNED NOT NULL AUTO_INCREMENT;

    ALTER TABLE rental 
        MODIFY rental_id INT NOT NULL AUTO_INCREMENT,
        MODIFY customer_id INT UNSIGNED NOT NULL;

    ALTER TABLE payment 
        MODIFY payment_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        MODIFY customer_id INT UNSIGNED NOT NULL,
        MODIFY rental_id INT DEFAULT NULL;

    -- Re-attach standard foreign key relationships
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
END$$  DELIMITER ;  CALL PrepareSakilaSchema(); DROP PROCEDURE PrepareSakilaSchema;  -- ---------------------------------------------------------------------------- -- 2. SYNTHETIC DATA GENERATION PROCEDURE -- ---------------------------------------------------------------------------- DELIMITER $$

DROP PROCEDURE IF EXISTS GenerateSakilaData$$ CREATE PROCEDURE GenerateSakilaData() BEGIN     DECLARE target_customers INT DEFAULT 1500;     DECLARE target_rentals INT DEFAULT 120000;     DECLARE max_inventory_id INT;     DECLARE min_inventory_id INT;          SET autocommit = 0;     SET unique_checks = 0;     SET foreign_key_checks = 0;      SELECT MIN(inventory_id), MAX(inventory_id)      INTO min_inventory_id, max_inventory_id      FROM inventory;      -- STEP A: Seed Customers (Scale to >= 1,000)     WHILE (SELECT COUNT(*) FROM customer) < target_customers DO         INSERT INTO customer (store_id, first_name, last_name, email, address_id, active, create_date)         SELECT              ELT(FLOOR(1 + (RAND() * 2)), 1, 2) AS store_id,             CONCAT('CUST', FLOOR(RAND() * 100000)) AS first_name,             CONCAT('USER', FLOOR(RAND() * 100000)) AS last_name,             CONCAT('synth_', UUID_SHORT(), '@example.com') AS email,             (SELECT address_id FROM address ORDER BY RAND() LIMIT 1) AS address_id,             IF(RAND() > 0.05, 1, 0) AS active,             NOW() - INTERVAL FLOOR(RAND() * 730) DAY AS create_date         FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t1         CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) t2         LIMIT 100;                  COMMIT;     END WHILE;      -- STEP B: Seed Rentals (Scale to >= 100,000 with realistic skew)     WHILE (SELECT COUNT(*) FROM rental) < target_rentals DO         INSERT IGNORE INTO rental (rental_date, inventory_id, customer_id, return_date, staff_id, last_update)         SELECT              rent_date,             inv_id,             cust_id,             CASE                  WHEN RAND() < 0.05 THEN NULL                 WHEN RAND() < 0.15 THEN rent_date + INTERVAL (15 + FLOOR(RAND() * 15)) DAY                 ELSE rent_date + INTERVAL (1 + FLOOR(RAND() * 7)) DAY             END AS return_date,             ELT(FLOOR(1 + (RAND() * 2)), 1, 2) AS staff_id,             NOW()         FROM (             SELECT                  NOW() - INTERVAL FLOOR(RAND() * 365) DAY                        - INTERVAL FLOOR(RAND() * 86400) SECOND                        - INTERVAL FLOOR(RAND() * 1000000) MICROSECOND AS rent_date,                 FLOOR(min_inventory_id + (RAND() * (max_inventory_id - min_inventory_id))) AS inv_id,                 (SELECT customer_id FROM customer ORDER BY customer_id LIMIT 1) +                  FLOOR(POW(RAND(), 2.5) * (SELECT COUNT(*) FROM customer)) AS cust_id             FROM (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) a             CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) b             CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) c             CROSS JOIN (SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) d         ) raw_data         WHERE cust_id IN (SELECT customer_id FROM customer)         LIMIT 2500;          COMMIT;     END WHILE;      -- STEP C: Seed Payments (1:1 with unbilled rentals)     INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date, last_update)     SELECT          r.customer_id,         r.staff_id,         r.rental_id,         ROUND(             2.99 +              CASE                  WHEN r.return_date IS NULL THEN 19.99                 WHEN TIMESTAMPDIFF(DAY, r.rental_date, r.return_date) > 7                      THEN (TIMESTAMPDIFF(DAY, r.rental_date, r.return_date) - 7) * 1.50                 ELSE 0.00             END + (RAND() * 1.00),              2         ) AS amount,         COALESCE(r.return_date, r.rental_date + INTERVAL 7 DAY) AS payment_date,         NOW()     FROM rental r     LEFT JOIN payment p ON r.rental_id = p.rental_id     WHERE p.payment_id IS NULL;      COMMIT;      SET unique_checks = 1;     SET foreign_key_checks = 1;     SET autocommit = 1;  END$$

DELIMITER ;

CALL GenerateSakilaData();
DROP PROCEDURE GenerateSakilaData;

-- ----------------------------------------------------------------------------
-- 3. VERIFICATION
-- ----------------------------------------------------------------------------
SELECT 'customer' AS table_name, COUNT(*) AS total_rows FROM customer
UNION ALL
SELECT 'rental', COUNT(*) FROM rental
UNION ALL
SELECT 'payment', COUNT(*) FROM payment;