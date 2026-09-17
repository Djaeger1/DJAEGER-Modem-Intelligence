package com.djaeger.facebookadshield526;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.content.pm.PackageInfo;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.TextView;

import java.util.Collections;
import java.util.Locale;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.atomic.AtomicBoolean;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * DJAEGER Facebook Ad Shield 526 - SHADOW1.
 *
 * Deliberately scoped to com.facebook.katana 526.1.0.66.75 only.
 * It does NOT touch DNS, networking, account/session data or other apps.
 *
 * Strategy:
 *  1) detect the visible sponsored marker (Indonesian/English),
 *  2) collapse the containing feed unit, preferring Litho/list-row roots,
 *  3) run a few bounded scans after Activity resume as a fallback.
 *
 * This is a UI-layer compatibility backport/failsafe, not a claim that the
 * upstream 576/578 structural hooks are valid on Facebook 526.
 */
public final class FacebookAdShield526 implements IXposedHookLoadPackage {
    private static final String TARGET_PACKAGE = "com.facebook.katana";
    private static final String TARGET_VERSION = "526.1.0.66.75";
    private static final String TAG = "DJAEGER-FB526";

    private static final AtomicBoolean INSTALLED = new AtomicBoolean(false);
    private static final Set<View> HIDDEN = Collections.newSetFromMap(new WeakHashMap<>());
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    @Override
    public void handleLoadPackage(final XC_LoadPackage.LoadPackageParam lpparam) throws Throwable {
        if (!TARGET_PACKAGE.equals(lpparam.packageName)) return;
        if (lpparam.processName != null && !TARGET_PACKAGE.equals(lpparam.processName)) return;

        XposedHelpers.findAndHookMethod(Application.class, "attach", Context.class, new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (INSTALLED.get()) return;
                Context context = (Context) param.args[0];
                String version = getVersion(context);
                if (!TARGET_VERSION.equals(version)) {
                    XposedBridge.log(TAG + " disabled: expected " + TARGET_VERSION + ", got " + version);
                    return;
                }
                if (!INSTALLED.compareAndSet(false, true)) return;
                installHooks();
                XposedBridge.log(TAG + " SHADOW1 active on Facebook " + version);
            }
        });
    }

    private static String getVersion(Context context) {
        try {
            PackageInfo pi = context.getPackageManager().getPackageInfo(TARGET_PACKAGE, 0);
            return pi.versionName == null ? "unknown" : pi.versionName;
        } catch (Throwable t) {
            XposedBridge.log(TAG + " version check failed: " + t);
            return "unknown";
        }
    }

    private static void installHooks() {
        XC_MethodHook textHook = new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                if (!(param.thisObject instanceof TextView)) return;
                TextView tv = (TextView) param.thisObject;
                CharSequence text = tv.getText();
                if (isSponsoredMarker(text)) queueHide(tv);
            }
        };

        try {
            XposedHelpers.findAndHookMethod(TextView.class, "setText", CharSequence.class, textHook);
        } catch (Throwable t) {
            XposedBridge.log(TAG + " setText(CharSequence) hook unavailable: " + t);
        }
        try {
            XposedHelpers.findAndHookMethod(TextView.class, "setText", CharSequence.class, TextView.BufferType.class, textHook);
        } catch (Throwable t) {
            XposedBridge.log(TAG + " setText(CharSequence,BufferType) hook unavailable: " + t);
        }

        try {
            XposedHelpers.findAndHookMethod(View.class, "setContentDescription", CharSequence.class, new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    View v = (View) param.thisObject;
                    CharSequence d = v.getContentDescription();
                    if (isSponsoredMarker(d)) queueHide(v);
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + " contentDescription hook unavailable: " + t);
        }

        try {
            XposedHelpers.findAndHookMethod(Activity.class, "onResume", new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    Activity a = (Activity) param.thisObject;
                    View decor = a.getWindow() == null ? null : a.getWindow().getDecorView();
                    if (decor == null) return;
                    // Bounded fallbacks only. No permanent polling loop.
                    MAIN.postDelayed(() -> scanTree(decor, 0, new int[]{0}), 350);
                    MAIN.postDelayed(() -> scanTree(decor, 0, new int[]{0}), 1200);
                    MAIN.postDelayed(() -> scanTree(decor, 0, new int[]{0}), 3000);
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + " Activity.onResume hook unavailable: " + t);
        }
    }

    private static boolean isSponsoredMarker(CharSequence cs) {
        if (cs == null) return false;
        String s = cs.toString().trim();
        // Avoid treating a long post body that merely mentions the word as an ad marker.
        if (s.isEmpty() || s.length() > 80) return false;
        String n = s.toLowerCase(Locale.ROOT)
                .replace('\u00a0', ' ')
                .replace("•", "·")
                .trim();
        return n.equals("bersponsor")
                || n.startsWith("bersponsor ·")
                || n.startsWith("bersponsor  ·")
                || n.equals("sponsored")
                || n.startsWith("sponsored ·")
                || n.startsWith("sponsored  ·");
    }

    private static void queueHide(final View marker) {
        if (marker == null) return;
        marker.post(() -> hideContainingUnit(marker));
        marker.postDelayed(() -> hideContainingUnit(marker), 120);
    }

    private static void hideContainingUnit(View marker) {
        if (!marker.isAttachedToWindow()) return;
        View root = findFeedUnitRoot(marker);
        if (root == null) return;
        synchronized (HIDDEN) {
            if (HIDDEN.contains(root)) return;
            HIDDEN.add(root);
        }
        collapse(root);
        XposedBridge.log(TAG + " hidden sponsored unit root=" + root.getClass().getName());
    }

    private static View findFeedUnitRoot(View marker) {
        View current = marker;
        View sizeFallback = null;
        View rootView = marker.getRootView();
        int screenWidth = rootView == null ? 0 : rootView.getWidth();
        float density = marker.getResources().getDisplayMetrics().density;
        int minCardHeight = (int) (160f * density);

        for (int depth = 0; depth < 16 && current != null; depth++) {
            String cn = current.getClass().getName().toLowerCase(Locale.ROOT);
            if (cn.contains("lithoview")) return current;

            if (depth >= 2 && screenWidth > 0
                    && current.getWidth() >= (int) (screenWidth * 0.82f)
                    && current.getHeight() >= minCardHeight
                    && sizeFallback == null) {
                sizeFallback = current;
            }

            ViewParent parent = current.getParent();
            if (!(parent instanceof View)) break;
            View parentView = (View) parent;
            String pn = parentView.getClass().getName().toLowerCase(Locale.ROOT);
            if (pn.contains("recyclerview") || pn.contains("listview") || pn.contains("viewpager")) {
                return current;
            }
            current = parentView;
        }
        return sizeFallback;
    }

    private static void collapse(View root) {
        try {
            root.setVisibility(View.GONE);
            root.setAlpha(0f);
            root.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS);
            ViewGroup.LayoutParams lp = root.getLayoutParams();
            if (lp != null) {
                lp.height = 0;
                if (lp instanceof ViewGroup.MarginLayoutParams) {
                    ViewGroup.MarginLayoutParams mlp = (ViewGroup.MarginLayoutParams) lp;
                    mlp.topMargin = 0;
                    mlp.bottomMargin = 0;
                }
                root.setLayoutParams(lp);
            }
            root.requestLayout();
        } catch (Throwable t) {
            XposedBridge.log(TAG + " collapse failed: " + t);
        }
    }

    private static void scanTree(View v, int depth, int[] count) {
        if (v == null || depth > 24 || count[0]++ > 1200) return;
        if (v instanceof TextView) {
            CharSequence text = ((TextView) v).getText();
            if (isSponsoredMarker(text)) {
                hideContainingUnit(v);
                return;
            }
        }
        if (isSponsoredMarker(v.getContentDescription())) {
            hideContainingUnit(v);
            return;
        }
        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            int n = g.getChildCount();
            for (int i = 0; i < n; i++) {
                scanTree(g.getChildAt(i), depth + 1, count);
                if (count[0] > 1200) return;
            }
        }
    }
}
