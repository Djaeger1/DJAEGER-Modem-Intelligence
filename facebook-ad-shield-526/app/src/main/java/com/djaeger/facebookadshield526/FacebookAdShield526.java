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
import java.lang.reflect.Array;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.ArrayList;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.WeakHashMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * DJAEGER Facebook Ad Shield 526 - SHADOW3.
 *
 * Strict target: com.facebook.katana 526.1.0.66.75 only.
 * Recommended LSPosed scope: Facebook only.
 *
 * SHADOW3 moves the primary decision point below the visible "Bersponsor"
 * label.  It inspects the object graph supplied to LithoView setComponent*
 * calls and visible LithoView hosts for strong GraphQL/feed ad signals such
 * as SPONSORED categories and known ad feed-unit classes.  The SHADOW2 UI /
 * accessibility detector remains as a bounded fallback.
 *
 * No DNS, account/session, network, storage or other-app modification.
 */
public final class FacebookAdShield526 implements IXposedHookLoadPackage {
    private static final String TARGET_PACKAGE = "com.facebook.katana";
    private static final String TARGET_VERSION = "526.1.0.66.75";
    private static final String TAG = "DJAEGER-FB526";

    private static final AtomicBoolean INSTALLED = new AtomicBoolean(false);
    private static final Handler MAIN = new Handler(Looper.getMainLooper());
    private static final Set<View> HIDDEN = Collections.newSetFromMap(new WeakHashMap<>());
    private static final Map<View, SavedLayout> SAVED_LAYOUTS = Collections.synchronizedMap(new WeakHashMap<>());
    private static final Map<Activity, Integer> ACTIVE_SCANS = Collections.synchronizedMap(new WeakHashMap<>());
    private static final Set<String> HOOKED_METHODS = ConcurrentHashMap.newKeySet();
    private static final AtomicInteger NEXT_SCAN_TOKEN = new AtomicInteger(1);
    private static final AtomicInteger STRUCTURAL_HITS = new AtomicInteger(0);

    private static final long ACTIVE_SCAN_INTERVAL_MS = 1000L;
    private static final int MAX_TREE_NODES = 1300;
    private static final int MAX_STRUCTURAL_HOSTS_PER_SCAN = 10;
    private static final int MAX_GRAPH_OBJECTS = 150;
    private static final int MAX_GRAPH_DEPTH = 6;

    private static final String[] AD_ENUMS = {
            "SPONSORED", "PROMOTION", "AD", "ADVERTISEMENT", "BANNER"
    };
    private static final String[] SAFE_ENUMS = {
            "FB_SHORTS", "MULTI_FB_STORIES_TRAY"
    };
    private static final String[] AD_CLASS_TOKENS = {
            "graphqlfbmultiadsfeedunit",
            "graphqlquickpromotionnativetemplatefeedunit",
            "sponsoredstory",
            "reelsbannerad",
            "banneradfeedunit"
    };

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

                ClassLoader loader = context.getClassLoader();
                installLithoHooks(loader);
                installUiFallbackHooks();
                XposedBridge.log(TAG + " SHADOW3 active on Facebook " + version);
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

    /**
     * Event-driven structural path.  Litho is Facebook's feed renderer; the
     * component/tree object is available before the row is drawn.  We only
     * hook void setComponent* methods and only suppress a call when the
     * supplied object has a strong sponsored classification.
     */
    private static void installLithoHooks(ClassLoader loader) {
        String[] candidates = {
                "com.facebook.litho.LithoView",
                "com.facebook.litho.widget.LithoView"
        };

        int hooked = 0;
        for (String name : candidates) {
            try {
                Class<?> cls = Class.forName(name, false, loader);
                hooked += hookLithoSetters(cls);
            } catch (Throwable ignored) {
            }
        }
        XposedBridge.log(TAG + " SHADOW3 Litho setter hooks=" + hooked);
    }

