/*
  DEVICECMD deadlock mitigation (SQL Server)
  Run once on the application database.
*/

SET NOCOUNT ON;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_DEVICECMD_QUEUE_LOOKUP'
      AND object_id = OBJECT_ID('dbo.DEVICECMD')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_DEVICECMD_QUEUE_LOOKUP
    ON dbo.DEVICECMD (
        SLNO,
        IS_DEL_EXECUTED,
        DC_RES,
        CMD_DESC,
        REF_ID,
        DC_ID
    )
    INCLUDE (
        DC_EXECDATE,
        DC_DATE,
        DC_cmd_date
    );
END
GO

