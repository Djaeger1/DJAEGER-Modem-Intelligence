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
import android.view.accessibility.AccessibilityNodeInfo;
import android.view.accessibility.AccessibilityNodeProvider;
import android.widget.TextView;

import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * DJAEGER Facebook Ad Shield 526 - SHADOW2.
 *
 * Strict scope: com.facebook.katana 526.1.0.66.75 only.
 * No DNS/network/account/session modification.
 *
 * SHADOW2 adds a Litho/accessibility path because Facebook 526 can render the
 * visible "Bersponsor" label through virtual accessibility nodes instead of
 * Android TextView objects.  SHADOW1 therefore missed real sponsored units.
 *
 * Strategy:
 *  1) retain TextView/contentDescription hooks from SHADOW1,
 *  2) query View.findViewsWithText as a cheap framework path,
 *  3) inspect AccessibilityNodeInfo / AccessibilityNodeProvider virtual nodes,
 *  4) run a low-frequency scan only while a Facebook Activity is resumed,
 *  5) collapse the nearest plausible Litho/feed-row root, never the decor root.
 */
public final class FacebookAdShield526 implements IXposedHookLoadPackage {
    private static final String TARGET_PACKAGE = "com.facebook.katana";
    private static final String TARGET_VERSION = "526.1.0.66.75";
    private static final String TAG = "DJAEGER-FB526";

