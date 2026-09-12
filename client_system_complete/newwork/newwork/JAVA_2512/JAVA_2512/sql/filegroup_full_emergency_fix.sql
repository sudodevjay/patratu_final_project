/*
  FILEGROUP FULL emergency fix (SQL Server)
  =========================================
  Target DB example: BIO_DATA_NTPC_CLIMS

  Use this when you see:
    - error 1105 (PRIMARY filegroup full)
    - BIO_PICDATA / DEVICECMD write failures

  This script does NOT create any SQL Agent scheduler/job.
*/

SET NOCOUNT ON;

PRINT 'Database: ' + DB_NAME();
PRINT 'Start : ' + CONVERT(VARCHAR(19), GETDATE(), 120);

/* A) Visibility: file + filegroup usage */
SELECT
    DB_NAME() AS database_name,
    df.name AS logical_file_name,
    df.type_desc,
    CAST(df.size / 128.0 AS DECIMAL(18,2)) AS size_mb,
    CASE WHEN df.max_size = -1 THEN 'UNLIMITED'
         ELSE CAST(CAST(df.max_size / 128.0 AS DECIMAL(18,2)) AS VARCHAR(40)) END AS max_size_mb,
    CASE WHEN df.is_percent_growth = 1 THEN CAST(df.growth AS VARCHAR(20)) + ' %'
         ELSE CAST(CAST(df.growth / 128.0 AS DECIMAL(18,2)) AS VARCHAR(40)) + ' MB' END AS growth,
    fg.name AS filegroup_name,
    df.physical_name
FROM sys.database_files df
LEFT JOIN sys.filegroups fg
    ON df.data_space_id = fg.data_space_id
ORDER BY df.type_desc, df.file_id;

SELECT
    fg.name AS filegroup_name,
    CAST(SUM(df.size) / 128.0 AS DECIMAL(18,2)) AS allocated_mb,
    CAST(SUM(FILEPROPERTY(df.name, 'SpaceUsed')) / 128.0 AS DECIMAL(18,2)) AS used_mb,
    CAST((SUM(df.size) - SUM(FILEPROPERTY(df.name, 'SpaceUsed'))) / 128.0 AS DECIMAL(18,2)) AS free_mb
FROM sys.filegroups fg
JOIN sys.database_files df
    ON df.data_space_id = fg.data_space_id
GROUP BY fg.name
ORDER BY fg.name;

/* B) Ensure PRIMARY files can grow */
DECLARE @growSql NVARCHAR(MAX) = N'';
SELECT @growSql = @growSql +
    N'ALTER DATABASE [' + DB_NAME() + N'] MODIFY FILE (NAME = N''' + df.name
    + N''', FILEGROWTH = 512MB, MAXSIZE = UNLIMITED);' + CHAR(10)
FROM sys.database_files df
WHERE df.type_desc = 'ROWS'
  AND df.data_space_id IN (SELECT data_space_id FROM sys.filegroups WHERE name = 'PRIMARY');

IF LEN(@growSql) > 0
BEGIN
    PRINT 'Applying autogrowth on PRIMARY row files...';
    EXEC sp_executesql @growSql;
END

/* C) Remove duplicate pending setuserinfo rows (new queue logic writes src_sno key) */
DECLARE @dupDeleted INT = 0;
;WITH dup AS (
    SELECT
        DC_ID,
        ROW_NUMBER() OVER (
            PARTITION BY SLNO, CMD_DESC, ISNULL(src_sno, '')
            ORDER BY DC_ID DESC
        ) AS rn
    FROM DEVICECMD
    WHERE CMD_DESC = 'JAVA:setuserinfo'
      AND ISNULL(src_sno, '') <> ''
      AND ISNULL(CASE WHEN ISNUMERIC(DC_RES)=1 THEN CONVERT(INT, DC_RES) ELSE NULL END, 0) = 0
      AND ISNULL(CONVERT(INT, IS_DEL_EXECUTED), 0) = 0
)
DELETE FROM dup
WHERE rn > 1;
SET @dupDeleted = @@ROWCOUNT;
PRINT 'Duplicate pending setuserinfo removed: ' + CAST(@dupDeleted AS VARCHAR(20));

/* D) Retention cleanup: completed DEVICECMD rows (manual, no scheduler/job) */
DECLARE @RetentionDays INT = 14;
DECLARE @BatchSize INT = 5000;
DECLARE @deleted INT = 1;
DECLARE @totalDeleted INT = 0;

WHILE (@deleted > 0)
BEGIN
    DELETE TOP (@BatchSize)
    FROM DEVICECMD
    WHERE ISNULL(CONVERT(INT, IS_DEL_EXECUTED), 0) = 1
      AND ISNULL(CASE WHEN ISNUMERIC(DC_RES)=1 THEN CONVERT(INT, DC_RES) ELSE NULL END, 0) IN (1, 2)
      AND ISNULL(DC_RESDATE, ISNULL(DC_cmd_date, DC_DATE)) < DATEADD(DAY, -@RetentionDays, GETDATE());

    SET @deleted = @@ROWCOUNT;
    SET @totalDeleted = @totalDeleted + @deleted;
END

PRINT 'Completed DEVICECMD rows removed: ' + CAST(@totalDeleted AS VARCHAR(20));

/* E) Table size snapshot */
EXEC sp_spaceused 'dbo.DEVICECMD';
EXEC sp_spaceused 'dbo.BIO_PICDATA';

PRINT 'End   : ' + CONVERT(VARCHAR(19), GETDATE(), 120);
PRINT 'Done.';
