/*
  ============================================================
  PATRATU FINGERPRINT PROJECT - DATABASE SETUP FROM SCRATCH
  ============================================================
  Run this script in SSMS connected to: devsql (localhost)
  Login: sa / T@123

  This creates:
    1. IDSL_NTPC_CLIMS   (main application database)
    2. BIO_DATA_NTPC_CLIMS (biometric data database)
    3. Synonyms in IDSL_NTPC_CLIMS so app can see BIO_ tables

  Run order: Execute whole file at once (F5 in SSMS)
  ============================================================
*/

SET NOCOUNT ON;
PRINT 'Starting database setup...';
PRINT 'Time: ' + CONVERT(VARCHAR(19), GETDATE(), 120);
GO

-- ============================================================
-- STEP 1: Create IDSL_NTPC_CLIMS database
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'IDSL_NTPC_CLIMS')
BEGIN
    CREATE DATABASE [IDSL_NTPC_CLIMS];
    PRINT 'Database IDSL_NTPC_CLIMS created.';
END
ELSE
    PRINT 'Database IDSL_NTPC_CLIMS already exists.';
GO

-- ============================================================
-- STEP 2: Create BIO_DATA_NTPC_CLIMS database
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'BIO_DATA_NTPC_CLIMS')
BEGIN
    CREATE DATABASE [BIO_DATA_NTPC_CLIMS];
    PRINT 'Database BIO_DATA_NTPC_CLIMS created.';
END
ELSE
    PRINT 'Database BIO_DATA_NTPC_CLIMS already exists.';
GO

-- ============================================================
-- STEP 3: Create tables in IDSL_NTPC_CLIMS
-- ============================================================
USE [IDSL_NTPC_CLIMS];
GO

-- Table: DEVICEINFO
-- Stores fingerprint device registration info and parameters
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DEVICEINFO') AND type = 'U')
BEGIN
    CREATE TABLE dbo.DEVICEINFO (
        DI_ID       INT            NOT NULL IDENTITY(1,1),
        SLNO        VARCHAR(50)    NULL,
        DI_PARAM    VARCHAR(100)   NULL,
        DI_VALUE    VARCHAR(255)   NULL,
        DI_MANUAL   INT            NULL DEFAULT 0,
        CONSTRAINT PK_DEVICEINFO PRIMARY KEY (DI_ID)
    );
    PRINT 'Table DEVICEINFO created.';
END
ELSE
    PRINT 'Table DEVICEINFO already exists.';
GO

-- Table: DEVICECMD
-- Stores commands sent to fingerprint devices
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.DEVICECMD') AND type = 'U')
BEGIN
    CREATE TABLE dbo.DEVICECMD (
        DC_ID           INT            NOT NULL IDENTITY(1,1),
        SLNO            VARCHAR(50)    NULL,
        DC_CMD          NVARCHAR(MAX)  NULL,
        DC_DATE         DATETIME       NULL DEFAULT GETDATE(),
        DC_EXECDATE     DATETIME       NULL,
        DC_RES          VARCHAR(10)    NULL DEFAULT '0',
        DC_RESDATE      DATETIME       NULL,
        CMD_DESC        VARCHAR(255)   NULL,
        REF_ID          INT            NULL DEFAULT 0,
        src_sno         VARCHAR(50)    NULL,
        DC_cmd_date     DATETIME       NULL DEFAULT GETDATE(),
        IS_DEL_EXECUTED INT            NULL DEFAULT 0,
        CONSTRAINT PK_DEVICECMD PRIMARY KEY (DC_ID)
    );
    PRINT 'Table DEVICECMD created.';
END
ELSE
    PRINT 'Table DEVICECMD already exists.';
GO

