package com.timmy.deploy;

import java.awt.Desktop;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileVisitResult;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.SimpleFileVisitor;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import java.nio.file.attribute.BasicFileAttributes;
import java.nio.file.attribute.FileTime;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;

public final class ClientLauncher {

    private static final String START_SCRIPT = "start-tomcat.cmd";
    private static final String STOP_SCRIPT = "stop-tomcat.cmd";
    private static final String SOURCE_WAR = "demo.war";
    private static final String TARGET_CONTEXT_WAR = "demo.war";
    private static final String TARGET_CONTEXT_DIR = "demo";
    private static final String APP_URL = "http://localhost:8080/demo/";
    private static final int HTTP_PORT = 8080;
    private static final int SHUTDOWN_PORT = 18005;
    private static final String LOG_DIR = "logs";
    private static final String LAUNCHER_LOG = "launcher.log";
    private static final String START_LOG_HINT = "logs\\start-tomcat.log";
    private static final String CATALINA_LOG_HINT = "tomcat\\logs\\catalina*.log";
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private ClientLauncher() {
    }

    public static void main(String[] args) {
        Path launcherLog = null;
        try {
            Path appDir = resolveAppDir();
            Path logsDir = appDir.resolve(LOG_DIR);
            Files.createDirectories(logsDir);
            launcherLog = logsDir.resolve(LAUNCHER_LOG);
            log(launcherLog, "Launcher started. args=" + Arrays.toString(args));

            if (hasArg(args, "--stop")) {
                int stopExit = runScript(appDir, STOP_SCRIPT, launcherLog);
                log(launcherLog, "Stop script exit code: " + stopExit);
                System.out.println("Stop command sent.");
                return;
            }

            deployWarIfNeeded(appDir, launcherLog);
            int startExit = runScript(appDir, START_SCRIPT, launcherLog);
            log(launcherLog, "Start script exit code: " + startExit);
            if (startExit != 0) {
                throw new IOException("Tomcat start script failed. Exit code: " + startExit);
            }

            boolean shutdownReady = waitForPort("127.0.0.1", SHUTDOWN_PORT, 45);
            if (!shutdownReady) {
                throw new IOException("Tomcat did not open shutdown port " + SHUTDOWN_PORT + ". Check " + START_LOG_HINT + " and " + CATALINA_LOG_HINT);
            }

            boolean httpReady = waitForPort("127.0.0.1", HTTP_PORT, 30);
            if (!httpReady) {
                log(launcherLog, "Warning: HTTP port " + HTTP_PORT + " not ready yet.");
            }

            if (!hasArg(args, "--no-browser")) {
                Thread.sleep(5000L);
                openBrowser(APP_URL);
            }

            log(launcherLog, "Startup successful. URL=" + APP_URL);
            System.out.println("Fingerprint client server start command sent.");
            System.out.println("Open: " + APP_URL);
        } catch (Exception ex) {
            if (launcherLog != null) {
                try {
                    log(launcherLog, "Startup failed: " + ex.toString());
                } catch (IOException ignore) {
                    // Keep original failure.
                }
            }
            System.err.println("Failed to start client package: " + ex.getMessage());
            System.err.println("Check logs: app\\logs\\launcher.log, app\\logs\\start-tomcat.log, app\\tomcat\\logs\\catalina*.log");
            ex.printStackTrace(System.err);
            System.exit(1);
        }
    }

    private static boolean hasArg(String[] args, String value) {
        return Arrays.stream(args).anyMatch(value::equalsIgnoreCase);
    }

    private static Path resolveAppDir() throws URISyntaxException {
        URI location = ClientLauncher.class.getProtectionDomain().getCodeSource().getLocation().toURI();
        Path codeSourcePath = Paths.get(location).toAbsolutePath().normalize();
        return Files.isDirectory(codeSourcePath) ? codeSourcePath : codeSourcePath.getParent();
    }

