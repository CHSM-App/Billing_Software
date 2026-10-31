-- Nothing to undo: 049 only set settled ('billed') tables to 'empty', the same
-- as staff tapping "Mark as Paid / Empty". Which rows were billed is not
-- recorded, and putting tables back into a state the app no longer produces
-- would only block QR orders again.
SELECT 1
GO
