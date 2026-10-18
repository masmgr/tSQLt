EXEC tSQLt.NewTestClass 'AssertAlmostEqualsTests';
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test equal values and two NULLs succeed with defaults]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 42, 42;
    EXEC tSQLt.AssertAlmostEquals 0, 0;
    EXEC tSQLt.AssertAlmostEquals -42, -42;
    EXEC tSQLt.AssertAlmostEquals NULL, NULL;
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test defaults reject distinct values]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1.0, 1.000001;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 0, 1e-300;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test absolute tolerance includes its boundary]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 1, 1.125, 0.25;
    EXEC tSQLt.AssertAlmostEquals 1, 1.25, 0.25;
    EXEC tSQLt.AssertAlmostEquals 1.25, 1, 0.25;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1, 1.5, 0.25;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test relative tolerance uses the larger magnitude symmetrically]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 7, 8, 0, 0.25;
    EXEC tSQLt.AssertAlmostEquals 6, 8, 0, 0.25;
    EXEC tSQLt.AssertAlmostEquals 8, 6, 0, 0.25;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 5, 8, 0, 0.25;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 8, 5, 0, 0.25;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test either tolerance is sufficient]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 6, 8, 2, 0.125;
    EXEC tSQLt.AssertAlmostEquals 6, 8, 1, 0.25;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 6, 8, 1, 0.125;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test zero and near zero values]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 0, 0.125, 0.125;
    EXEC tSQLt.AssertAlmostEquals -0.125, 0, 0.125;
    EXEC tSQLt.AssertAlmostEquals 0, 8, 0, 1;
    EXEC tSQLt.AssertAlmostEquals -8, 0, 0, 1;
    EXEC tSQLt.AssertAlmostEquals 0, 1e-300, 1e-300;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 0, 8, 0, 0.5;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 0, 1e-300, 0, 0.5;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test negative values use magnitudes]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals -6, -8, 2;
    EXEC tSQLt.AssertAlmostEquals -6, -8, 0, 0.25;
    EXEC tSQLt.AssertAlmostEquals -8, -6, 0, 0.25;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -6, -8, 1, 0.125;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test opposite signs obey absolute and relative boundaries]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals -2, 6, 8;
    EXEC tSQLt.AssertAlmostEquals 6, -2, 8;
    EXEC tSQLt.AssertAlmostEquals -2, 8, 0, 1.25;
    EXEC tSQLt.AssertAlmostEquals 8, -2, 0, 1.25;
    EXEC tSQLt.AssertAlmostEquals -8, 8, 0, 2;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -2, 6, 7;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -2, 8, 0, 1.125;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -8, 8, 0, 1.5;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test opposite signs cannot pass relative tolerance one]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -1e-300, 1e300, 0, 1;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1e300, -1e-300, 0, 1;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test huge opposite signs do not overflow]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals -1e308, 1e308, 0, 2;
    EXEC tSQLt.AssertAlmostEquals 1e308, -1e308, 0, 1e308;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -1e308, 1e308, 1e308, 0;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -1e308, 1e308, 0, 1.5;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test huge same sign values do not overflow tolerance products]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 1e308, 1.5e308, 0, 2;
    EXEC tSQLt.AssertAlmostEquals -1e308, -1.5e308, 0, 1e308;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1e308, 1.5e308, 0, 0.125;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test tiny values retain relative differences]
