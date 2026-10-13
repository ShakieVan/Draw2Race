package com.godot.game;

import android.app.Activity;
import android.content.Context;
import android.net.ConnectivityManager;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.RouteInfo;
import android.net.wifi.WifiNetworkSpecifier;
import android.os.Build;
import android.util.Log;

import org.json.JSONObject;

import java.net.Inet4Address;
import java.net.InetAddress;

/**
 * Spiel-WLAN per QR-Code beitreten (Beta 1.0.2, übernommen aus Mau-Mau Flip 1.4.3): Die App verbindet sich selbst mit dem WLAN aus einem gescannten WLAN-QR-Code
 * (WIFI:S:…;T:WPA;P:…;;) – über WifiNetworkSpecifier (ab Android 10, Android zeigt einmal einen Systemdialog). Das Netz gehört nur
 * der App (kein Internet, das Handy bleibt sonst wie es ist); die App bindet sich daran (bind), damit die Verbindung zum Gastgeber
 * nicht über die mobilen Daten läuft. Aufgerufen aus scripts/net/qr_join.gd per JavaClassWrapper.
 * - request(activity, ssid, password, security wpa2|wpa3|open): "" = angefragt, sonst Fehlercode old_android | exception.
 *   Nicht „connect“ nennen: JavaClassWrapper leitet j.connect(…) aus GDScript an Object.connect weiter (Gerätetest 1.4.3).
 * - state(activity): JSON {status: idle|connecting|available|unavailable|lost, ssid, handle, gateway, address, sdk}.
 *   gateway = Gastgeber (im Spiel-WLAN ist das Handy des Gastgebers das Gateway).
 * - bind(activity): Prozess an dieses Netz binden. "" = gebunden, sonst Grund.
 * - release(activity): Anfrage zurückziehen (Android trennt das Spiel-WLAN, das Handy kommt wieder normal ins Internet); eine
 *   Bindung an dieses Netz wird gelöst. true = es gab eine Anfrage.
 */
public final class QrWifi {
    private static final Object LOCK = new Object();
    private static final int TIMEOUT_MS = 120000;
    private static ConnectivityManager.NetworkCallback callback;
    private static Network network;
    private static String status = "idle";
    private static String ssid = "";

    private QrWifi() {}

    private static ConnectivityManager connectivity(Activity activity) {
        return (ConnectivityManager) activity.getApplicationContext().getSystemService(Context.CONNECTIVITY_SERVICE);
    }

    public static String request(Activity activity, String wantedSsid, String password, String security) {
        if (Build.VERSION.SDK_INT < 29) {
            return "old_android";
        }
        try {
            release(activity);
            WifiNetworkSpecifier.Builder spec = new WifiNetworkSpecifier.Builder().setSsid(wantedSsid);
            if (password != null && !password.isEmpty() && !"open".equals(security)) {
                if ("wpa3".equals(security)) {
                    spec.setWpa3Passphrase(password);
                } else {
                    spec.setWpa2Passphrase(password);
                }
            }
            NetworkRequest request = new NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(spec.build())
                    .build();
            ConnectivityManager.NetworkCallback cb = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(Network n) {
                    synchronized (LOCK) {
                        if (callback != this) return;
                        network = n;
                        status = "available";
                    }
                }

                @Override
                public void onUnavailable() {
                    synchronized (LOCK) {
                        if (callback != this) return;
                        network = null;
                        status = "unavailable";
                    }
                }

                @Override
                public void onLost(Network n) {
                    synchronized (LOCK) {
                        if (callback != this) return;
                        network = null;
                        status = "lost";
                    }
                }
            };
            synchronized (LOCK) {
                callback = cb;
                network = null;
                status = "connecting";
                ssid = wantedSsid;
            }
            connectivity(activity).requestNetwork(request, cb, TIMEOUT_MS);
            return "";
        } catch (Throwable e) {
            Log.w("Draw2Race", "Spiel-WLAN aus dem QR-Code: " + e);
            synchronized (LOCK) {
                callback = null;
                status = "unavailable";
            }
            return "exception";
        }
    }

    private static String ipv4(InetAddress a) {
        return a instanceof Inet4Address && !a.isAnyLocalAddress() ? a.getHostAddress() : "";
    }

    public static String state(Activity activity) {
        JSONObject out = new JSONObject();
        try {
            Network n;
            synchronized (LOCK) {
                n = network;
                out.put("status", status);
                out.put("ssid", ssid);
            }
            out.put("sdk", Build.VERSION.SDK_INT);
            String gateway = "";
            String address = "";
            if (n != null) {
                out.put("handle", String.valueOf(n.getNetworkHandle()));
                LinkProperties props = connectivity(activity).getLinkProperties(n);
                if (props != null) {
                    for (RouteInfo route : props.getRoutes()) {
                        String gw = route.getGateway() == null ? "" : ipv4(route.getGateway());
                        if (!gw.isEmpty()) {
                            gateway = gw;
                            break;
                        }
                    }
                    if (gateway.isEmpty() && Build.VERSION.SDK_INT >= 30 && props.getDhcpServerAddress() != null) {
                        gateway = ipv4(props.getDhcpServerAddress());
                    }
                    for (LinkAddress la : props.getLinkAddresses()) {
                        String ip = ipv4(la.getAddress());
                        if (!ip.isEmpty()) {
                            address = ip + "/" + la.getPrefixLength();
                            break;
                        }
                    }
                }
            } else {
                out.put("handle", "");
            }
            out.put("gateway", gateway);
            out.put("address", address);
        } catch (Throwable ignored) {
        }
        return out.toString();
    }

    public static String bind(Activity activity) {
        Network n;
        synchronized (LOCK) {
            n = network;
        }
        if (n == null) {
            return "Das Spiel-WLAN ist nicht verbunden.";
        }
        try {
            return connectivity(activity).bindProcessToNetwork(n) ? "" : "Android hat die Bindung abgelehnt.";
        } catch (Throwable e) {
            return "Bindung fehlgeschlagen: " + e.getMessage();
        }
    }

    public static boolean release(Activity activity) {
        ConnectivityManager.NetworkCallback cb;
        Network n;
        synchronized (LOCK) {
            cb = callback;
            n = network;
            callback = null;
            network = null;
            status = "idle";
            ssid = "";
        }
        if (cb == null) {
            return false;
        }
        try {
            ConnectivityManager cm = connectivity(activity);
            if (n != null && n.equals(cm.getBoundNetworkForProcess())) {
                cm.bindProcessToNetwork(null);
            }
            cm.unregisterNetworkCallback(cb);
        } catch (Throwable ignored) {
        }
        return true;
    }
}
