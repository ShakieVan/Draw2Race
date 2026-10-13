/**************************************************************************/
/*  GodotApp.java                                                         */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

package com.godot.game;

import org.godotengine.godot.Godot;
import org.godotengine.godot.GodotActivity;

import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;

import androidx.activity.EdgeToEdge;
import androidx.core.splashscreen.SplashScreen;

/**
 * Template activity for Godot Android builds.
 * Feel free to extend and modify this class for your custom logic.
 */
public class GodotApp extends GodotActivity {
	static {
		// .NET libraries.
		if (BuildConfig.FLAVOR.equals("mono")) {
			try {
				Log.v("GODOT", "Loading System.Security.Cryptography.Native.Android library");
				System.loadLibrary("System.Security.Cryptography.Native.Android");
			} catch (UnsatisfiedLinkError e) {
				Log.e("GODOT", "Unable to load System.Security.Cryptography.Native.Android library");
			}
		}
	}

	private final Runnable updateWindowAppearance = () -> {
		Godot godot = getGodot();
		if (godot != null) {
			godot.enableImmersiveMode(godot.isInImmersiveMode(), true);
			godot.enableEdgeToEdge(godot.isInEdgeToEdgeMode(), true);
			godot.setSystemBarsAppearance();
		}
	};

	// Draw2Race (Beta 1.0.2, übernommen aus Mau-Mau Flip 1.6.1, Gerätetest mit gesperrten Testhandys): Ist die Eigenschaft
	// log.tag.Draw2RaceTestLock auf VERBOSE gesetzt, erscheint die App über dem Sperrbildschirm und schaltet ihn dabei ein. Das Handy
	// bleibt gesperrt: Home, Benachrichtigungen und jede andere App (Browser, Installationsdialog, Systemdialoge) liegen weiter hinter
	// der Sperre. Setzen kann die Eigenschaft nur adb, keine App; beim Neustart verfällt sie.
	//   adb shell setprop log.tag.Draw2RaceTestLock VERBOSE      (aus: … INFO)
	//   adb shell am start -n de.draw2race.game/com.godot.game.GodotAppLauncher
	private static final String TEST_LOCK_TAG = "Draw2RaceTestLock";

	private void applyTestLock() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
			return;
		}
		try {
			boolean on = Log.isLoggable(TEST_LOCK_TAG, Log.VERBOSE);
			setShowWhenLocked(on);
			setTurnScreenOn(on);
		} catch (Throwable ignored) {
		}
	}

	@Override
	public void onCreate(Bundle savedInstanceState) {
		SplashScreen.installSplashScreen(this);
		EdgeToEdge.enable(this);
		super.onCreate(savedInstanceState);
		applyTestLock();
		// Draw2Race (Beta 1.0.2, Spiel-WLAN): App-Link draw2race://join?h=…&p=… merken (AppLink.java) und den Testeinstieg
		// „gescannter Text“ (Extra d2r_scan, QrScan.java). Nicht nach einer Wiederherstellung oder aus dem Verlauf, sonst träte die
		// App einem alten Spiel erneut bei.
		Intent start = getIntent();
		if (savedInstanceState == null && start != null
				&& (start.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0) {
			AppLink.remember(start);
			QrScan.remember(start);
		}
	}

	@Override
	public void onNewIntent(Intent intent) {
		super.onNewIntent(intent);
		applyTestLock();
		AppLink.remember(intent);
		QrScan.remember(intent);
	}

	@Override
	public void onResume() {
		super.onResume();
		applyTestLock();
		updateWindowAppearance.run();
	}

	@Override
	public void onGodotMainLoopStarted() {
		super.onGodotMainLoopStarted();
		runOnUiThread(updateWindowAppearance);
	}

	@Override
	public void onGodotForceQuit(Godot instance) {
		if (!BuildConfig.FLAVOR.equals("instrumented")) {
			// For instrumented builds, we disable force-quitting to allow the instrumented tests to complete
			// successfully, otherwise they fail when the process crashes.
			super.onGodotForceQuit(instance);
		}
	}
}