-- Index for DEVICECMD (performance - deadlock mitigation)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DEVICECMD_QUEUE_LOOKUP' AND object_id = OBJECT_ID('dbo.DEVICECMD'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DEVICECMD_QUEUE_LOOKUP
    ON dbo.DEVICECMD (SLNO, IS_DEL_EXECUTED, DC_RES, CMD_DESC, REF_ID, DC_ID)
    INCLUDE (DC_EXECDATE, DC_DATE, DC_cmd_date);
    PRINT 'Index IX_DEVICECMD_QUEUE_LOOKUP created.';
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_DEVICECMD_RETENTION_SCAN' AND object_id = OBJECT_ID('dbo.DEVICECMD'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_DEVICECMD_RETENTION_SCAN
    ON dbo.DEVICECMD (IS_DEL_EXECUTED, DC_RES, DC_RESDATE, DC_cmd_date, DC_DATE)
    INCLUDE (DC_ID, CMD_DESC, SLNO);
    PRINT 'Index IX_DEVICECMD_RETENTION_SCAN created.';
END
GO

-- Table: NetWork
-- Stores device network/location mapping
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.NetWork') AND type = 'U')
BEGIN
    CREATE TABLE dbo.NetWork (
        ID              INT            NOT NULL IDENTITY(1,1),
        SLNO            VARCHAR(50)    NULL,
        GATE            VARCHAR(10)    NULL,
        NET_AREA        VARCHAR(100)   NULL,
        location_name   VARCHAR(100)   NULL,
        ONLINE          BIT            NULL DEFAULT 1,
        ISDELETED       BIT            NULL DEFAULT 0,
        DeviceName      VARCHAR(20)    NULL,
        Status_Upd_on   DATETIME       NULL DEFAULT GETDATE(),
        CONSTRAINT PK_NetWork PRIMARY KEY (ID)
    );
    PRINT 'Table NetWork created.';
END
ELSE
    PRINT 'Table NetWork already exists.';
GO

-- Table: CLIMSLOG (base table for CLIMSVIEW)
-- Stores CLIMS attendance log records
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.CLIMSLOG') AND type = 'U')
BEGIN
    CREATE TABLE dbo.CLIMSLOG (
        DEVICELOGID     BIGINT         NOT NULL IDENTITY(1,1),
        DOWNLOADDATE    DATETIME       NULL DEFAULT GETDATE(),
        PROJECTID       VARCHAR(50)    NULL,
        USERID          VARCHAR(20)    NULL,
        LOGDATE         DATETIME       NULL,
        DIRECTION       VARCHAR(10)    NULL,
        DEVICEID        VARCHAR(20)    NULL,
        CONSTRAINT PK_CLIMSLOG PRIMARY KEY (DEVICELOGID)
    );
    PRINT 'Table CLIMSLOG created.';
END
ELSE
    PRINT 'Table CLIMSLOG already exists.';
GO

-- View: CLIMSVIEW (used by ClimsViewMapper)
IF OBJECT_ID(N'dbo.CLIMSVIEW', 'V') IS NOT NULL
    DROP VIEW dbo.CLIMSVIEW;
GO

CREATE VIEW dbo.CLIMSVIEW AS
SELECT
    DEVICELOGID,
    DOWNLOADDATE,
    PROJECTID,
    USERID,
    LOGDATE,
    DIRECTION,
    DEVICEID
FROM dbo.CLIMSLOG;
GO

PRINT 'View CLIMSVIEW created.';
GO

-- Stored procedure: DEVICECMD retention cleanup
IF OBJECT_ID('dbo.usp_devicecmd_retention_cleanup', 'P') IS NOT NULL
    DROP PROCEDURE dbo.usp_devicecmd_retention_cleanup;
GO

CREATE PROCEDURE dbo.usp_devicecmd_retention_cleanup
    @RetentionDays INT = 14,
    @BatchSize     INT = 2000,
    @MaxLoops      INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @loop INT = 0, @deleted INT = 1, @totalDeleted INT = 0;

    IF @RetentionDays < 1 SET @RetentionDays = 1;
    IF @BatchSize < 100    SET @BatchSize = 100;
    IF @MaxLoops < 1       SET @MaxLoops = 1;

    WHILE (@loop < @MaxLoops AND @deleted > 0)
    BEGIN
        SET @loop += 1;
        DELETE TOP (@BatchSize) FROM dbo.DEVICECMD
        WHERE ISNULL(CONVERT(INT, IS_DEL_EXECUTED), 0) = 1
          AND ISNULL(CASE WHEN ISNUMERIC(DC_RES) = 1 THEN CONVERT(INT, DC_RES) ELSE NULL END, 0) IN (1, 2)
          AND ISNULL(DC_RESDATE, ISNULL(DC_cmd_date, DC_DATE)) < DATEADD(DAY, -@RetentionDays, GETDATE());
        SET @deleted = @@ROWCOUNT;
        SET @totalDeleted += @deleted;
    END
    PRINT '[usp_devicecmd_retention_cleanup] deleted = ' + CAST(@totalDeleted AS VARCHAR(20));
