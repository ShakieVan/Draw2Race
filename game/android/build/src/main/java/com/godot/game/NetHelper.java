package com.godot.game;

import android.app.Activity;
import android.content.Context;
import android.net.ConnectivityManager;
import android.net.DhcpInfo;
import android.net.LinkAddress;
import android.net.LinkProperties;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.RouteInfo;
import android.net.wifi.WifiManager;
import android.os.Build;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InterfaceAddress;
import java.net.NetworkInterface;
import java.util.Collections;

/**
 * Android-Teil des lokalen Mehrspielers (docs/MULTIPLAYER_RECHERCHE.md 4.2–4.4), aufgerufen aus scripts/net/net_android.gd per
 * JavaClassWrapper (statische Methoden, wie Updater.java):
 * - Prozess an das WLAN binden bzw. lösen (ConnectivityManager.bindProcessToNetwork). Ein Hotspot ohne Internet wird nie zum
 *   Standardnetz; ohne Bindung laufen neue Sockets bei eingeschalteten mobilen Daten ins Mobilnetz. Die Bindung gilt für alle
 *   danach erzeugten Sockets des Prozesses. An welches Netz (WLAN oder ab Android 16 der eigene Hotspot) entscheidet
 *   net_android.gd und übergibt das Handle (bindNetwork).
 * - Netzwerkzustand als JSON (WLAN/Mobilnetz, Internet geprüft, Standardnetz, gebunden, lokales Netz = eigener Hotspot, Adressen,
 *   Gateway).
 * - Eigene Multicast-Sperre (WifiManager.MulticastLock), damit Rundrufe auch auf sparsamen Geräten ankommen.
 * Berechtigungen: ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE (alle „normal“, ohne Dialog).
 */
public final class NetHelper {
    private static WifiManager.MulticastLock multicastLock;

    private NetHelper() {}

    private static ConnectivityManager connectivity(Activity activity) {
        return (ConnectivityManager) activity.getApplicationContext().getSystemService(Context.CONNECTIVITY_SERVICE);
    }

    private static WifiManager wifi(Activity activity) {
        return (WifiManager) activity.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
    }

