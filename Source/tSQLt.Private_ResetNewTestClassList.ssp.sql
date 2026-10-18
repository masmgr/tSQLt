IF OBJECT_ID('tSQLt.Private_ResetNewTestClassList') IS NOT NULL DROP PROCEDURE tSQLt.Private_ResetNewTestClassList;
GO
---Build+
GO
CREATE PROCEDURE tSQLt.Private_ResetNewTestClassList
AS
BEGIN
  SET NOCOUNT ON;
  DELETE FROM tSQLt.Private_PreviousTestClassList;

  INSERT INTO tSQLt.Private_PreviousTestClassList(ClassName)
  SELECT DISTINCT Name FROM tSQLt.TestClasses;
END;
GO
---Build-
GO