END
GO
PRINT 'Stored procedure usp_devicecmd_retention_cleanup created.';
GO

-- ============================================================
-- STEP 4: Create tables in BIO_DATA_NTPC_CLIMS
-- ============================================================
USE [BIO_DATA_NTPC_CLIMS];
GO

-- Table: BIO_USERMAST
-- Master table of biometric enrolled users
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.BIO_USERMAST') AND type = 'U')
BEGIN
    CREATE TABLE dbo.BIO_USERMAST (
        BU_ID       INT             NOT NULL IDENTITY(1,1),
        TR_DATE     DATETIME        NULL DEFAULT GETDATE(),
        SLNO        VARCHAR(50)     NULL,
        ID          VARCHAR(20)     NULL,
        NAME        VARCHAR(100)    NULL,
        PRI         VARCHAR(10)     NULL DEFAULT '0',
        PASSWD      VARCHAR(10)     NULL DEFAULT '',
        CARDNO      VARCHAR(20)     NULL DEFAULT '',
        GRPNO       VARCHAR(10)     NULL DEFAULT '1',
        TZ          VARCHAR(20)     NULL DEFAULT '0000000100000000',
        ISDELETED   INT             NULL DEFAULT 0,
        DEL_DATE    DATETIME        NULL,
        UPD_DATE    DATETIME        NULL DEFAULT GETDATE(),
        Verify      VARCHAR(5)      NULL DEFAULT '-1',
        CONSTRAINT PK_BIO_USERMAST PRIMARY KEY (BU_ID)
    );
    CREATE INDEX IX_BIO_USERMAST_ID ON dbo.BIO_USERMAST (ID);
    PRINT 'Table BIO_USERMAST created.';
END
ELSE
    PRINT 'Table BIO_USERMAST already exists.';
GO

-- Table: BIO_FACEDATA
-- Stores face/fingerprint template data
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.BIO_FACEDATA') AND type = 'U')
BEGIN
    CREATE TABLE dbo.BIO_FACEDATA (
        BP_ID       INT             NOT NULL IDENTITY(1,1),
        BP_DATE     DATETIME        NULL DEFAULT GETDATE(),
        SLNO        VARCHAR(50)     NULL,
        ID          VARCHAR(20)     NULL,
        FINDEX      VARCHAR(5)      NULL,
        FPSIZE      INT             NULL DEFAULT 0,
        FPVALID     VARCHAR(5)      NULL DEFAULT '1',
        FPTMP       NVARCHAR(MAX)   NULL,
        UPD_DATE    DATETIME        NULL DEFAULT GETDATE(),
        CONSTRAINT PK_BIO_FACEDATA PRIMARY KEY (BP_ID)
    );
    CREATE INDEX IX_BIO_FACEDATA_ID ON dbo.BIO_FACEDATA (ID);
    PRINT 'Table BIO_FACEDATA created.';
END
ELSE
    PRINT 'Table BIO_FACEDATA already exists.';
GO

-- Table: BIO_PICDATA
-- Stores photo/image data per user
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'dbo.BIO_PICDATA') AND type = 'U')
BEGIN
    CREATE TABLE dbo.BIO_PICDATA (
        BP_ID       INT             NOT NULL IDENTITY(1,1),
        BP_DATE     DATETIME        NULL DEFAULT GETDATE(),
        SLNO        VARCHAR(50)     NULL,
        ID          VARCHAR(20)     NULL,
        SIZE        INT             NULL DEFAULT 0,
        IMAGE       NVARCHAR(MAX)   NULL,
        UPD_DATE    DATETIME        NULL DEFAULT GETDATE(),
        CONSTRAINT PK_BIO_PICDATA PRIMARY KEY (BP_ID)
    );
    CREATE INDEX BIOPICIX1 ON dbo.BIO_PICDATA (ID);
    PRINT 'Table BIO_PICDATA created.';
