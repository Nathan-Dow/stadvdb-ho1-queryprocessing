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

-- QUERY 3: Get the top 10% of customers who rented movies the longest. Do these customers generate above or below average revenue compared to the overall customer base
SELECT 
    ranked.customer_id,
    ranked.customer_name,
    ranked.avg_hours_kept,
    ranked.total_rentals,
    ranked.customer_revenue,

    ranked.overall_mean_rentals,
    ranked.overall_mean_revenue,

    CASE 
        WHEN ranked.customer_revenue > ranked.overall_mean_revenue THEN 'Above Mean'
        ELSE 'At or Below Mean'
    END AS revenue_status
FROM (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        COUNT(r.rental_id) AS total_rentals,
        ROUND(AVG(TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date)), 2) AS avg_hours_kept,
        ROUND(SUM(p.amount), 2) AS customer_revenue,
        
        NTILE(10) OVER (
            ORDER BY AVG(TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date)) DESC
        ) AS duration_decile,
        
        ROUND(AVG(COUNT(r.rental_id)) OVER (), 2) AS overall_mean_rentals,
        ROUND(AVG(SUM(p.amount)) OVER (), 2) AS overall_mean_revenue

    FROM customer c
    JOIN rental r ON c.customer_id = r.customer_id
    JOIN payment p ON r.rental_id = p.rental_id
    WHERE r.return_date IS NOT NULL
      AND r.return_date >= r.rental_date
    GROUP BY c.customer_id, c.first_name, c.last_name
) AS ranked
WHERE ranked.duration_decile = 1
ORDER BY ranked.avg_hours_kept DESC;

-- QUERY 3 (Optimized):
WITH customer_aggregates AS (
    SELECT 
        r.customer_id,
        COUNT(r.rental_id) AS total_rentals,
        ROUND(AVG(TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date)), 2) AS avg_hours_kept,
        ROUND(SUM(p.amount), 2) AS customer_revenue
    FROM rental r
    JOIN payment p ON r.rental_id = p.rental_id
    WHERE r.return_date >= r.rental_date
    GROUP BY r.customer_id
),
ranked_customers AS (
    SELECT 
        ca.customer_id,
        ca.total_rentals,
        ca.avg_hours_kept,
        ca.customer_revenue,
        NTILE(10) OVER (
            ORDER BY ca.avg_hours_kept DESC
        ) AS duration_decile,
        ROUND(AVG(ca.total_rentals) OVER (), 2) AS overall_mean_rentals,
        ROUND(AVG(ca.customer_revenue) OVER (), 2) AS overall_mean_revenue
    FROM customer_aggregates ca
)
SELECT 
    rc.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    rc.avg_hours_kept,
    rc.total_rentals,
    rc.overall_mean_rentals,
    rc.customer_revenue,
    rc.overall_mean_revenue,
    CASE 
        WHEN rc.customer_revenue > rc.overall_mean_revenue THEN 'Above Mean'
        ELSE 'At or Below Mean'
    END AS revenue_status
FROM ranked_customers rc
JOIN customer c ON c.customer_id = rc.customer_id
WHERE rc.duration_decile = 1
ORDER BY rc.avg_hours_kept DESC;

-- QUERY 4: Which film categories generate the most revenue, and what is their average rental duration in hours?
SELECT 
    c.name AS category_name,
    COUNT(r.rental_id) AS total_rentals,
    SUM(p.amount) AS total_revenue,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date)), 2) AS avg_rental_hours
FROM category c
JOIN film_category fc ON c.category_id = fc.category_id
JOIN film f ON fc.film_id = f.film_id
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
WHERE r.return_date IS NOT NULL
GROUP BY c.name
ORDER BY total_revenue DESC;

EXPLAIN SELECT 
    c.name AS category_name,
    COUNT(r.rental_id) AS total_rentals,
    SUM(p.amount) AS total_revenue,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, r.rental_date, r.return_date)), 2) AS avg_rental_hours
FROM category c
JOIN film_category fc ON c.category_id = fc.category_id
JOIN film f ON fc.film_id = f.film_id
JOIN inventory i ON f.film_id = i.film_id
JOIN rental r ON i.inventory_id = r.inventory_id
JOIN payment p ON r.rental_id = p.rental_id
WHERE r.return_date IS NOT NULL
GROUP BY c.name
ORDER BY total_revenue DESC;

-- ----------------------------------------------------------------------------
-- PART 2: APPLY OPTIMIZATIONS (INDEXING)
-- ----------------------------------------------------------------------------
