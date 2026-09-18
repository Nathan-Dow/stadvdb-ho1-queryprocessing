-- ============================================================================
-- SAKILA ANALYTICAL QUERIES & OPTIMIZATION
-- ============================================================================
-- NOTE TO TEAM: Run each query one by one in your DBMS.
-- Record the Execution Time and the EXPLAIN output for the PDF report.

USE sakila;

-- ----------------------------------------------------------------------------
-- PART 1: BASELINE QUERIES (BEFORE OPTIMIZATION)
-- ----------------------------------------------------------------------------
-- QUERY 1: Top 10 Most Profitable Customers (Joins 3 tables: customer, rental, payment)
-- Run this first to get execution time, then run the EXPLAIN below it.
SELECT c.customer_id, c.first_name, c.last_name, SUM(p.amount) AS total_spent 
FROM customer c 
JOIN rental r ON c.customer_id = r.customer_id 
JOIN payment p ON r.rental_id = p.rental_id 
GROUP BY c.customer_id 
ORDER BY total_spent DESC 
LIMIT 10;

EXPLAIN SELECT c.customer_id, c.first_name, c.last_name, SUM(p.amount) AS total_spent 
FROM customer c 
JOIN rental r ON c.customer_id = r.customer_id 
JOIN payment p ON r.rental_id = p.rental_id 
GROUP BY c.customer_id 
ORDER BY total_spent DESC 
LIMIT 10;

-- QUERY 2:

-- QUERY 3:

-- QUERY 4:

-- ----------------------------------------------------------------------------
-- PART 2: APPLY OPTIMIZATIONS (INDEXING)
-- ----------------------------------------------------------------------------
