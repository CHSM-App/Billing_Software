-- Drops bills.notes. Any customer instructions already recorded on bills go
-- with it — they are only a copy of online_orders.note, which is untouched, so
-- nothing is permanently lost.
--
-- routes/online_orders.js and routes/kitchen.js reference this column; roll the
-- code back alongside it or accepting an online order will fail.
IF COL_LENGTH('bills', 'notes') IS NOT NULL
    ALTER TABLE bills DROP COLUMN notes
GO