    private static int hookLithoSetters(Class<?> cls) {
        if (cls == null || !View.class.isAssignableFrom(cls)) return 0;
        int count = 0;

        ArrayList<Method> methods = new ArrayList<>();
        try { Collections.addAll(methods, cls.getDeclaredMethods()); } catch (Throwable ignored) {}
        try { Collections.addAll(methods, cls.getMethods()); } catch (Throwable ignored) {}

        for (Method method : methods) {
            try {
                if (Modifier.isStatic(method.getModifiers())) continue;
                if (method.getReturnType() != Void.TYPE) continue;
                Class<?>[] p = method.getParameterTypes();
                if (p.length < 1 || p.length > 3 || p[0].isPrimitive()) continue;

                String mn = method.getName().toLowerCase(Locale.ROOT);
                String p0 = p[0].getName().toLowerCase(Locale.ROOT);
                boolean namedSetter = mn.startsWith("setcomponent");
                boolean lithoShape = p0.contains("com.facebook.litho.component")
                        || p0.contains("com.facebook.litho.componenttree");
                if (!namedSetter && !lithoShape) continue;

                String key = method.getDeclaringClass().getName() + "#" + method.toGenericString();
                if (!HOOKED_METHODS.add(key)) continue;

                method.setAccessible(true);
                XposedBridge.hookMethod(method, new XC_MethodHook() {
                    @Override
                    protected void beforeHookedMethod(MethodHookParam param) {
                        if (!(param.thisObject instanceof View)) return;
                        View host = (View) param.thisObject;
                        Object component = (param.args == null || param.args.length == 0) ? null : param.args[0];
                        if (component == null) return;

                        boolean sponsored = structuralSaysSponsored(component);
                        if (sponsored) {
                            STRUCTURAL_HITS.incrementAndGet();
                            hideHost(host, "litho-setter:" + method.getName());
                            // All methods hooked here are void.  Returning null skips
                            // installation of the sponsored component into the host.
                            param.setResult(null);
                        } else {
                            restoreIfHidden(host);
                        }
                    }
                });
                count++;
            } catch (Throwable t) {
                XposedBridge.log(TAG + " Litho hook skipped: " + t);
            }
        }
        return count;
    }

