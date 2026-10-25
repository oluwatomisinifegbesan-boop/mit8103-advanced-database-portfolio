# Advanced Database Systems Portfolio (MIT 8103)

Practical portfolio for MIT 8103 Advanced Database Systems, 2026/2027 First Semester, Miva Open University.

## Case study: EkoMart Online

EkoMart Online is a simulated Nigerian e-commerce platform. Customers in all 36 states and the FCT buy electronics, fashion, home, grocery and beauty products. Orders ship from five regional warehouses (Lagos, Abuja, Kano, Port Harcourt, Onitsha).

The database stores:
- customers and their addresses
- the product catalogue, categories and suppliers
- warehouse stock
- orders and order lines
- payments and shipments
- product reviews

Every portfolio activity uses this same case study. See [Portfolio 1](portfolio-1-database-design/README.md#1-case-study-ekomart-online) for the full statement.

## Portfolio activities

| # | Activity | Folder | Status |
|---|---|---|---|
| 1 | Database Design and Modelling | [`portfolio-1-database-design`](portfolio-1-database-design/) | Done |
| 2 | Query Processing and Optimisation | [`portfolio-2-query-optimisation`](portfolio-2-query-optimisation/) | Done |
| 3 | Transactions and Concurrency | [`portfolio-3-transactions-concurrency`](portfolio-3-transactions-concurrency/) | Done |
| 4 | NoSQL and Advanced Data Models | [`portfolio-4-nosql`](portfolio-4-nosql/) | Not started |
| 5 | Distributed and Cloud Database Exercise | [`portfolio-5-distributed-cloud`](portfolio-5-distributed-cloud/) | Not started |

## Technology

- **PostgreSQL 16**: relational model, query optimisation, transactions (Portfolios 1-3, 5)
- **MongoDB**: document model (Portfolios 4-5)

## Quick start

```bash
createdb ekomart
psql -d ekomart -f portfolio-1-database-design/sql/01_schema.sql
psql -d ekomart -f portfolio-1-database-design/sql/02_seed_data.sql
```
