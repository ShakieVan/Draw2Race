package com.godot.game;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;

import com.google.android.gms.common.ConnectionResult;
import com.google.android.gms.common.GoogleApiAvailability;
import com.google.android.gms.common.moduleinstall.ModuleInstall;
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest;
import com.google.mlkit.common.MlKitException;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanner;
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions;
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning;

import org.json.JSONObject;

/**
 * QR-Scanner in der App (Beta 1.0.2, übernommen aus Mau-Mau Flip 1.4.3): Google Code Scanner (play-services-code-scanner). Die
 * Kamera-Oberfläche kommt aus den Google-Play-Diensten, die App braucht keine Kamera-Erlaubnis. Aufgerufen aus scripts/net/qr_join.gd
 * per JavaClassWrapper
 * (statische Methoden, wie NetHelper.java/GameWifi.java); das Ergebnis kommt später, GDScript fragt take() ab.
 * - start(activity): "" = Scanner geöffnet, sonst Fehlercode: no_gms (keine bzw. veraltete Google-Play-Dienste), busy, exception.
 * - take(): JSON {status: idle|scanning|done|cancelled|failed, text, error, source (camera|intent), at (ms)}; ein Endstand
 *   (done/cancelled/failed) wird dabei abgeholt und vergessen.
 *   error bei failed: no_gms | module (Scanner-Modul wird noch geladen) | exception.
 * Testeinstieg ohne Kamera (Gerätetest): adb shell am start -n de.draw2race.game/com.godot.game.GodotAppLauncher --es d2r_scan "<Text>"
 * – GodotApp reicht das Intent an remember() weiter; der Text gilt als gescannt (source "intent"). GDScript wertet ihn nur auf dem
 * Beitreten-Bildschirm aus und verwirft ältere als 2 min; er löst nichts aus, was ein gescannter QR-Code nicht auch täte.
 */
public final class QrScan {
    private static final String TAG = "Draw2Race";
    private static final Object LOCK = new Object();
    private static String status = "idle";
    private static String text = "";
    private static String error = "";
    private static String source = "";
    private static long at = 0;

    private QrScan() {}

    private static void finish(String newStatus, String newText, String newError, String newSource) {
        synchronized (LOCK) {
            status = newStatus;
            text = newText == null ? "" : newText;
            error = newError == null ? "" : newError;
            source = newSource;
            at = System.currentTimeMillis();
        }
    }

    /** Gibt es die Google-Play-Dienste (Voraussetzung für den Scanner)? */
    public static boolean available(Activity activity) {
        try {
            return GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(activity) == ConnectionResult.SUCCESS;
        } catch (Throwable e) {
            return false;
        }
    }

    public static String start(Activity activity) {
        if (!available(activity)) {
            finish("failed", "", "no_gms", "camera");
            return "no_gms";
        }
        synchronized (LOCK) {
            if ("scanning".equals(status)) {
                return "busy";
            }
            status = "scanning";
            text = "";
            error = "";
            source = "camera";
        }
        try {
            GmsBarcodeScannerOptions options = new GmsBarcodeScannerOptions.Builder()
                    .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
                    .enableAutoZoom()
                    .build();
            activity.runOnUiThread(() -> {
                try {
                    GmsBarcodeScanner scanner = GmsBarcodeScanning.getClient(activity, options);
                    // Erst prüfen, ob das Scanner-Modul der Play-Dienste schon da ist (Gerätetest 1.4.3, S10: beim allerersten Antippen
                    // scheiterte startScan während des Ladens mit einem allgemeinen Fehler). Fehlt es: Laden anstoßen, Hinweis „wird geladen“.
                    ModuleInstall.getClient(activity).areModulesAvailable(scanner)
                            .addOnSuccessListener(r -> {
                                if (r.areModulesAvailable()) {
                                    scan(activity, scanner);
                                } else {
                                    install(activity, scanner);
                                    finish("failed", "", "module", "camera");
                                }
                            })
                            .addOnFailureListener(e -> scan(activity, scanner));
                } catch (Throwable e) {
                    Log.w(TAG, "QR-Scanner: " + e);
                    finish("failed", "", "exception", "camera");
                }
            });
            return "";
        } catch (Throwable e) {
            Log.w(TAG, "QR-Scanner: " + e);
            finish("failed", "", "exception", "camera");
            return "exception";
        }
    }

    private static void install(Activity activity, GmsBarcodeScanner scanner) {
        try {
            ModuleInstall.getClient(activity).installModules(ModuleInstallRequest.newBuilder().addApi(scanner).build());
        } catch (Throwable ignored) {
        }
    }

    private static void scan(Activity activity, GmsBarcodeScanner scanner) {
        try {
            scanner.startScan()
                    .addOnSuccessListener(barcode -> {
                        String raw = barcode.getRawValue();
                        if (raw == null || raw.isEmpty()) raw = barcode.getDisplayValue();
                        finish("done", raw, "", "camera");
                    })
                    .addOnCanceledListener(() -> finish("cancelled", "", "", "camera"))
                    .addOnFailureListener(e -> {
                        Log.w(TAG, "QR-Scanner: " + e);
                        boolean module = e instanceof MlKitException
                                && ((MlKitException) e).getErrorCode() == MlKitException.UNAVAILABLE;
                        if (module) {
                            install(activity, scanner);   // Scanner-Modul fehlt noch: Laden anstoßen, gleich noch einmal versuchen
                        }
                        finish("failed", "", module ? "module" : "exception", "camera");
                    });
        } catch (Throwable e) {
            Log.w(TAG, "QR-Scanner: " + e);
            finish("failed", "", "exception", "camera");
        }
    }

    /** Stand abholen; ein Endstand wird dabei vergessen. */
    public static String take() {
        JSONObject out = new JSONObject();
        synchronized (LOCK) {
            try {
                out.put("status", status);
                out.put("text", text);
                out.put("error", error);
                out.put("source", source);
                out.put("at", at);
                out.put("now", System.currentTimeMillis());
            } catch (Throwable ignored) {
            }
            if (!"scanning".equals(status)) {
                status = "idle";
                text = "";
                error = "";
                source = "";
            }
        }
        return out.toString();
    }

    /** Testeinstieg: Intent mit Extra „d2r_scan“ gilt als gescannter Text (siehe oben). */
    public static void remember(Intent intent) {
        if (intent == null) {
            return;
        }
        try {
            String injected = intent.getStringExtra("d2r_scan");
            if (injected == null || injected.isEmpty() || injected.length() > 1024) {
                return;
            }
            intent.removeExtra("d2r_scan");
            finish("done", injected, "", "intent");
        } catch (Throwable ignored) {
        }
    }
}