    private static void installUiFallbackHooks() {
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
                    startActivityScanner((Activity) param.thisObject);
                }
            });
        } catch (Throwable t) {
            XposedBridge.log(TAG + " Activity.onResume hook unavailable: " + t);
        }
        try {
            XposedHelpers.findAndHookMethod(Activity.class, "onPause", new XC_MethodHook() {
                @Override
                protected void afterHookedMethod(MethodHookParam param) {
                    ACTIVE_SCANS.remove((Activity) param.thisObject);
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
                if (decor != null && decor.isAttachedToWindow()) scanActivityRoot(decor);
                MAIN.postDelayed(this, ACTIVE_SCAN_INTERVAL_MS);
            }
        };
        MAIN.postDelayed(loop, 250L);
    }

    private static void scanActivityRoot(View decor) {
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

        scanTree(decor, 0, new int[]{0}, new int[]{0});
    }

    private static boolean isSponsoredMarker(CharSequence cs) {
        if (cs == null) return false;
        String s = cs.toString().trim();
        if (s.isEmpty() || s.length() > 160) return false;
        String n = s.toLowerCase(Locale.ROOT)
                .replace('\u00a0', ' ')
                .replace("•", "·")
                .trim();
        // Facebook 526 may expose the row as one accessibility string that
        // includes the page name + marker, so SHADOW3 accepts contained
        // markers rather than only exact TextView labels.
        return n.equals("bersponsor")
                || n.startsWith("bersponsor ·")
                || n.contains(" bersponsor")
                || n.equals("sponsored")
                || n.startsWith("sponsored ·")
                || n.contains(" sponsored");
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
        hideHost(root, source);
    }

    private static void hideHost(View root, String source) {
        if (root == null || root == root.getRootView()) return;
        synchronized (HIDDEN) {
            if (HIDDEN.contains(root)) return;
            HIDDEN.add(root);
        }
        collapse(root);
        XposedBridge.log(TAG + " hidden sponsored unit source=" + source
                + " root=" + root.getClass().getName()
                + " structuralHits=" + STRUCTURAL_HITS.get());
    }

    private static View findFeedUnitRoot(View marker) {
        View current = marker;
        View sizeFallback = null;
        View rootView = marker.getRootView();
        int screenWidth = rootView == null ? 0 : rootView.getWidth();
        int screenHeight = rootView == null ? 0 : rootView.getHeight();
        float density = marker.getResources().getDisplayMetrics().density;
        int minCardHeight = (int) (120f * density);

        for (int depth = 0; depth < 18 && current != null; depth++) {
            String cn = current.getClass().getName().toLowerCase(Locale.ROOT);
            if (cn.contains("lithoview") && current.getHeight() >= minCardHeight) return current;

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
            if (!SAVED_LAYOUTS.containsKey(root)) SAVED_LAYOUTS.put(root, SavedLayout.capture(root));
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

    private static void restoreIfHidden(View host) {
        if (host == null) return;
        SavedLayout saved = SAVED_LAYOUTS.remove(host);
        synchronized (HIDDEN) { HIDDEN.remove(host); }
        if (saved == null) return;
        try {
            host.setVisibility(saved.visibility);
            host.setAlpha(saved.alpha);
            host.setImportantForAccessibility(saved.importantForAccessibility);
            ViewGroup.LayoutParams lp = host.getLayoutParams();
            if (lp != null) {
                lp.height = saved.height;
                if (lp instanceof ViewGroup.MarginLayoutParams) {
                    ViewGroup.MarginLayoutParams mlp = (ViewGroup.MarginLayoutParams) lp;
                    mlp.topMargin = saved.topMargin;
                    mlp.bottomMargin = saved.bottomMargin;
                }
                host.setLayoutParams(lp);
            }
            host.requestLayout();
        } catch (Throwable t) {
            XposedBridge.log(TAG + " restore failed: " + t);
        }
    }

    /** Structural classifier inspired by the upstream feed-guard idea, but
     * implemented without DexKit so it can backport to fixed Facebook 526.
     * Exact enum/category values and known GraphQL ad-unit classes are strong
     * signals.  Safe container categories outrank deeper nested ad children.
     */
    private static boolean structuralSaysSponsored(Object root) {
        if (root == null) return false;
        ScanResult result = new ScanResult();
        IdentityHashMap<Object, Boolean> seen = new IdentityHashMap<>();
        inspectObject(root, 0, new int[]{0}, seen, result);
        return result.adDepth < result.safeDepth;
    }

    private static void inspectObject(Object obj, int depth, int[] budget,
                                      IdentityHashMap<Object, Boolean> seen,
                                      ScanResult result) {
        if (obj == null || depth > MAX_GRAPH_DEPTH || budget[0]++ >= MAX_GRAPH_OBJECTS) return;
        if (result.adDepth == 0) return;

        Class<?> cls = obj.getClass();
        if (!cls.isPrimitive()) {
            if (seen.put(obj, Boolean.TRUE) != null) return;
        }

        if (obj instanceof Enum<?>) {
            String n = ((Enum<?>) obj).name();
            noteEnum(n, depth, result);
            return;
        }
        if (obj instanceof CharSequence) {
            noteString(obj.toString(), depth, result);
            return;
        }
        if (obj instanceof Number || obj instanceof Boolean || obj instanceof Character
                || obj instanceof Class<?> || obj instanceof ClassLoader || obj instanceof Thread
                || obj instanceof Handler || obj instanceof Context) {
            return;
        }

        String className = cls.getName();
        String lowerClass = className.toLowerCase(Locale.ROOT);
        for (String token : AD_CLASS_TOKENS) {
            if (lowerClass.contains(token)) {
                result.adDepth = Math.min(result.adDepth, depth);
                break;
            }
        }

        if (cls.isArray()) {
            int n = Math.min(Array.getLength(obj), 18);
            for (int i = 0; i < n; i++) {
                inspectObject(Array.get(obj, i), depth + 1, budget, seen, result);
            }
            return;
        }

        if (obj instanceof Iterable<?>) {
            int i = 0;
            for (Object value : (Iterable<?>) obj) {
                inspectObject(value, depth + 1, budget, seen, result);
                if (++i >= 18 || budget[0] >= MAX_GRAPH_OBJECTS) break;
            }
            return;
        }

        if (obj instanceof Map<?, ?>) {
            int i = 0;
            for (Map.Entry<?, ?> e : ((Map<?, ?>) obj).entrySet()) {
                inspectObject(e.getKey(), depth + 1, budget, seen, result);
                inspectObject(e.getValue(), depth + 1, budget, seen, result);
                if (++i >= 14 || budget[0] >= MAX_GRAPH_OBJECTS) break;
            }
            return;
        }

        if (!shouldDescendInto(className, depth)) return;

        Class<?> cursor = cls;
        int classLevels = 0;
        while (cursor != null && cursor != Object.class && classLevels++ < 5) {
            Field[] fields;
            try {
                fields = cursor.getDeclaredFields();
            } catch (Throwable t) {
                break;
            }
            int fieldsSeen = 0;
            for (Field f : fields) {
                if (fieldsSeen++ >= 42 || budget[0] >= MAX_GRAPH_OBJECTS) break;
                if (Modifier.isStatic(f.getModifiers()) || f.isSynthetic()) continue;
                try {
                    f.setAccessible(true);
                    Object value = f.get(obj);
                    if (value == null) continue;

                    String fn = f.getName().toLowerCase(Locale.ROOT);
                    if (value instanceof Boolean && Boolean.TRUE.equals(value)
                            && (fn.contains("sponsor") || fn.contains("advert"))) {
                        result.adDepth = Math.min(result.adDepth, depth + 1);
                        continue;
                    }
                    inspectObject(value, depth + 1, budget, seen, result);
                } catch (Throwable ignored) {
                }
            }
            cursor = cursor.getSuperclass();
        }
    }

    private static boolean shouldDescendInto(String className, int depth) {
        if (depth >= MAX_GRAPH_DEPTH) return false;
        if (className == null) return false;
        return className.startsWith("com.facebook.")
                || className.startsWith("X.")
                || className.startsWith("com.google.common.collect.")
                || className.startsWith("java.util.");
    }

    private static void noteEnum(String value, int depth, ScanResult result) {
        if (value == null) return;
        String n = value.toUpperCase(Locale.ROOT);
        for (String safe : SAFE_ENUMS) {
            if (safe.equals(n)) {
                result.safeDepth = Math.min(result.safeDepth, depth);
                return;
            }
        }
        for (String ad : AD_ENUMS) {
            if (ad.equals(n)) {
                result.adDepth = Math.min(result.adDepth, depth);
                return;
            }
        }
    }

    private static void noteString(String value, int depth, ScanResult result) {
        if (value == null) return;
        String s = value.trim();
        if (s.isEmpty() || s.length() > 180) return;
        String n = s.toUpperCase(Locale.ROOT);
        for (String safe : SAFE_ENUMS) {
            if (safe.equals(n)) {
                result.safeDepth = Math.min(result.safeDepth, depth);
                return;
            }
        }
        if ("SPONSORED".equals(n) || "ADVERTISEMENT".equals(n)
                || "BERSponsor".equalsIgnoreCase(s)) {
            result.adDepth = Math.min(result.adDepth, depth);
            return;
        }
        String lower = s.toLowerCase(Locale.ROOT);
        if (lower.length() <= 160 && (lower.contains("bersponsor") || lower.contains("sponsored"))) {
            result.adDepth = Math.min(result.adDepth, depth);
        }
    }

    private static boolean accessibilitySaysSponsored(View v) {
        if (v == null || v == v.getRootView()) return false;
        try {
            AccessibilityNodeInfo info = v.createAccessibilityNodeInfo();
            if (info != null) {
                try {
                    if (isSponsoredMarker(info.getText()) || isSponsoredMarker(info.getContentDescription())) return true;
                } finally {
                    info.recycle();
                }
            }
        } catch (Throwable ignored) {
        }

        try {
            AccessibilityNodeProvider provider = v.getAccessibilityNodeProvider();
            if (provider == null) return false;
            if (providerContains(provider, "Bersponsor")) return true;
            if (providerContains(provider, "Sponsored")) return true;
        } catch (Throwable ignored) {
        }
        return false;
    }

    private static boolean providerContains(AccessibilityNodeProvider provider, String text) {
        java.util.List<AccessibilityNodeInfo> list = null;
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

    private static void scanTree(View v, int depth, int[] count, int[] structuralChecks) {
        if (v == null || depth > 26 || count[0]++ > MAX_TREE_NODES) return;

        if (v instanceof TextView && isSponsoredMarker(((TextView) v).getText())) {
            hideContainingUnit(v, "tree-text");
            return;
        }
        if (isSponsoredMarker(v.getContentDescription())) {
            hideContainingUnit(v, "tree-contentDescription");
            return;
        }

        String cn = v.getClass().getName().toLowerCase(Locale.ROOT);
        if (cn.contains("lithoview") && structuralChecks[0] < MAX_STRUCTURAL_HOSTS_PER_SCAN) {
            structuralChecks[0]++;
            if (structuralSaysSponsored(v)) {
                STRUCTURAL_HITS.incrementAndGet();
                hideHost(v, "lithoview-object-graph");
                return;
            } else {
                restoreIfHidden(v);
            }
        }

        if (plausibleAccessibilityHost(v) && accessibilitySaysSponsored(v)) {
            hideContainingUnit(v, "accessibility-virtual-node");
            return;
        }

        if (v instanceof ViewGroup) {
            ViewGroup g = (ViewGroup) v;
            int n = g.getChildCount();
            for (int i = 0; i < n; i++) {
                scanTree(g.getChildAt(i), depth + 1, count, structuralChecks);
                if (count[0] > MAX_TREE_NODES) return;
            }
        }
    }

    private static final class ScanResult {
        int adDepth = Integer.MAX_VALUE;
        int safeDepth = Integer.MAX_VALUE;
    }

    private static final class SavedLayout {
        final int visibility;
        final float alpha;
        final int importantForAccessibility;
        final int height;
        final int topMargin;
        final int bottomMargin;

        SavedLayout(int visibility, float alpha, int importantForAccessibility,
                    int height, int topMargin, int bottomMargin) {
            this.visibility = visibility;
            this.alpha = alpha;
            this.importantForAccessibility = importantForAccessibility;
            this.height = height;
            this.topMargin = topMargin;
            this.bottomMargin = bottomMargin;
        }

        static SavedLayout capture(View v) {
            int height = ViewGroup.LayoutParams.WRAP_CONTENT;
            int top = 0;
            int bottom = 0;
            ViewGroup.LayoutParams lp = v.getLayoutParams();
            if (lp != null) {
                height = lp.height;
                if (lp instanceof ViewGroup.MarginLayoutParams) {
                    ViewGroup.MarginLayoutParams mlp = (ViewGroup.MarginLayoutParams) lp;
                    top = mlp.topMargin;
                    bottom = mlp.bottomMargin;
                }
            }
            return new SavedLayout(v.getVisibility(), v.getAlpha(), v.getImportantForAccessibility(),
                    height, top, bottom);
        }
    }
}