    private static final AtomicBoolean INSTALLED = new AtomicBoolean(false);
    private static final Set<View> HIDDEN = Collections.newSetFromMap(new WeakHashMap<>());
    private static final Map<Activity, Integer> ACTIVE_SCANS = Collections.synchronizedMap(new WeakHashMap<>());
    private static final AtomicInteger NEXT_SCAN_TOKEN = new AtomicInteger(1);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private static final long ACTIVE_SCAN_INTERVAL_MS = 900L;
    private static final int MAX_TREE_NODES = 1400;

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
                XposedBridge.log(TAG + " SHADOW2 active on Facebook " + version);
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
                if (isSponsoredMarker(tv.getText())) queueHide(tv, "text");
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
                    if (isSponsoredMarker(v.getContentDescription())) queueHide(v, "contentDescription");
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
                    startActivityScanner(a);
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + " Activity.onResume hook unavailable: " + t);
        }

        try {
            XposedHelpers.findAndHookMethod(Activity.class, "onPause", new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    Activity a = (Activity) param.thisObject;
                    ACTIVE_SCANS.remove(a);
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + " Activity.onPause hook unavailable: " + t);
        }
    }

    private static void startActivityScanner(Activity activity) {
        if (activity == null) return;
        int token = NEXT_SCAN_TOKEN.incrementAndGet();
        ACTIVE_SCANS.put(activity, token);
        WeakReference<Activity> ref = new WeakReference<>(activity);

        Runnable loop = new Runnable() {
            @Override
            public void run() {
                Activity a = ref.get();
                if (a == null || a.isFinishing()) return;
                Integer current = ACTIVE_SCANS.get(a);
                if (current == null || current != token) return;

                View decor = a.getWindow() == null ? null : a.getWindow().getDecorView();
                if (decor != null && decor.isAttachedToWindow()) {
                    scanActivityRoot(decor);
                }
                MAIN.postDelayed(this, ACTIVE_SCAN_INTERVAL_MS);
            }
        };

        MAIN.postDelayed(loop, 250L);
    }

    private static void scanActivityRoot(View decor) {
        // Android framework path.  Some custom views expose their visible text
        // here even when they are not TextView instances.
        try {
            ArrayList<View> hits = new ArrayList<>();
            int flags = View.FIND_VIEWS_WITH_TEXT | View.FIND_VIEWS_WITH_CONTENT_DESCRIPTION;
            decor.findViewsWithText(hits, "Bersponsor", flags);
            decor.findViewsWithText(hits, "Sponsored", flags);
            for (View hit : hits) {
                if (hit != null && hit != decor) queueHide(hit, "findViewsWithText");
            }
        } catch (Throwable ignored) {
        }

        scanTree(decor, 0, new int[]{0});
    }

    private static boolean isSponsoredMarker(CharSequence cs) {
        if (cs == null) return false;
        String s = cs.toString().trim();
        if (s.isEmpty() || s.length() > 96) return false;
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

    private static void queueHide(final View marker, final String source) {
        if (marker == null) return;
        marker.post(() -> hideContainingUnit(marker, source));
        marker.postDelayed(() -> hideContainingUnit(marker, source), 120L);
    }

    private static void hideContainingUnit(View marker, String source) {
        if (marker == null || !marker.isAttachedToWindow()) return;
        View root = findFeedUnitRoot(marker);
        if (root == null || root == marker.getRootView()) return;

        synchronized (HIDDEN) {
            if (HIDDEN.contains(root)) return;
            HIDDEN.add(root);
        }
        collapse(root);
        XposedBridge.log(TAG + " hidden sponsored unit source=" + source
                + " root=" + root.getClass().getName());
    }

    private static View findFeedUnitRoot(View marker) {
        View current = marker;
        View sizeFallback = null;
        View rootView = marker.getRootView();
        int screenWidth = rootView == null ? 0 : rootView.getWidth();
        int screenHeight = rootView == null ? 0 : rootView.getHeight();
        float density = marker.getResources().getDisplayMetrics().density;
        int minCardHeight = (int) (140f * density);

        for (int depth = 0; depth < 18 && current != null; depth++) {
            String cn = current.getClass().getName().toLowerCase(Locale.ROOT);
            if (cn.contains("lithoview") && current.getHeight() >= minCardHeight) {
                return current;
            }

            if (depth >= 1 && screenWidth > 0
                    && current.getWidth() >= (int) (screenWidth * 0.80f)
                    && current.getHeight() >= minCardHeight
                    && (screenHeight <= 0 || current.getHeight() < (int) (screenHeight * 0.90f))
                    && sizeFallback == null) {
                sizeFallback = current;
            }

            ViewParent parent = current.getParent();
            if (!(parent instanceof View)) break;
            View parentView = (View) parent;
            String pn = parentView.getClass().getName().toLowerCase(Locale.ROOT);
            if (pn.contains("recyclerview") || pn.contains("listview") || pn.contains("viewpager")) {
                if (current != rootView && current.getHeight() >= minCardHeight) return current;
                break;
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

    private static boolean accessibilitySaysSponsored(View v) {
        // Avoid ever using a whole-screen host as the hide target.
        if (v == null || v == v.getRootView()) return false;

        try {
            AccessibilityNodeInfo info = v.createAccessibilityNodeInfo();
            if (info != null) {
                try {
                    if (isSponsoredMarker(info.getText()) || isSponsoredMarker(info.getContentDescription())) {
                        return true;
                    }
                } finally {
                    info.recycle();
                }
            }
        } catch (Throwable ignored) {
        }

        try {
            AccessibilityNodeProvider provider = v.getAccessibilityNodeProvider();
            if (provider == null) return false;

            // Litho commonly exposes text as virtual accessibility children.
            if (providerContains(provider, "Bersponsor")) return true;
            if (providerContains(provider, "Sponsored")) return true;
        } catch (Throwable ignored) {
        }
        return false;
    }

    private static boolean providerContains(AccessibilityNodeProvider provider, String text) {
        List<AccessibilityNodeInfo> list = null;
        try {
            list = provider.findAccessibilityNodeInfosByText(text, AccessibilityNodeProvider.HOST_VIEW_ID);
            return list != null && !list.isEmpty();
        } catch (Throwable ignored) {
            return false;
        } finally {
            if (list != null) {
                for (AccessibilityNodeInfo info : list) {
                    if (info != null) {
                        try { info.recycle(); } catch (Throwable ignored) {}
                    }
                }
            }
        }
    }

    private static boolean plausibleAccessibilityHost(View v) {
        if (v == null || v == v.getRootView()) return false;
        String cn = v.getClass().getName().toLowerCase(Locale.ROOT);
        if (cn.contains("litho")) return true;

        View root = v.getRootView();
        int sw = root == null ? 0 : root.getWidth();
        int sh = root == null ? 0 : root.getHeight();
        if (sw <= 0 || sh <= 0) return true;
        return v.getWidth() >= (int) (sw * 0.55f) && v.getHeight() < (int) (sh * 0.90f);
    }

    private static void scanTree(View v, int depth, int[] count) {
        if (v == null || depth > 26 || count[0]++ > MAX_TREE_NODES) return;

        if (v instanceof TextView && isSponsoredMarker(((TextView) v).getText())) {
            hideContainingUnit(v, "tree-text");
            return;
        }
        if (isSponsoredMarker(v.getContentDescription())) {
            hideContainingUnit(v, "tree-contentDescription");
            return;
        }

        if (plausibleAccessibilityHost(v) && accessibilitySaysSponsored(v)) {
            hideContainingUnit(v, "accessibility-virtual-node");
            return;
        }

        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            int n = g.getChildCount();
            for (int i = 0; i < n; i++) {
                scanTree(g.getChildAt(i), depth + 1, count);
                if (count[0] > MAX_TREE_NODES) return;
            }
        }
    }
}
