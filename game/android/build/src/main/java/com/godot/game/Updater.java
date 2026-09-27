package com.godot.game;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import java.io.File;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/**
 * Android-Teil der Update-Funktion . Download und SHA-256-Prüfung erledigt
 * scripts/updater.gd; hier: Installationsberechtigung, Signatur-/Versionsprüfung der geladenen APK und Start des
 * System-Installers über den FileProvider der Godot-Bibliothek (Kennung <paket>.fileprovider, gibt files/ frei). Aufruf aus GDScript per JavaClassWrapper (statische Methoden).
 */
public final class Updater {
    private Updater() {}

    public static boolean canInstall(Activity activity) {
        return activity.getPackageManager().canRequestPackageInstalls();
    }

    public static void openInstallPermission(Activity activity) {
        activity.runOnUiThread(() -> {
            try {
                activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + activity.getPackageName())));
            } catch (Exception ignored) {
            }
        });
    }

    public static String installedVersion(Activity activity) {
        try {
            return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "";
        }
    }

    /** Leerer Text = in Ordnung, sonst Fehlerbeschreibung. */
    @SuppressWarnings("deprecation")
    public static String verify(Activity activity, String path, String version) {
        try {
            PackageManager pm = activity.getPackageManager();
            PackageInfo installed = pm.getPackageInfo(activity.getPackageName(), PackageManager.GET_SIGNING_CERTIFICATES);
            PackageInfo candidate = pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES);
            if (candidate == null) return "APK nicht lesbar";
            if (!activity.getPackageName().equals(candidate.packageName)) return "Falsches Paket";
            if (candidate.getLongVersionCode() <= installed.getLongVersionCode()) return "Keine neuere Version";
            if (!version.equals(candidate.versionName)) return "Versionsangabe passt nicht";
            Set<Signature> current = new HashSet<>(Arrays.asList(installed.signingInfo.getApkContentsSigners()));
            Set<Signature> incoming = new HashSet<>(Arrays.asList(candidate.signingInfo.getApkContentsSigners()));
            if (current.isEmpty() || !current.equals(incoming)) return "Signatur passt nicht";
            return "";
        } catch (Exception e) {
            return "Prüfung fehlgeschlagen: " + e.getMessage();
        }
    }

    public static String install(Activity activity, String path) {
        try {
            File file = new File(path);
            Uri uri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".fileprovider", file);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "application/vnd.android.package-archive");
            intent.setClipData(ClipData.newRawUri("Draw2Race-Update", uri));
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            activity.runOnUiThread(() -> {
                try {
                    activity.startActivity(intent);
                } catch (Exception ignored) {
                }
            });
            return "";
        } catch (Exception e) {
            return "Installation nicht möglich: " + e.getMessage();
        }
    }
}
