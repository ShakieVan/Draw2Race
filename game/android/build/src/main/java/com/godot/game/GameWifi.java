package com.godot.game;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.LocationManager;
import android.net.wifi.SoftApConfiguration;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;

import org.json.JSONObject;

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;

/**
 * Spiel-WLAN (Beta 1.0.2, übernommen aus Mau-Mau Flip): eigenes WLAN über WifiManager.startLocalOnlyHotspot, aufgerufen aus
 * scripts/net/net_android.gd per JavaClassWrapper (statische Methoden, wie NetHelper.java). LocalOnlyHotspotCallback ist eine
 * Klasse und lässt sich deshalb nicht aus GDScript implementieren. Alle Einstiege fangen Throwable (wie Updater.java seit 1.0.1).
 * - startHotspot(activity): startet auf dem Main-Looper; das Ergebnis kommt später, GDScript fragt hotspotState() ab.
 * - hotspotState(activity): JSON {status: off|starting|on|failed|stopped, ssid, password, security (open|wpa2|wpa3_transition|wpa3|
 *   other), error (Code, siehe unten), error_code (Android-Zahl), sdk, permission (nötige Laufzeit-Erlaubnis), granted, location_on,
 *   ap_enabled (normaler Hotspot läuft, soweit lesbar), concurrency (Heim-WLAN bleibt verbunden)}.
 *   error: "" | no_channel | generic | incompatible_mode (meist: normaler Hotspot läuft) | tethering_disallowed | permission |
 *   location_off | unsupported | busy | exception.
 * - stopHotspot(): Reservation schließen.
 * - requestPermission(activity): fehlende Laufzeit-Erlaubnis anfragen (true = schon erteilt). Bis Android 12 genauer UND grober Standort
 *   in einer Anfrage – Android 12 übergeht eine Anfrage nach nur dem genauen Standort (Prüfung 13.10.2026). Das Ergebnis meldet Godot
 *   je Erlaubnis über SceneTree.on_request_permissions_result.
 * Die Reservation liegt in einem statischen Feld; sie endet mit dem App-Prozess und wird beim Zerstören der Activity geschlossen.
 * Keine Methode und kein Feld nennt Typen ab API 26 in der Signatur (Reservation als AutoCloseable): Godot liest die Methoden der
 * Klasse per Reflexion, auf Android 7 schlüge das sonst mit NoClassDefFoundError fehl.
 * Start und Schließen zählen eine Generation hoch: Ein Rückruf eines überholten Starts (geschlossen, während er noch lief) wird
 * verworfen, eine dabei doch noch erteilte Reservation sofort geschlossen.
 * Die App ändert nie den normalen Hotspot des Nutzers.
 * Berechtigungen: CHANGE_WIFI_STATE (normal), NEARBY_WIFI_DEVICES (ab Android 13, neverForLocation), ACCESS_FINE_LOCATION (bis 12).
 */
public final class GameWifi {
    private static final Object LOCK = new Object();
    private static AutoCloseable reservation;      // WifiManager.LocalOnlyHotspotReservation (ab API 26)
    private static int generation = 0;              // jeder Start und jedes Schließen zählt hoch; ältere Rückrufe verfallen
    private static String status = "off";
    private static String error = "";
    private static int errorCode = 0;
    private static boolean lifecycleHooked = false;

    private GameWifi() {}

