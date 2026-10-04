package com.godot.game;

import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;

import androidx.core.content.FileProvider;

import java.io.File;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * Android-Teil der Update-Funktion . Download und SHA-256-Prüfung erledigt
 * scripts/updater.gd; hier: Installationsberechtigung, Signatur-/Versionsprüfung der geladenen APK und Start des
 * System-Installers über den FileProvider der Godot-Bibliothek (Kennung <paket>.fileprovider, gibt files/ frei). Aufruf aus GDScript per JavaClassWrapper (statische Methoden).
 * minSdk ist 24 (Android 7.0): Schnittstellen ab API 26/28 nur hinter Build.VERSION.SDK_INT mit Rückfall. Fehlt eine Methode doch,
 * wirft Android einen Error (NoSuchMethodError) statt einer Exception – darum fangen alle Einstiege Throwable.
 */
public final class Updater {
    private Updater() {}

    @SuppressWarnings("deprecation")
    public static boolean canInstall(Activity activity) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) return activity.getPackageManager().canRequestPackageInstalls();
            // Android 7.x: kein Recht je App, sondern der Schalter „Unbekannte Herkunft“ (Einstellungen → Sicherheit).
            return Settings.Secure.getInt(activity.getContentResolver(), Settings.Secure.INSTALL_NON_MARKET_APPS, 0) == 1;
        } catch (Throwable t) {
            // Unbekannt: Android 7 lässt den System-Installer selbst nachfragen, ab Android 8 lieber die Einstellung anbieten.
            return Build.VERSION.SDK_INT < Build.VERSION_CODES.O;
        }
    }

    public static void openInstallPermission(Activity activity) {
        activity.runOnUiThread(() -> {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    activity.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:" + activity.getPackageName())));
                } else {
                    activity.startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS));
                }
            } catch (Throwable ignored) {
            }
        });
    }

    public static String installedVersion(Activity activity) {
        try {
            return activity.getPackageManager().getPackageInfo(activity.getPackageName(), 0).versionName;
        } catch (Throwable e) {
            return "";
        }
    }

    /** Leerer Text = in Ordnung, sonst Fehlerbeschreibung. */
    public static String verify(Activity activity, String path, String version) {
        try {
            PackageManager pm = activity.getPackageManager();
            PackageInfo installed = pm.getPackageInfo(activity.getPackageName(), signatureFlag());
            PackageInfo candidate = pm.getPackageArchiveInfo(path, signatureFlag());
            if (candidate == null) return "APK nicht lesbar (Datei beschädigt?)";
            if (!activity.getPackageName().equals(candidate.packageName)) return "Falsches Paket – die Datei ist nicht Draw2Race";
            if (versionCode(candidate) <= versionCode(installed)) return "Keine neuere Version (eine ältere wird nie installiert)";
            if (!version.equals(candidate.versionName)) return "Versionsangabe passt nicht zur Datei";
            Set<Signature> current = signers(installed);
            Set<Signature> incoming = signers(candidate);
            if (incoming.isEmpty()) return "Signatur passt nicht – die Datei ist nicht signiert";
            if (current.isEmpty() || !current.equals(incoming)) return "Signatur passt nicht – die Datei stammt nicht vom Draw2Race-Projekt oder wurde verändert";
            return "";
        } catch (Throwable e) {
            return "Prüfung fehlgeschlagen: " + e;
        }
    }

    // Signaturen und Versionsnummer: ab Android 9 (API 28) über signingInfo/getLongVersionCode, davor über die alten Felder.
    @SuppressWarnings("deprecation")
    private static int signatureFlag() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? PackageManager.GET_SIGNING_CERTIFICATES : PackageManager.GET_SIGNATURES;
    }

    @SuppressWarnings("deprecation")
    static long versionCode(PackageInfo info) {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.P ? info.getLongVersionCode() : info.versionCode;
    }

    @SuppressWarnings("deprecation")
    private static Set<Signature> signers(PackageInfo info) {
        Signature[] list;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            list = info.signingInfo == null ? null : info.signingInfo.getApkContentsSigners();
        } else {
            list = info.signatures;
        }
        return list == null ? Collections.emptySet() : new HashSet<>(Arrays.asList(list));
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
                } catch (Throwable ignored) {
                }
            });
            return "";
        } catch (Throwable e) {
            return "Installation nicht möglich: " + e.getMessage();
        }
    }
}
