package com.godot.game;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.net.Uri;

import androidx.core.content.FileProvider;

import org.json.JSONObject;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.security.MessageDigest;

/**
 * Die installierte APK weitergeben (scripts/apk_share.gd, Nutzerwunsch 04.10.2026): Kennwerte der installierten APK, SHA-256 und auf
 * Wunsch eine Kopie unter files/share/ in einem eigenen Thread (Abfrage über status()), dazu das Teilen-Menü (ACTION_SEND). Die Kopie
 * ist nötig, weil der FileProvider der Godot-Bibliothek (Kennung &lt;paket&gt;.fileprovider, files-path "/") nur files/ freigibt und
 * GDScript außerhalb des App-Speichers nichts lesen darf. Aufruf aus GDScript per JavaClassWrapper (statische Methoden).
 */
public final class ApkShare {
    private ApkShare() {}

    private static final Object LOCK = new Object();
    private static Thread worker;
    private static volatile boolean cancel;
    private static volatile long done;
    private static volatile long total;
    private static volatile String state = "idle";   // idle | busy | done | error
    private static volatile String sha = "";
    private static volatile String error = "";
    private static volatile String target = "";

    /** JSON {source, size, version, code, stamp, split}; "{}" bei einem Fehler. */
    public static String info(Activity activity) {
        try {
            ApplicationInfo app = activity.getApplicationInfo();
            PackageInfo pkg = activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0);
            File apk = new File(app.sourceDir);
            JSONObject o = new JSONObject();
            o.put("source", app.sourceDir);
            o.put("size", apk.length());
            o.put("version", pkg.versionName);
            // Versionsnummer über Updater.versionCode: getLongVersionCode gibt es erst ab Android 9 (API 28), minSdk ist 24.
            long code = Updater.versionCode(pkg);
            o.put("code", code);
            o.put("stamp", pkg.lastUpdateTime + "-" + apk.length() + "-" + code);
            // Aus mehreren Teil-APKs installiert (App-Bundle): die Basis-APK allein wäre unvollständig – dann nicht weitergeben.
            o.put("split", app.splitSourceDirs != null && app.splitSourceDirs.length > 0);
            return o.toString();
        } catch (Throwable e) {
            return "{}";
        }
    }

    /** Startet SHA-256 der installierten APK (dest leer) bzw. Kopie nach dest samt SHA-256. false = es läuft schon eine Aufgabe. */
    public static boolean start(Activity activity, String dest) {
        synchronized (LOCK) {
            if (worker != null && worker.isAlive()) return false;
            final String source = activity.getApplicationInfo().sourceDir;
            cancel = false;
            done = 0;
            total = new File(source).length();
            sha = "";
            error = "";
            target = dest;
            state = "busy";
            worker = new Thread(() -> run(source, dest), "Draw2Race-ApkShare");
            worker.start();
            return true;
        }
    }

    private static void run(String source, String dest) {
        File part = dest.isEmpty() ? null : new File(dest + ".part");
        try {
            if (part != null) {
                File dir = part.getParentFile();
                if (dir != null && !dir.isDirectory() && !dir.mkdirs()) throw new Exception("Ordner nicht anlegbar");
            }
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] buffer = new byte[1 << 20];
            try (InputStream in = new FileInputStream(source); OutputStream out = part == null ? null : new FileOutputStream(part)) {
                int n;
                while ((n = in.read(buffer)) > 0) {
                    if (cancel) throw new Exception("abgebrochen");
                    digest.update(buffer, 0, n);
                    if (out != null) out.write(buffer, 0, n);
                    done += n;
                }
            }
            if (part != null) {
                File file = new File(dest);
                if (file.exists() && !file.delete()) throw new Exception("alte Kopie nicht löschbar");
                if (!part.renameTo(file)) throw new Exception("Umbenennen fehlgeschlagen");
            }
            StringBuilder hex = new StringBuilder();
            for (byte b : digest.digest()) hex.append(String.format("%02x", b));
            sha = hex.toString();
            state = "done";
        } catch (Throwable e) {   // auch Errors: Ein ungefangener Fehler in diesem eigenen Thread beendet sonst die App
            if (part != null) part.delete();
            error = e.getMessage() == null ? e.toString() : e.getMessage();
            state = "error";
        }
    }

    /** JSON {state, done, total, sha256, path, error}. */
    public static String status() {
        try {
            JSONObject o = new JSONObject();
            o.put("state", state);
            o.put("done", done);
            o.put("total", total);
            o.put("sha256", sha);
            o.put("path", target);
            o.put("error", error);
            return o.toString();
        } catch (Exception e) {
            return "{}";
        }
    }

    public static void cancel() {
        cancel = true;
    }

    /** Teilen-Menü mit der Datei (Quick Share, Bluetooth, Messenger …). Leerer Text = geöffnet, sonst Fehlerbeschreibung. */
    public static String share(Activity activity, String path, String subject, String title) {
        try {
            Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", new File(path));
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType("application/vnd.android.package-archive");
            send.putExtra(Intent.EXTRA_STREAM, uri);
            send.putExtra(Intent.EXTRA_SUBJECT, subject);
            send.setClipData(ClipData.newRawUri(subject, uri));
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            Intent chooser = Intent.createChooser(send, title);
            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            activity.runOnUiThread(() -> {
                try {
                    activity.startActivity(chooser);
                } catch (Exception ignored) {
                }
            });
            return "";
        } catch (Exception e) {
            return "Teilen nicht möglich: " + e.getMessage();
        }
    }
}
