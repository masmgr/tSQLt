/*
  Run in the database from which tSQLt should be removed, using an account
  with permission to drop its objects, assembly and database user.

  This script also works after an incomplete installation and can be rerun.
  It does not require any installed tSQLt procedures, functions or CLR code.
  User test schemas and server-level configuration are left in place.
  External dependencies or database corruption can prevent complete removal;
  SQL Server errors are reported to the caller.
*/
DECLARE @ClassName NVARCHAR(MAX) = 'tSQLt';
/*--DROPSTATEMENT--*/
GO
/*--UNINSTALL--*/
GO