    private static WifiManager wifi(Activity activity) {
        return (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
    }

    public static String requiredPermission() {
        return Build.VERSION.SDK_INT >= 33 ? "android.permission.NEARBY_WIFI_DEVICES" : "android.permission.ACCESS_FINE_LOCATION";
    }

    private static boolean granted(Activity activity) {
        return activity.checkSelfPermission(requiredPermission()) == PackageManager.PERMISSION_GRANTED;
    }

    /** Erlaubnis anfragen, falls sie fehlt. true = schon erteilt; false = Systemdialog angestoßen (bzw. nicht möglich). */
    public static boolean requestPermission(final Activity activity) {
        try {
            if (granted(activity)) {
                return true;
            }
            final String[] wanted = Build.VERSION.SDK_INT >= 33
                    ? new String[] {"android.permission.NEARBY_WIFI_DEVICES"}
                    : new String[] {"android.permission.ACCESS_FINE_LOCATION", "android.permission.ACCESS_COARSE_LOCATION"};
            activity.runOnUiThread(() -> {
                try {
                    activity.requestPermissions(wanted, 4711);
                } catch (Throwable ignored) {
                }
            });
        } catch (Throwable ignored) {
        }
        return false;
    }

    private static boolean locationOn(Activity activity) {
        if (Build.VERSION.SDK_INT < 28) {
            return true;
        }
        try {
            LocationManager lm = (LocationManager) activity.getApplicationContext().getSystemService(Context.LOCATION_SERVICE);
            return lm == null || lm.isLocationEnabled();
        } catch (Throwable e) {
            return true;
        }
    }

    /** Läuft der normale Hotspot (Tethering)? Nur über eine versteckte Methode lesbar; -1 = unbekannt, 0 = aus, 1 = an. */
    private static int apEnabled(Activity activity) {
        try {
            Method m = WifiManager.class.getMethod("isWifiApEnabled");
            Object r = m.invoke(wifi(activity));
            if (r instanceof Boolean) {
                // Ist der eigene Spiel-WLAN an, meldet Android ihn hier mit; dann zählt das nicht als normaler Hotspot.
                return ((Boolean) r) && reservation == null ? 1 : 0;
            }
        } catch (Throwable ignored) {
        }
        return -1;
    }

    private static void setState(String s, String err, int code) {
        synchronized (LOCK) {
            status = s;
            error = err;
            errorCode = code;
        }
    }

    /** Zustand nur setzen, wenn der Rückruf zum laufenden Start gehört (sonst ist er überholt). Aufruf unter LOCK. */
    private static boolean current(int gen) {
        return gen == generation;
    }

    private static String failText(int reason) {
        switch (reason) {
            case WifiManager.LocalOnlyHotspotCallback.ERROR_NO_CHANNEL: return "no_channel";
            case WifiManager.LocalOnlyHotspotCallback.ERROR_INCOMPATIBLE_MODE: return "incompatible_mode";
            case WifiManager.LocalOnlyHotspotCallback.ERROR_TETHERING_DISALLOWED: return "tethering_disallowed";
            default: return "generic";
        }
    }

    private static void hookLifecycle(Activity activity) {
        if (lifecycleHooked) {
            return;
        }
        lifecycleHooked = true;
        activity.getApplication().registerActivityLifecycleCallbacks(new Application.ActivityLifecycleCallbacks() {
            @Override public void onActivityCreated(Activity a, Bundle b) {}
            @Override public void onActivityStarted(Activity a) {}
            @Override public void onActivityResumed(Activity a) {}
            @Override public void onActivityPaused(Activity a) {}
            @Override public void onActivityStopped(Activity a) {}
            @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
            @Override public void onActivityDestroyed(Activity a) {
                if (a.isFinishing()) {
                    stopHotspot();
                }
            }
        });
    }

    /** Spiel-WLAN starten. "" = Start angestoßen (oder läuft schon), sonst Fehlercode wie in hotspotState. */
    public static String startHotspot(final Activity activity) {
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                setState("failed", "unsupported", 0);
                return "unsupported";
            }
            synchronized (LOCK) {
                if (reservation != null || "starting".equals(status)) {
                    return "";
                }
            }
            if (!granted(activity)) {
                setState("failed", "permission", 0);
                return "permission";
            }
            if (Build.VERSION.SDK_INT < 33 && !locationOn(activity)) {
                setState("failed", "location_off", 0);
                return "location_off";
            }
            final int gen;
            synchronized (LOCK) {
                gen = ++generation;
                status = "starting";
                error = "";
                errorCode = 0;
            }
            hookLifecycle(activity);
            final WifiManager wm = wifi(activity);
            new Handler(Looper.getMainLooper()).post(() -> {
                try {
                    wm.startLocalOnlyHotspot(new WifiManager.LocalOnlyHotspotCallback() {
                        @Override
                        public void onStarted(WifiManager.LocalOnlyHotspotReservation r) {
                            AutoCloseable old = null;
                            boolean stale;
                            synchronized (LOCK) {
                                stale = !current(gen);
                                if (!stale) {
                                    old = reservation;
                                    reservation = r;
                                    status = "on";
                                    error = "";
                                    errorCode = 0;
                                }
                            }
                            closeQuietly(stale ? r : old);   // überholt (inzwischen geschlossen): sofort wieder zu
                        }

                        @Override
                        public void onStopped() {
                            synchronized (LOCK) {
                                if (current(gen)) {
                                    reservation = null;
                                    status = "stopped";
                                }
                            }
                        }

                        @Override
                        public void onFailed(int reason) {
                            synchronized (LOCK) {
                                if (current(gen)) {
                                    reservation = null;
                                    status = "failed";
                                    error = failText(reason);
                                    errorCode = reason;
                                }
                            }
                        }
                    }, new Handler(Looper.getMainLooper()));
                } catch (SecurityException e) {
                    failIfCurrent(gen, "permission");
                } catch (IllegalStateException e) {
                    failIfCurrent(gen, "busy");
                } catch (Throwable e) {
                    failIfCurrent(gen, "exception");
                }
            });
            return "";
        } catch (Throwable e) {
            setState("failed", "exception", 0);
            return "exception";
        }
    }

    private static void failIfCurrent(int gen, String err) {
        synchronized (LOCK) {
            if (current(gen)) {
                status = "failed";
                error = err;
                errorCode = 0;
            }
        }
    }

    private static void closeQuietly(AutoCloseable r) {
        if (r != null) {
            try {
                r.close();
            } catch (Throwable ignored) {
            }
        }
    }

    /** Spiel-WLAN schließen (auch ein noch laufender Start wird verworfen). true = es lief. */
    public static boolean stopHotspot() {
        AutoCloseable r;
        synchronized (LOCK) {
            generation++;
            r = reservation;
            reservation = null;
            if (!"failed".equals(status)) {
                status = "off";
            }
        }
        if (r != null) {
            try {
                r.close();
            } catch (Throwable ignored) {
            }
            return true;
        }
        return false;
    }

    private static String clean(String ssid) {
        if (ssid == null) {
            return "";
        }
        if (ssid.length() >= 2 && ssid.startsWith("\"") && ssid.endsWith("\"")) {
            return ssid.substring(1, ssid.length() - 1);
        }
        return ssid;
    }

    private static void putCredentials(JSONObject out, Object reservationObject) throws Exception {
        WifiManager.LocalOnlyHotspotReservation r = (WifiManager.LocalOnlyHotspotReservation) reservationObject;
        String ssid = "";
        String pass = "";
        String sec = "other";
        if (Build.VERSION.SDK_INT >= 30) {
            SoftApConfiguration c = r.getSoftApConfiguration();
            if (Build.VERSION.SDK_INT >= 33 && c.getWifiSsid() != null) {
                ssid = new String(c.getWifiSsid().getBytes(), StandardCharsets.UTF_8);
            } else {
                ssid = clean(c.getSsid());
            }
            pass = c.getPassphrase() != null ? c.getPassphrase() : "";
            switch (c.getSecurityType()) {
                case SoftApConfiguration.SECURITY_TYPE_OPEN: sec = "open"; break;
                case SoftApConfiguration.SECURITY_TYPE_WPA2_PSK: sec = "wpa2"; break;
                case SoftApConfiguration.SECURITY_TYPE_WPA3_SAE_TRANSITION: sec = "wpa3_transition"; break;
                case SoftApConfiguration.SECURITY_TYPE_WPA3_SAE: sec = "wpa3"; break;
                default: sec = "other";
            }
        } else {
            @SuppressWarnings("deprecation")
            WifiConfiguration c = r.getWifiConfiguration();
            if (c != null) {
                ssid = clean(c.SSID);
                pass = c.preSharedKey != null ? clean(c.preSharedKey) : "";
                sec = pass.isEmpty() ? "open" : "wpa2";
            }
        }
        out.put("ssid", ssid);
        out.put("password", pass);
        out.put("security", sec);
    }

    public static String hotspotState(Activity activity) {
        JSONObject out = new JSONObject();
        try {
            Object r;
            synchronized (LOCK) {
                r = reservation;
                out.put("status", status);
                out.put("error", error);
                out.put("error_code", errorCode);
            }
            out.put("ssid", "");
            out.put("password", "");
            out.put("security", "");
            if (r != null) {
                try {
                    putCredentials(out, r);
                } catch (Throwable e) {
                    out.put("credentials_error", String.valueOf(e));
                }
            }
            out.put("sdk", Build.VERSION.SDK_INT);
            out.put("permission", requiredPermission());
            out.put("granted", granted(activity));
            out.put("location_on", locationOn(activity));
            out.put("ap_enabled", apEnabled(activity));
            boolean conc = false;
            if (Build.VERSION.SDK_INT >= 30) {
                try {
                    conc = wifi(activity).isStaApConcurrencySupported();
                } catch (Throwable ignored) {
                }
            }
            out.put("concurrency", conc);
        } catch (Throwable e) {
            return "{\"status\":\"failed\",\"error\":\"exception\"}";
        }
        return out.toString();
    }
}