    private static void deployWarIfNeeded(Path appDir, Path launcherLog) throws IOException {
        Path sourceWar = appDir.resolve(SOURCE_WAR);
        Path webappsDir = appDir.resolve("tomcat").resolve("webapps");
        Path targetWar = webappsDir.resolve(TARGET_CONTEXT_WAR);
        Path explodedDir = webappsDir.resolve(TARGET_CONTEXT_DIR);

        if (!Files.exists(sourceWar)) {
            throw new IOException("Missing source WAR: " + sourceWar);
        }

        Files.createDirectories(webappsDir);
        if (shouldCopyWar(sourceWar, targetWar)) {
            log(launcherLog, "WAR sync: copying " + sourceWar + " -> " + targetWar);
            Files.copy(sourceWar, targetWar, StandardCopyOption.REPLACE_EXISTING);
            deleteDirectory(explodedDir);
            log(launcherLog, "WAR sync complete.");
        } else {
            log(launcherLog, "WAR sync skipped (already up to date).");
        }
    }

    private static boolean shouldCopyWar(Path sourceWar, Path targetWar) throws IOException {
        if (!Files.exists(targetWar)) {
            return true;
        }
        long sourceSize = Files.size(sourceWar);
        long targetSize = Files.size(targetWar);
        if (sourceSize != targetSize) {
            return true;
        }
        FileTime sourceTime = Files.getLastModifiedTime(sourceWar);
        FileTime targetTime = Files.getLastModifiedTime(targetWar);
        return sourceTime.compareTo(targetTime) > 0;
    }

    private static void deleteDirectory(Path dir) throws IOException {
        if (!Files.exists(dir)) {
            return;
        }
        Files.walkFileTree(dir, new SimpleFileVisitor<Path>() {
            @Override
            public FileVisitResult visitFile(Path file, BasicFileAttributes attrs) throws IOException {
                Files.deleteIfExists(file);
                return FileVisitResult.CONTINUE;
            }

            @Override
            public FileVisitResult postVisitDirectory(Path directory, IOException exc) throws IOException {
                Files.deleteIfExists(directory);
                return FileVisitResult.CONTINUE;
            }
        });
    }

    private static int runScript(Path appDir, String scriptName, Path launcherLog) throws IOException, InterruptedException {
        Path scriptPath = appDir.resolve(scriptName);
        if (!Files.exists(scriptPath)) {
            throw new IOException("Missing script: " + scriptPath);
        }

        Path logsDir = appDir.resolve(LOG_DIR);
        Files.createDirectories(logsDir);
        Path processLog = logsDir.resolve(scriptName + ".launcher-output.log");

        ProcessBuilder builder = new ProcessBuilder("cmd.exe", "/c", scriptPath.toAbsolutePath().toString());
        builder.directory(appDir.toFile());
        builder.redirectErrorStream(true);
        builder.redirectOutput(ProcessBuilder.Redirect.appendTo(processLog.toFile()));
        log(launcherLog, "Executing script: " + scriptPath);

        Process process = builder.start();
        int exitCode = process.waitFor();
        log(launcherLog, "Script completed: " + scriptName + " exitCode=" + exitCode);
        return exitCode;
    }

    private static boolean waitForPort(String host, int port, int timeoutSeconds) {
        long deadline = System.currentTimeMillis() + timeoutSeconds * 1000L;
        while (System.currentTimeMillis() < deadline) {
            if (canConnect(host, port, 1000)) {
                return true;
            }
            try {
                Thread.sleep(1000L);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return false;
            }
        }
        return false;
    }

    private static boolean canConnect(String host, int port, int timeoutMillis) {
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(host, port), timeoutMillis);
            return true;
        } catch (IOException ignore) {
            return false;
        }
    }

    private static void log(Path logFile, String message) throws IOException {
        String line = "[" + TS.format(LocalDateTime.now()) + "] " + message + System.lineSeparator();
        Files.write(logFile, line.getBytes(StandardCharsets.UTF_8),
                StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }

    private static void openBrowser(String url) {
        try {
            if (!Desktop.isDesktopSupported()) {
                return;
            }
            Desktop.getDesktop().browse(URI.create(url));
        } catch (Exception ignore) {
            // Browser opening failure should not block server startup.
        }
    }
}
