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

-- QUERY 2: Get the top 20 most rented movies (by rental count), and see if their average rental duration (by days) is longer than the average in its category
SELECT 
	f1.title, 
  COUNT(f1.title) AS no_rentals, 
  AVG(TIMESTAMPDIFF(DAY, r1.rental_date, r1.return_date)) AS film_avg_rental_period,
  CASE 
    WHEN (
      SELECT AVG(TIMESTAMPDIFF(DAY, r2.rental_date, r2.return_date))
      FROM film f2
      JOIN inventory i2 ON f2.film_id = i2.film_id
      JOIN rental r2 ON i2.inventory_id = r2.inventory_id
      JOIN film_category fc2 ON f2.film_id = fc2.film_id
      WHERE fc1.category_id = fc2.category_id
      GROUP BY fc2.category_id
    ) < AVG(TIMESTAMPDIFF(DAY, r1.rental_date, r1.return_date)) THEN 'TRUE'
    ELSE 'FALSE'
  END AS is_rented_longer_than_category_average
FROM film f1
JOIN inventory i1 ON f1.film_id = i1.film_id
JOIN rental r1 ON i1.inventory_id = r1.inventory_id
JOIN film_category fc1 ON f1.film_id = fc1.film_id 
GROUP BY f1.title, fc1.category_id
ORDER BY no_rentals DESC, film_avg_rental_period DESC
LIMIT 20;

EXPLAIN SELECT 
	f1.title, 
  COUNT(f1.title) AS no_rentals, 
  AVG(TIMESTAMPDIFF(DAY, r1.rental_date, r1.return_date)) AS film_avg_rental_period,
  CASE 
    WHEN (
      SELECT AVG(TIMESTAMPDIFF(DAY, r2.rental_date, r2.return_date))
      FROM film f2
      JOIN inventory i2 ON f2.film_id = i2.film_id
      JOIN rental r2 ON i2.inventory_id = r2.inventory_id
      JOIN film_category fc2 ON f2.film_id = fc2.film_id
      WHERE fc1.category_id = fc2.category_id
      GROUP BY fc2.category_id
    ) < AVG(TIMESTAMPDIFF(DAY, r1.rental_date, r1.return_date)) THEN 'TRUE'
    ELSE 'FALSE'
  END AS is_rented_longer_than_category_average
FROM film f1
JOIN inventory i1 ON f1.film_id = i1.film_id
JOIN rental r1 ON i1.inventory_id = r1.inventory_id
JOIN film_category fc1 ON f1.film_id = fc1.film_id 
GROUP BY f1.title, fc1.category_id
ORDER BY no_rentals DESC, film_avg_rental_period DESC
LIMIT 20;

-- QUERY 3:

-- QUERY 4:

-- ----------------------------------------------------------------------------
-- PART 2: APPLY OPTIMIZATIONS (INDEXING)
-- ----------------------------------------------------------------------------
