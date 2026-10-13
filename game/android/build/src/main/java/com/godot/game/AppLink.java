package com.godot.game;

import android.content.Intent;
import android.net.Uri;

/**
 * App-Link „In Draw2Race öffnen“ (Beta 1.0.2, Spiel-WLAN, übernommen aus Mau-Mau Flip): Die Einladungsseite des Gastgebers
 * (NetApk, http://<IP>:24683/) öffnet die App mit draw2race://join?h=<IP>&p=<Port>.
 * GodotApp meldet hier jedes Intent beim Start (onCreate) und bei neuem Intent (onNewIntent); der Link bleibt gemerkt, bis
 * scripts/net/net_android.gd ihn per JavaClassWrapper abholt (take()). Geprüft wird er erst in GDScript (private IP, Port).
 * Der Intent-Filter hängt an der Activity-Alias .GodotAppLink (AndroidManifest.xml), Ziel ist .GodotApp.
 */
public final class AppLink {
    private static volatile String pending = "";

    private AppLink() {}

    /** Intent merken, falls es ein App-Link ist (Schema draw2race). Alles andere bleibt unbeachtet. */
    public static void remember(Intent intent) {
        try {
            if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction())) {
                return;
            }
            Uri data = intent.getData();
            if (data == null || !"draw2race".equalsIgnoreCase(data.getScheme())) {
                return;
            }
            String text = data.toString();
            if (text.length() > 512) {
                return;
            }
            pending = text;
        } catch (Throwable ignored) {
        }
    }

    /** Gemerkten Link abholen und vergessen ("" = keiner). */
    public static synchronized String take() {
        String out = pending;
        pending = "";
        return out == null ? "" : out;
    }
}