    private static String transport(NetworkCapabilities caps) {
        if (caps == null) return "?";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return "vpn";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return "wifi";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return "mobile";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) return "ethernet";
        if (caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) return "bluetooth";
        return "other";
    }

    private static String gateway(LinkProperties props) {
        if (props == null) return "";
        for (RouteInfo route : props.getRoutes()) {
            InetAddress gw = route.getGateway();
            if (route.isDefaultRoute() && gw instanceof Inet4Address && !gw.isAnyLocalAddress()) return gw.getHostAddress();
        }
        return "";
    }

    private static JSONObject describe(ConnectivityManager cm, Network network) throws Exception {
        JSONObject o = new JSONObject();
        NetworkCapabilities caps = cm.getNetworkCapabilities(network);
        LinkProperties props = cm.getLinkProperties(network);
        o.put("handle", String.valueOf(network.getNetworkHandle()));
        o.put("transport", transport(caps));
        o.put("internet", caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET));
        o.put("validated", caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
        o.put("not_metered", caps != null && caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED));
        o.put("local", isLocal(caps));
        o.put("iface", props != null && props.getInterfaceName() != null ? props.getInterfaceName() : "");
        JSONArray addresses = new JSONArray();
        if (props != null) {
            for (LinkAddress address : props.getLinkAddresses()) {
                if (address.getAddress() instanceof Inet4Address) {
                    addresses.put(address.getAddress().getHostAddress() + "/" + address.getPrefixLength());
                }
            }
        }
        o.put("addresses", addresses);
        o.put("gateway", gateway(props));
        return o;
    }

    /**
     * Lokales Netz (NET_CAPABILITY_LOCAL_NETWORK = 36, ab Android 15/API 35): So meldet Android 16 den eigenen Hotspot – mit Transport
     * WLAN, aber ohne Gateway (Gerätetest S24 Ultra 04.10.2026, swlan0). Wert als Zahl, damit es auch mit älterem SDK übersetzt.
     */
    private static boolean isLocal(NetworkCapabilities caps) {
        try {
            return caps != null && Build.VERSION.SDK_INT >= 35 && caps.hasCapability(36);
        } catch (Exception e) {
            return false;
        }
    }

    private static boolean hotspotName(LinkProperties props) {
        String name = props != null && props.getInterfaceName() != null ? props.getInterfaceName().toLowerCase() : "";
        return name.startsWith("swlan") || name.startsWith("softap") || name.startsWith("ap");
    }

    /** Ein WLAN, in dem das Handy Gast ist (mit Gateway zuerst) – nie der eigene Hotspot. Nur noch für bindWifi (Netztest). */
    @SuppressWarnings("deprecation")
    private static Network findWifi(ConnectivityManager cm) {
        Network fallback = null;
        for (Network network : cm.getAllNetworks()) {
            NetworkCapabilities caps = cm.getNetworkCapabilities(network);
            if (caps == null || !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) continue;
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) || isLocal(caps)) continue;
            LinkProperties props = cm.getLinkProperties(network);
            if (hotspotName(props)) continue;
            if (!gateway(props).isEmpty()) return network;
            fallback = network;
        }
        return fallback;
    }

    /** Netzwerkzustand als JSON-Text (Felder siehe net_android.gd, state()). */
    @SuppressWarnings("deprecation")
    public static String state(Activity activity) {
        JSONObject out = new JSONObject();
        try {
            ConnectivityManager cm = connectivity(activity);
            out.put("sdk", Build.VERSION.SDK_INT);
            out.put("device", Build.MANUFACTURER + " " + Build.MODEL);
            Network active = cm.getActiveNetwork();
            Network bound = cm.getBoundNetworkForProcess();
            JSONArray networks = new JSONArray();
            String wifiGateway = "";
            for (Network network : cm.getAllNetworks()) {
                JSONObject o = describe(cm, network);
                o.put("default", network.equals(active));
                o.put("bound", network.equals(bound));
                networks.put(o);
                if (wifiGateway.isEmpty() && "wifi".equals(o.getString("transport"))) wifiGateway = o.getString("gateway");
            }
            out.put("networks", networks);
            out.put("default", active != null ? describe(cm, active) : JSONObject.NULL);
            out.put("bound", bound != null ? describe(cm, bound) : JSONObject.NULL);
            out.put("wifi_gateway", wifiGateway);
            String dhcp = "";
            WifiManager wm = wifi(activity);
            if (wm != null) {
                out.put("wifi_enabled", wm.isWifiEnabled());
                DhcpInfo info = wm.getDhcpInfo();
                if (info != null && info.gateway != 0) {
                    int g = info.gateway;
                    dhcp = (g & 0xff) + "." + ((g >> 8) & 0xff) + "." + ((g >> 16) & 0xff) + "." + ((g >> 24) & 0xff);
                }
            }
            out.put("dhcp_gateway", dhcp);
            out.put("multicast_lock", multicastLock != null && multicastLock.isHeld());
            out.put("interfaces", interfaceArray());
        } catch (Exception e) {
            try {
                out.put("error", e.toString());
            } catch (Exception ignored) {
            }
        }
        return out.toString();
    }

    /** Eigene IPv4-Adressen mit Netzpräfix und Rundrufadresse (auch die Hotspot-Schnittstelle des Hosts) als JSON-Liste. */
    public static String interfaces(Activity activity) {
        try {
            return interfaceArray().toString();
        } catch (Exception e) {
            return "[]";
        }
    }

    private static JSONArray interfaceArray() throws Exception {
        JSONArray out = new JSONArray();
        for (NetworkInterface iface : Collections.list(NetworkInterface.getNetworkInterfaces())) {
            if (!iface.isUp() || iface.isLoopback()) continue;
            for (InterfaceAddress address : iface.getInterfaceAddresses()) {
                if (!(address.getAddress() instanceof Inet4Address)) continue;
                JSONObject o = new JSONObject();
                o.put("name", iface.getName());
                o.put("address", address.getAddress().getHostAddress());
                o.put("prefix", address.getNetworkPrefixLength());
                o.put("broadcast", address.getBroadcast() != null ? address.getBroadcast().getHostAddress() : "");
                out.put(o);
            }
        }
        return out;
    }

    /** Leerer Text = Prozess ans WLAN gebunden, sonst Grund. */
    public static String bindWifi(Activity activity) {
        try {
            ConnectivityManager cm = connectivity(activity);
            Network network = findWifi(cm);
            if (network == null) return "Kein WLAN verbunden.";
            if (!cm.bindProcessToNetwork(network)) return "Android hat die Bindung abgelehnt.";
            return "";
        } catch (Exception e) {
            return "Bindung fehlgeschlagen: " + e.getMessage();
        }
    }

    /**
     * Leerer Text = Prozess an das Netz mit diesem Handle gebunden (Network.getNetworkHandle(), wie in state()), sonst Grund. Welches Netz
     * das WLAN ist, entscheidet net_android.gd (wifi_handle) – dort ist die Einordnung getestet.
     */
    @SuppressWarnings("deprecation")
    public static String bindNetwork(Activity activity, String handle) {
        try {
            ConnectivityManager cm = connectivity(activity);
            for (Network network : cm.getAllNetworks()) {
                if (!String.valueOf(network.getNetworkHandle()).equals(handle)) continue;
                if (!cm.bindProcessToNetwork(network)) return "Android hat die Bindung abgelehnt.";
                return "";
            }
            return "Das WLAN ist nicht mehr verbunden.";
        } catch (Exception e) {
            return "Bindung fehlgeschlagen: " + e.getMessage();
        }
    }

    /** Bindung lösen: neue Sockets laufen wieder über das Standardnetz (z. B. für den Update-Download). */
    public static boolean unbind(Activity activity) {
        try {
            return connectivity(activity).bindProcessToNetwork(null);
        } catch (Exception e) {
            return false;
        }
    }

    public static boolean multicastAcquire(Activity activity) {
        try {
            if (multicastLock == null) {
                WifiManager wm = wifi(activity);
                if (wm == null) return false;
                multicastLock = wm.createMulticastLock("Draw2RaceNetz");
                multicastLock.setReferenceCounted(false);
            }
            if (!multicastLock.isHeld()) multicastLock.acquire();
            return multicastLock.isHeld();
        } catch (Exception e) {
            return false;
        }
    }

    public static boolean multicastRelease(Activity activity) {
        try {
            if (multicastLock != null && multicastLock.isHeld()) multicastLock.release();
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