AS
BEGIN
    EXEC tSQLt.AssertAlmostEquals 1e-300, 2e-300, 0, 0.5;
    EXEC tSQLt.AssertAlmostEquals -1e-300, 1e-300, 0, 2;
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1e-300, 2e-300, 0, 0.25;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals -1e-300, 1e-300, 0, 1.5;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test normalization preserves close but unequal values]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1.0000000000000002e0, 1e0, 0, 1e-17;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1e0, 1.0000000000000002e0, 0, 1e-17;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test one NULL always fails regardless of tolerance]
AS
BEGIN
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals NULL, 1, 1e308, 1e308;';
    EXEC tSQLt_testutil.assertFailCalled 'EXEC tSQLt.AssertAlmostEquals 1, NULL, 1e308, 1e308;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test negative absolute tolerance errors before equal value shortcut]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedMessage = N'@AbsoluteTolerance must be non-NULL and non-negative.', @ExpectedSeverity = 16;
    EXEC tSQLt.AssertAlmostEquals 1, 1, -1;
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test NULL absolute tolerance errors before NULL shortcut]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedMessage = N'@AbsoluteTolerance must be non-NULL and non-negative.', @ExpectedSeverity = 16;
    EXEC tSQLt.AssertAlmostEquals NULL, NULL, NULL;
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test negative relative tolerance errors before NULL shortcut]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedMessage = N'@RelativeTolerance must be non-NULL and non-negative.', @ExpectedSeverity = 16;
    EXEC tSQLt.AssertAlmostEquals NULL, NULL, 0, -1;
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test NULL relative tolerance errors before equal value shortcut]
AS
BEGIN
    EXEC tSQLt.ExpectException @ExpectedMessage = N'@RelativeTolerance must be non-NULL and non-negative.', @ExpectedSeverity = 16;
    EXEC tSQLt.AssertAlmostEquals 1, 1, 0, NULL;
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test numeric parameter types convert to FLOAT]
AS
BEGIN
    DECLARE @Float FLOAT, @Real REAL, @Integer INT, @Decimal DECIMAL(20,10);
    SELECT @Float = 1.25, @Real = 1.25, @Integer = 1, @Decimal = 1.25;
    EXEC tSQLt.AssertAlmostEquals @Float, @Real;
    EXEC tSQLt.AssertAlmostEquals @Real, @Decimal;
    EXEC tSQLt.AssertAlmostEquals @Integer, @Decimal, 0.25;
    EXEC tSQLt_testutil.assertFailCalled 'DECLARE @R REAL; SET @R = 1.5; EXEC tSQLt.AssertAlmostEquals 1, @R, 0.25;';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test comparison uses FLOAT precision after conversion]
AS
BEGIN
    DECLARE @Expected BIGINT, @Actual BIGINT;
    SELECT @Expected = 9007199254740992, @Actual = 9007199254740993;
    EXEC tSQLt.AssertAlmostEquals @Expected, @Actual;
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test failure message includes values and both tolerances]
AS
BEGIN
    EXEC tSQLt_testutil.AssertFailMessageEquals
        'EXEC tSQLt.AssertAlmostEquals 1, 2, 0.25, 0.125;',
        'Expected: <1.000000000000000e+000> but was: <2.000000000000000e+000> (AbsoluteTolerance: <2.500000000000000e-001>, RelativeTolerance: <1.250000000000000e-001>)';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test failure message represents NULL values]
AS
BEGIN
    EXEC tSQLt_testutil.AssertFailMessageEquals
        'EXEC tSQLt.AssertAlmostEquals NULL, 1;',
        'Expected: <NULL> but was: <1.000000000000000e+000> (AbsoluteTolerance: <0.000000000000000e+000>, RelativeTolerance: <0.000000000000000e+000>)';
    EXEC tSQLt_testutil.AssertFailMessageEquals
        'EXEC tSQLt.AssertAlmostEquals 1, NULL;',
        'Expected: <1.000000000000000e+000> but was: <NULL> (AbsoluteTolerance: <0.000000000000000e+000>, RelativeTolerance: <0.000000000000000e+000>)';
END;
GO

CREATE PROCEDURE AssertAlmostEqualsTests.[test custom message prefixes failure details]
AS
BEGIN
    DECLARE @Details NVARCHAR(MAX), @ExpectedMessage NVARCHAR(MAX);
    SET @Details = N'Expected: <1.000000000000000e+000> but was: <2.000000000000000e+000> (AbsoluteTolerance: <0.000000000000000e+000>, RelativeTolerance: <0.000000000000000e+000>)';
    SET @ExpectedMessage = N'Calculation result ' + @Details;
    EXEC tSQLt_testutil.AssertFailMessageEquals
        'EXEC tSQLt.AssertAlmostEquals 1, 2, @Message = N''Calculation result'';', @ExpectedMessage;
    EXEC tSQLt_testutil.AssertFailMessageEquals
        'EXEC tSQLt.AssertAlmostEquals 1, 2, @Message = N''Calculation result '';', @ExpectedMessage;
    EXEC tSQLt_testutil.AssertFailMessageEquals
        'EXEC tSQLt.AssertAlmostEquals 1, 2, @Message = NULL;', @Details;
END;
GO