END
ELSE
    PRINT 'Table BIO_PICDATA already exists.';
GO

-- ============================================================
-- STEP 5: Create synonyms in IDSL_NTPC_CLIMS for BIO_ tables
-- (So the Java app connecting to IDSL_NTPC_CLIMS can see BIO_ tables)
-- ============================================================
USE [IDSL_NTPC_CLIMS];
GO

IF OBJECT_ID(N'dbo.BIO_USERMAST', 'SN') IS NULL
BEGIN
    CREATE SYNONYM dbo.BIO_USERMAST FOR [BIO_DATA_NTPC_CLIMS].[dbo].[BIO_USERMAST];
    PRINT 'Synonym BIO_USERMAST created.';
END
ELSE
    PRINT 'Synonym BIO_USERMAST already exists.';
GO

IF OBJECT_ID(N'dbo.BIO_FACEDATA', 'SN') IS NULL
BEGIN
    CREATE SYNONYM dbo.BIO_FACEDATA FOR [BIO_DATA_NTPC_CLIMS].[dbo].[BIO_FACEDATA];
    PRINT 'Synonym BIO_FACEDATA created.';
END
ELSE
    PRINT 'Synonym BIO_FACEDATA already exists.';
GO

IF OBJECT_ID(N'dbo.BIO_PICDATA', 'SN') IS NULL
BEGIN
    CREATE SYNONYM dbo.BIO_PICDATA FOR [BIO_DATA_NTPC_CLIMS].[dbo].[BIO_PICDATA];
    PRINT 'Synonym BIO_PICDATA created.';
END
ELSE
    PRINT 'Synonym BIO_PICDATA already exists.';
GO

-- ============================================================
-- STEP 6: Create SQL login 'sa' with correct password (if not set)
-- ============================================================
USE [master];
GO

-- Enable mixed-mode auth (SQL + Windows) - needed for 'sa' login
-- Note: This requires a SQL Server restart to fully take effect
-- if it was previously Windows-only auth.
EXEC xp_instance_regwrite
    N'HKEY_LOCAL_MACHINE',
    N'Software\Microsoft\MSSQLServer\MSSQLServer',
    N'LoginMode',
    REG_DWORD,
    2;
GO

-- Enable and set password for 'sa' login
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'sa')
BEGIN
    ALTER LOGIN [sa] ENABLE;
    ALTER LOGIN [sa] WITH PASSWORD = N'T@123', CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;
    PRINT 'sa login enabled with password T@123';
END
GO

-- Grant sa access to both databases
USE [IDSL_NTPC_CLIMS];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'sa')
    CREATE USER [sa] FOR LOGIN [sa];
EXEC sp_addrolemember N'db_owner', N'sa';
GO

USE [BIO_DATA_NTPC_CLIMS];
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'sa')
    CREATE USER [sa] FOR LOGIN [sa];
EXEC sp_addrolemember N'db_owner', N'sa';
GO

PRINT '============================================================';
PRINT 'Setup COMPLETE!';
PRINT '';
PRINT 'Databases created:';
PRINT '  - IDSL_NTPC_CLIMS   (main app database)';
PRINT '  - BIO_DATA_NTPC_CLIMS (bio data database)';
PRINT '';
PRINT 'Connection string for jdbc.properties:';
PRINT '  jdbc:sqlserver://localhost:1433;databaseName=IDSL_NTPC_CLIMS;encrypt=true;trustServerCertificate=true';
PRINT '  username=sa   password=T@123';
PRINT '';
PRINT 'IMPORTANT: Restart SQL Server service after this script';
PRINT '  so mixed-mode authentication (sa login) takes effect.';
PRINT '============================================================';
GO
