IF OBJECT_ID('tSQLt.Private_PreviousTestClassList') IS NOT NULL DROP TABLE tSQLt.Private_PreviousTestClassList;
---Build+
CREATE TABLE tSQLt.Private_PreviousTestClassList (
  ClassName NVARCHAR(450) PRIMARY KEY CLUSTERED
);
---Build-
