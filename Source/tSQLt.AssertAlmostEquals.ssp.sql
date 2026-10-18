IF OBJECT_ID('tSQLt.AssertAlmostEquals') IS NOT NULL DROP PROCEDURE tSQLt.AssertAlmostEquals;
GO
---Build+
CREATE PROCEDURE tSQLt.AssertAlmostEquals
    @Expected FLOAT,
    @Actual FLOAT,
    @AbsoluteTolerance FLOAT = 0,
    @RelativeTolerance FLOAT = 0,
    @Message NVARCHAR(MAX) = N''
AS
BEGIN
    IF @AbsoluteTolerance IS NULL OR @AbsoluteTolerance < 0
    BEGIN
        RAISERROR('@AbsoluteTolerance must be non-NULL and non-negative.', 16, 10);
        RETURN;
    END;
    IF @RelativeTolerance IS NULL OR @RelativeTolerance < 0
    BEGIN
        RAISERROR('@RelativeTolerance must be non-NULL and non-negative.', 16, 10);
        RETURN;
    END;

    IF @Expected = @Actual OR (@Expected IS NULL AND @Actual IS NULL)
        RETURN 0;

    IF @Expected IS NOT NULL AND @Actual IS NOT NULL
    BEGIN
        DECLARE @Scale FLOAT, @Smaller FLOAT, @Difference FLOAT;
        SELECT @Scale = CASE WHEN ABS(@Expected) > ABS(@Actual) THEN ABS(@Expected) ELSE ABS(@Actual) END,
               @Smaller = CASE WHEN ABS(@Expected) > ABS(@Actual) THEN ABS(@Actual) ELSE ABS(@Expected) END;

        IF (@Expected >= 0 AND @Actual >= 0) OR (@Expected <= 0 AND @Actual <= 0)
        BEGIN
            -- Same-sign subtraction cannot overflow. Divide the difference,
            -- rather than the operands, to preserve close, distinct values.
            SET @Difference = ABS(@Expected - @Actual);
            IF @Difference <= @AbsoluteTolerance
                RETURN 0;
            IF @RelativeTolerance > 0
            BEGIN
                IF @Difference / @Scale <= @RelativeTolerance
                    RETURN 0;
            END;
        END
        ELSE
        BEGIN
            -- Opposite-sign magnitudes may overflow when added. Compare the
            -- smaller magnitude with the remaining absolute allowance instead.
            IF @Scale <= @AbsoluteTolerance
            BEGIN
                IF @Smaller <= @AbsoluteTolerance - @Scale
                    RETURN 0;
            END;
            -- Relative distance is 1 + smaller/scale, in [1,2]. Subtract 1
            -- from the tolerance to avoid rounding a small ratio away.
            IF @RelativeTolerance >= 2
                RETURN 0;
            IF @RelativeTolerance > 1
            BEGIN
                IF @Smaller / @Scale <= @RelativeTolerance - 1
                    RETURN 0;
            END;
        END;
    END;

    DECLARE @Msg NVARCHAR(MAX);
    SELECT @Msg = N'Expected: <' + ISNULL(CONVERT(NVARCHAR(30), @Expected, 2), N'NULL') +
                  N'> but was: <' + ISNULL(CONVERT(NVARCHAR(30), @Actual, 2), N'NULL') +
                  N'> (AbsoluteTolerance: <' + CONVERT(NVARCHAR(30), @AbsoluteTolerance, 2) +
                  N'>, RelativeTolerance: <' + CONVERT(NVARCHAR(30), @RelativeTolerance, 2) + N'>)';
    SET @Message = COALESCE(@Message, N'');
    IF @Message <> N'' AND @Message NOT LIKE N'% ' SET @Message = @Message + N' ';
    EXEC tSQLt.Fail @Message, @Msg;
END;
---Build-
GO
