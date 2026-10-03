# Billing App Backend

Express.js + MSSQL backend for the billing app.

## 1. Install SQL Server

**Option A — SQL Server Developer Edition (Windows)**
Download free from: https://www.microsoft.com/en-us/sql-server/sql-server-downloads
Choose "Developer" edition. After install, enable TCP/IP in SQL Server Configuration Manager and note the SA password you set.

**Option B — Docker (cross-platform, uses Azure SQL Edge)**
```bash
docker run -e "ACCEPT_EULA=1" -e "MSSQL_SA_PASSWORD=YourStrongPass123!" \
  -p 1433:1433 --name billing-sql -d mcr.microsoft.com/azure-sql-edge
```

## 2. Create the database

Connect with SQL Server Management Studio (SSMS) or `sqlcmd`:
```sql
CREATE DATABASE billing_app;
```

Or via sqlcmd:
```bash
sqlcmd -S localhost -U sa -P "YourStrongPass123!" -Q "CREATE DATABASE billing_app"
```

## 3. Configure environment

Edit `.env` in the backend root:
```
DB_HOST=localhost
DB_PORT=1433
DB_USER=sa
DB_PASSWORD=YourStrongPass123!
DB_NAME=billing_app
JWT_SECRET=changeme
PORT=3000
```

## 4. Create the schema

**Option A — Node script (recommended)**
```bash
node src/init-db.js
```
This reads `src/schema.sql` and runs it against the database. Safe to re-run — it will say "Tables already exist" if schema is already applied.

**Option B — SSMS**
Open SSMS, connect to your server, open `src/schema.sql`, and press F5.

**Option C — sqlcmd**
```bash
sqlcmd -S localhost -U sa -P "YourStrongPass123!" -d billing_app -i src/schema.sql
```

## 5. Install and run

```bash
npm install
npm start
```

## 6. Verify

```bash
curl http://localhost:3000/health
# Expected: {"ok":true}
```

## 7. Manual owner verification

New registrations land with `is_verified = 0`. You approve them manually in the database.

**See pending registrations:**
```sql
SELECT id, name, phone, business_type, created_at
FROM businesses
WHERE is_verified = 0;
```

**Approve a business:**
```sql
UPDATE businesses SET is_verified = 1 WHERE id = '<paste-uuid-here>';
```

## 8. Test the registration + login flow

```bash
# 1. Register a new owner
curl -X POST http://localhost:3000/api/register \
  -H "Content-Type: application/json" \
  -d '{
    "business_name": "Sharma General Store",
    "business_type": "retail",
    "address": "123 Main Road, Mumbai",
    "phone": "9876543210",
    "inventory_enabled": true,
    "has_barcode_scanner": false,
    "owner_name": "Ramesh Sharma",
    "owner_phone": "9876543210",
    "pin": "1234"
  }'
# Expected: {"success":true,"message":"Registration successful. Account pending verification."}

# 2. Try to login — should be blocked
curl -X POST http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"9876543210","pin":"1234"}'
# Expected: 403 {"error":"Your account is pending verification. Please wait."}

# 3. Approve in DB (run the UPDATE SQL above)

# 4. Login again — should succeed
curl -X POST http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"phone":"9876543210","pin":"1234"}'
# Expected: {"success":true,"token":"...","user":{...},"business":{...}}
```
